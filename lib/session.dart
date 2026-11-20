import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gal/gal.dart';
import 'package:record/record.dart';
import 'discovery.dart';
import 'hub.dart';
import 'media.dart';
import 'models.dart';
import 'store.dart';

class Peer {
  String name;
  bool online;
  Peer(this.name, this.online);
}

class CallPeer {
  final String id;
  bool present = false;
  Uint8List? frame; // latest video frame (JPEG)
  int rot = 0; // quarter turns to rotate the frame clockwise
  CallPeer(this.id);
}

Future<List<String>> localIps() async {
  final l = await NetworkInterface.list(type: InternetAddressType.IPv4);
  return [
    for (final i in l)
      for (final a in i.addresses)
        if (!a.address.startsWith('127.')) a.address
  ];
}

class Session extends ChangeNotifier {
  final store = Store();
  Hub? hub;
  List<String> hubIps = [];
  WebSocket? _ws;
  Announcer? _ann;
  String _host = '';
  bool _want = false;
  final peers = <String, Peer>{};
  String? openThread;
  void Function(String)? onNotice;
  Timer? _nt;

  bool get online => _ws != null;
  String get myId => store.id;
  String get myName => store.name;

  Future<void> init() async {
    await store.load();
    if (store.id.isEmpty) {
      store.id = Store.rid();
      store.save();
    }
  }

  void setName(String n) {
    store.name = n.trim();
    store.save();
  }

  void _tick() {
    _nt ??= Timer(const Duration(milliseconds: 150), () {
      _nt = null;
      notifyListeners();
    });
  }

  // ================= connection =================
  Future<void> startHost() async {
    hub = Hub(store.media);
    await hub!.start();
    hubIps = await localIps();
    try {
      _ann = Announcer();
      await _ann!.start(myName);
    } catch (_) {}
    _host = '127.0.0.1';
    _want = true;
    await _open();
  }

  Future<void> startJoin(String ip) async {
    _host = ip;
    _want = true;
    await _open();
  }

  Future<void> _open() async {
    final ws = await WebSocket.connect('ws://$_host:${Hub.port}/ws')
        .timeout(const Duration(seconds: 6));
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 5);
    ws.add(jsonEncode({'t': 'hello', 'id': myId, 'name': myName}));
    ws.listen(_onData, onDone: () => _lost(ws), onError: (_) => _lost(ws));
    notifyListeners();
    _flushOutbox();
    _retryDownloads();
  }

  void _lost(WebSocket ws) {
    if (_ws != ws) return;
    _ws = null;
    for (final p in peers.values) {
      p.online = false;
    }
    notifyListeners();
    if (_want) Timer(const Duration(seconds: 3), _retry);
  }

  Future<void> _retry() async {
    if (!_want || _ws != null) return;
    try {
      await _open();
    } catch (_) {
      if (_want) Timer(const Duration(seconds: 3), _retry);
    }
  }

  Future<void> leave() async {
    _want = false;
    if (inCall) hangup();
    final w = _ws;
    _ws = null;
    await w?.close();
    _ann?.stop();
    _ann = null;
    await hub?.stop();
    hub = null;
    peers.clear();
    notifyListeners();
  }

  bool _send(Map m) {
    final w = _ws;
    if (w == null) return false;
    w.add(jsonEncode(m));
    return true;
  }

  // ================= contacts / threads =================
  String nameOf(String id) => peers[id]?.name ?? store.names[id] ?? 'অজানা';
  bool isOnline(String id) => peers[id]?.online ?? false;
  List<String> get contactIds =>
      {...store.names.keys, ...peers.keys}.where((k) => k != myId).toList();

  String titleOf(String t) {
    if (t == 'all') return 'সবাই (গ্রুপ)';
    if (t.startsWith('g:')) return store.groups[t.substring(2)]?.name ?? 'গ্রুপ';
    return nameOf(t);
  }

  List<String> get threadIds {
    final l = <String>['all', ...store.groups.keys.map((g) => 'g:$g'), ...contactIds];
    l.sort((a, b) => (store.last(b)?.ts ?? 0).compareTo(store.last(a)?.ts ?? 0));
    return l;
  }

  List<String> membersOf(String t) {
    if (t == 'all') return peers.keys.where((k) => k != myId).toList();
    if (t.startsWith('g:')) {
      return (store.groups[t.substring(2)]?.members ?? []).where((k) => k != myId).toList();
    }
    return [t];
  }

  List<String> callTargets(String t) => membersOf(t).where(isOnline).toList();

  void clearUnread(String t) {
    if (store.unread.remove(t) != null) {
      store.save();
      scheduleMicrotask(notifyListeners);
    }
  }

  String createGroup(String name, List<String> members) {
    final gid = Store.rid(8);
    store.groups[gid] = Group(gid, name, [myId, ...members]);
    _newMsg('g:$gid', 'sys', text: '$myName "$name" গ্রুপ তৈরি করেছেন');
    return 'g:$gid';
  }

  void deleteMsg(Msg m) {
    store.remove(m);
    store.save();
    notifyListeners();
  }

  // ================= messages =================
  Msg _newMsg(String thread, String kind,
      {String text = '', String? fid, String? name, String? path, int size = 0}) {
    final m = Msg(
      id: Store.rid(16), thread: thread, from: myId, fromName: myName, kind: kind,
      mine: true, text: text, fid: fid, name: name, path: path, size: size,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    store.add(m);
    store.save();
    notifyListeners();
    _push(m);
    return m;
  }

  void sendText(String thread, String text) {
    if (text.trim().isEmpty) return;
    _newMsg(thread, 'text', text: text.trim());
  }

  Future<void> sendFile(String thread, String src, {String? kind}) async {
    final name = src.split(Platform.pathSeparator).last;
    final fid = Store.rid(10);
    final dest = File('${store.media.path}/${fid}_$name');
    await File(src).copy(dest.path);
    final size = await dest.length();
    _newMsg(thread, kind ?? kindOf(name), fid: fid, name: name, path: dest.path, size: size);
  }

  final _busy = <String>{};

  Future<void> _push(Msg m) async {
    if (_ws == null || m.status != stSending || !_busy.add(m.id)) return;
    try {
      if (m.isFile && !await _upload(m)) {
        Timer(const Duration(seconds: 5), () => _push(m));
        return;
      }
      final g = m.thread.startsWith('g:') ? store.groups[m.thread.substring(2)] : null;
      _send({
        't': 'msg', 'mid': m.id, 'to': m.thread, 'kind': m.kind, 'text': m.text,
        'fid': m.fid, 'name': m.name, 'size': m.size, 'ts': m.ts,
        if (g != null) 'members': g.members,
        if (g != null) 'gname': g.name,
      });
    } finally {
      _busy.remove(m.id);
    }
  }

  void _retryDownloads() {
    final l = store.msgs
        .where((m) => !m.mine && m.isFile && m.path == null && m.dl != dlLoading)
        .toList();
    for (final m in l) {
      _download(m);
    }
  }

  void _flushOutbox() {
    for (final m in store.msgs.where((m) => m.mine && m.status == stSending).toList()) {
      _push(m);
    }
  }

  Future<bool> _upload(Msg m) async {
    if (hub != null) {
      hub!.served[m.fid!] = m.path!;
      return true;
    }
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final f = File(m.path!);
      final len = await f.length();
      var sent = 0;
      final req = await c.putUrl(Uri(
          scheme: 'http', host: _host, port: Hub.port, pathSegments: ['up', m.fid!, m.name!]));
      req.contentLength = len;
      await req.addStream(f.openRead().map((ch) {
        sent += ch.length;
        m.progress = len == 0 ? 1 : sent / len;
        _tick();
        return ch;
      }));
      final r = await req.close();
      await r.drain();
      return r.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  String _lastDlErr = '';

  Future<void> retryDownload(Msg m) async {
    await _download(m);
    if (m.dl == dlFailed) onNotice?.call('ডাউনলোড হয়নি: $_lastDlErr');
  }

  final _dling = <String>{};

  Future<void> _download(Msg m) async {
    if (!_dling.add(m.id)) return;
    try {
      await _download2(m);
      if (m.dl == dlDone && (m.kind == 'image' || m.kind == 'video')) {
        await saveToGallery(m, silent: true);
      }
    } finally {
      _dling.remove(m.id);
    }
  }

  Future<void> _download2(Msg m) async {
    if (hub != null) {
      final p = hub!.served[m.fid];
      if (p != null) {
        m.path = p;
        m.dl = dlDone;
      } else {
        m.dl = dlFailed;
      }
      store.save();
      notifyListeners();
      return;
    }
    m.dl = dlLoading;
    m.progress = 0;
    notifyListeners();
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final dest = File('${store.media.path}/${m.fid}_${safeName(m.name ?? 'file')}');
      final req = await c.getUrl(
          Uri(scheme: 'http', host: _host, port: Hub.port, pathSegments: ['dl', m.fid!]));
      final r = await req.close();
      if (r.statusCode != 200) throw 'http ${r.statusCode}';
      final sink = dest.openWrite();
      var got = 0;
      await sink.addStream(r.map((ch) {
        got += ch.length;
        m.progress = m.size == 0 ? 1 : got / m.size;
        _tick();
        return ch;
      }));
      await sink.close();
      m.path = dest.path;
      m.dl = dlDone;
    } catch (e) {
      _lastDlErr = '$e';
      m.dl = dlFailed;
    } finally {
      c.close(force: true);
    }
    store.save();
    notifyListeners();
  }

  void _onMsg(Map m) {
    final from = m['from'] as String;
    final to = m['to'] as String;
    final mid = m['mid'] as String;
    if (m['fromName'] != null) store.names[from] = m['fromName'];
    String thread;
    if (to == 'all') {
      thread = 'all';
    } else if (to.startsWith('g:')) {
      thread = to;
      store.groups.putIfAbsent(to.substring(2),
          () => Group(to.substring(2), m['gname'] ?? 'গ্রুপ', List<String>.from(m['members'] ?? [])));
    } else {
      thread = from;
    }
    _send({'t': 'dlv', 'to': from, 'mid': mid});
    if (store.has(mid)) return;
    final msg = Msg(
      id: mid, thread: thread, from: from, fromName: m['fromName'] ?? '', kind: m['kind'],
      mine: false, text: m['text'] ?? '', fid: m['fid'], name: m['name'], size: m['size'] ?? 0,
      ts: m['ts'] ?? DateTime.now().millisecondsSinceEpoch, status: stDelivered,
      dl: m['fid'] != null ? dlLoading : dlNone,
    );
    store.add(msg);
    if (openThread != thread) store.unread[thread] = (store.unread[thread] ?? 0) + 1;
    if (msg.isFile) _download(msg);
    store.save();
    notifyListeners();
  }

  void _sysLocal(String thread, String text) {
    store.add(Msg(
      id: Store.rid(16), thread: thread, from: 'sys', fromName: '', kind: 'sys', mine: false,
      text: text, ts: DateTime.now().millisecondsSinceEpoch, status: stDelivered,
    ));
    store.save();
    notifyListeners();
  }

  void _onData(dynamic d) {
    try {
      _handle(d);
    } catch (e) {
      debugPrint('msg error: $e');
    }
  }

  void _handle(dynamic d) {
    if (d is! String) {
      _onBinary(d as List<int>);
      return;
    }
    final m = jsonDecode(d) as Map;
    switch (m['t']) {
      case 'peers':
        for (final p in (m['list'] as List)) {
          final id = p['id'] as String;
          if (id == myId) continue;
          store.names[id] = p['name'];
          peers[id] = Peer(p['name'], p['online'] == true);
        }
        store.save();
        notifyListeners();
        break;
      case 'msg':
        _onMsg(m);
        break;
      case 'ack':
      case 'dlv':
        for (final x in store.msgs.reversed) {
          if (x.id == m['mid']) {
            final s = m['t'] == 'ack' ? stSent : stDelivered;
            if (x.status < s) x.status = s;
            break;
          }
        }
        store.save();
        notifyListeners();
        break;
      case 'invite':
        _onInvite(m);
        break;
      case 'decline':
        if (inCall && m['cid'] == cid) {
          invited.remove(m['from']);
          if (invited.isEmpty && !cps.values.any((c) => c.present)) hangup();
          notifyListeners();
        }
        break;
      case 'joined':
        if (inCall && m['cid'] == cid) {
          _send({'t': 'here', 'to': m['from'], 'cid': cid});
          _present(m['from']);
        }
        break;
      case 'here':
        if (inCall && m['cid'] == cid) _present(m['from']);
        break;
      case 'leave':
        _onLeave(m);
        break;
    }
  }

  // ================= calls: audio + video travel through the hub (no WebRTC) =================
  bool inCall = false, iAmCaller = false, callVideo = false;
  bool muted = false, camOff = false, speaker = false;
  String? cid, callThread;
  List<String> all = [];
  final invited = <String>{};
  final cps = <String, CallPeer>{};
  Map<String, dynamic>? incoming;
  CameraController? cam;
  CameraDescription? _camDesc;
  List<CameraDescription> _cams = [];
  DateTime? _t0;
  Timer? _ringTimer, _inTimer;
  bool _busyCall = false, _convBusy = false;
  int _lastFrameMs = 0;

  int get callSeconds => _t0 == null ? 0 : DateTime.now().difference(_t0!).inSeconds;
  String mmss(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  bool get _anyPresent => cps.values.any((c) => c.present);
  CallPeer _cp(String id) => cps.putIfAbsent(id, () => CallPeer(id));

  // ---- local devices
  Future<bool> _openMedia(bool video) async {
    try {
      final r = AudioRecorder();
      final ok = await r.hasPermission();
      await r.dispose();
      if (!ok) {
        onNotice?.call('মাইক্রোফোনের পারমিশন দিন');
        return false;
      }
      speaker = video;
      muted = false;
      camOff = false;
      final started = await Media.startAudio(speaker: speaker, onMic: _onMic);
      if (!started) {
        onNotice?.call('মাইক্রোফোন চালু করা যায়নি');
        return false;
      }
      if (video) {
        try {
          await _startCamera(CameraLensDirection.front);
        } catch (e) {
          onNotice?.call('ক্যামেরা চালু করা যায়নি: $e');
        }
      }
      return true;
    } catch (e) {
      onNotice?.call('কল শুরু করা যায়নি: $e');
      return false;
    }
  }

  Future<void> _startCamera(CameraLensDirection dir) async {
    if (_cams.isEmpty) _cams = await availableCameras();
    final d = _cams.firstWhere((c) => c.lensDirection == dir, orElse: () => _cams.first);
    final c = CameraController(d, ResolutionPreset.low,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    await c.initialize();
    _camDesc = d;
    cam = c;
    await c.startImageStream(_onCamFrame);
    notifyListeners();
  }

  Future<void> _stopCamera() async {
    final c = cam;
    cam = null;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  Future<void> _closeLocal() async {
    await _stopCamera();
    await Media.stopAudio();
  }

  void _onMic(Uint8List d) {
    if (!inCall || muted || !_anyPresent) return;
    _sendMedia(1, d);
  }

  Future<void> _onCamFrame(CameraImage img) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_convBusy || now - _lastFrameMs < 100 || camOff || !inCall || !_anyPresent) return;
    _convBusy = true;
    _lastFrameMs = now;
    try {
      final jpg = await Media.jpeg(img);
      final rot = img.width > img.height ? ((_camDesc?.sensorOrientation ?? 90) ~/ 90) % 4 : 0;
      final b = BytesBuilder(copy: false)
        ..addByte(rot)
        ..addByte(0)
        ..add(jpg);
      _sendMedia(2, b.takeBytes());
    } catch (_) {
    } finally {
      _convBusy = false;
    }
  }

  // ---- media over the hub: [type][n][n x 12-byte ids][payload]
  // type 1 = audio (PCM16 16 kHz mono, 20 ms), 2 = video frame (JPEG), 3 = camera off
  void _sendMedia(int type, Uint8List payload) {
    final w = _ws;
    if (w == null) return;
    final ids = [for (final c in cps.values) if (c.present) c.id];
    if (ids.isEmpty) return;
    final b = BytesBuilder(copy: false);
    b.addByte(type);
    b.addByte(ids.length);
    for (final id in ids) {
      b.add(ascii.encode(id.padRight(12).substring(0, 12)));
    }
    b.add(payload);
    w.add(b.takeBytes());
  }

  void _onBinary(List<int> d) {
    if (!inCall || d.length < 13) return;
    final bytes = d is Uint8List ? d : Uint8List.fromList(d);
    final type = bytes[0];
    final from = ascii.decode(Uint8List.sublistView(bytes, 1, 13)).trim();
    if (type == 1) {
      Media.play(from, Uint8List.fromList(Uint8List.sublistView(bytes, 13)));
    } else if (type == 2 && bytes.length > 15) {
      final cp = cps[from];
      if (cp == null) return;
      cp.rot = bytes[13];
      cp.frame = Uint8List.fromList(Uint8List.sublistView(bytes, 15));
      _tick();
    } else if (type == 3) {
      final cp = cps[from];
      if (cp != null) {
        cp.frame = null;
        notifyListeners();
      }
    }
  }

  // ---- call signalling
  Future<void> startCall(String thread, bool video) async {
    if (_busyCall || inCall || incoming != null) return;
    _busyCall = true;
    try {
      final targets = callTargets(thread);
      if (targets.isEmpty) {
        onNotice?.call('কেউ অনলাইনে নেই');
        return;
      }
      if (!await _openMedia(video)) {
        await _closeLocal();
        return;
      }
      cid = Store.rid(8);
      callVideo = video;
      callThread = thread;
      iAmCaller = true;
      all = [myId, ...targets];
      invited
        ..clear()
        ..addAll(targets);
      inCall = true;
      _t0 = null;
      notifyListeners();
      for (final t in targets) {
        _send({'t': 'invite', 'to': t, 'cid': cid, 'video': video, 'all': all, 'thread': thread});
      }
      _ringTimer?.cancel();
      _ringTimer = Timer(const Duration(seconds: 45), () {
        if (inCall && !_anyPresent) hangup();
      });
    } finally {
      _busyCall = false;
    }
  }

  String _threadOfInvite(Map m) {
    final th = (m['thread'] ?? '') as String;
    return (th == 'all' || th.startsWith('g:')) ? th : m['from'] as String;
  }

  void _onInvite(Map m) {
    if (inCall || incoming != null || _busyCall) {
      _send({'t': 'decline', 'to': m['from'], 'cid': m['cid']});
      return;
    }
    incoming = Map<String, dynamic>.from(m);
    notifyListeners();
    _inTimer?.cancel();
    _inTimer = Timer(const Duration(seconds: 60), () {
      if (incoming != null && incoming!['cid'] == m['cid']) {
        incoming = null;
        notifyListeners();
      }
    });
  }

  Future<void> acceptCall() async {
    if (_busyCall) return;
    final inc = incoming;
    if (inc == null) return;
    _busyCall = true;
    try {
      _inTimer?.cancel();
      final ok = await _openMedia(inc['video'] == true);
      if (!ok) {
        incoming = null;
        declineAll(inc);
        await _closeLocal();
        notifyListeners();
        return;
      }
      if (incoming == null || incoming!['cid'] != inc['cid']) {
        await _closeLocal();
        return;
      }
      incoming = null;
      cid = inc['cid'];
      callVideo = inc['video'] == true;
      callThread = _threadOfInvite(inc);
      iAmCaller = false;
      all = List<String>.from(inc['all']);
      invited
        ..clear()
        ..addAll(all.where((x) => x != myId));
      inCall = true;
      _t0 = null;
      notifyListeners();
      for (final id in all) {
        if (id != myId) _send({'t': 'joined', 'to': id, 'cid': cid});
      }
      _ringTimer?.cancel();
      _ringTimer = Timer(const Duration(seconds: 15), () {
        if (inCall && !_anyPresent) hangup();
      });
    } finally {
      _busyCall = false;
    }
  }

  void declineAll(Map inc) {
    for (final id in List<String>.from(inc['all'])) {
      if (id != myId) _send({'t': 'decline', 'to': id, 'cid': inc['cid']});
    }
  }

  void declineCall() {
    final inc = incoming;
    if (inc == null) return;
    incoming = null;
    _inTimer?.cancel();
    declineAll(inc);
    _sysLocal(_threadOfInvite(inc), 'আপনি কল প্রত্যাখ্যান করেছেন');
  }

  void _onLeave(Map m) {
    final from = m['from'];
    final inc = incoming;
    if (inc != null && inc['cid'] == m['cid'] && inc['from'] == from) {
      incoming = null;
      _inTimer?.cancel();
      _sysLocal(_threadOfInvite(inc), 'মিসড কল');
      return;
    }
    if (!inCall || m['cid'] != cid) return;
    invited.remove(from);
    cps.remove(from);
    notifyListeners();
    if (!_anyPresent) hangup();
  }

  void _present(String id) {
    final cp = _cp(id);
    cp.present = true;
    invited.remove(id);
    _ringTimer?.cancel();
    _t0 ??= DateTime.now();
    notifyListeners();
  }

  void hangup() {
    for (final id in all) {
      if (id != myId) _send({'t': 'leave', 'to': id, 'cid': cid});
    }
    _endCall();
  }

  Future<void> _endCall() async {
    if (!inCall) return;
    _ringTimer?.cancel();
    final secs = _t0 == null ? null : callSeconds;
    final th = callThread ?? 'all';
    final caller = iAmCaller;
    cps.clear();
    inCall = false;
    cid = null;
    all = [];
    invited.clear();
    _t0 = null;
    notifyListeners();
    await _closeLocal();
    if (secs != null) {
      _sysLocal(th, 'কল শেষ • ${mmss(secs)}');
    } else if (caller) {
      _sysLocal(th, 'অনুত্তরিত কল');
    }
  }

  void toggleMute() {
    muted = !muted;
    notifyListeners();
  }

  void toggleCam() {
    if (cam == null) return;
    camOff = !camOff;
    if (camOff) _sendMedia(3, Uint8List(1));
    notifyListeners();
  }

  Future<void> switchCam() async {
    final c = cam;
    if (c == null) return;
    final dir = c.description.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    await _stopCamera();
    try {
      await _startCamera(dir);
    } catch (e) {
      onNotice?.call('ক্যামেরা বদলানো যায়নি');
    }
  }

  void toggleSpeaker() {
    speaker = !speaker;
    Media.setSpeaker(speaker);
    notifyListeners();
  }

  // ================= saving received files =================
  Future<void> saveToGallery(Msg m, {bool silent = false}) async {
    try {
      if (m.path == null) return;
      if (m.kind == 'video') {
        await Gal.putVideo(m.path!);
      } else {
        await Gal.putImage(m.path!);
      }
      if (!silent) onNotice?.call('গ্যালারিতে সেভ হয়েছে');
    } catch (e) {
      if (!silent) onNotice?.call('সেভ করা যায়নি: $e');
    }
  }

  Future<void> saveToDownloads(Msg m) async {
    try {
      final dir = Directory('/storage/emulated/0/Download/HotspotLink');
      dir.createSync(recursive: true);
      await File(m.path!).copy('${dir.path}/${m.name}');
      onNotice?.call('সেভ হয়েছে: Download/HotspotLink');
    } catch (e) {
      onNotice?.call('সেভ করা যায়নি: $e');
    }
  }
}

final app = Session();
