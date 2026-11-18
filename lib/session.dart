import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'hub.dart';
import 'models.dart';
import 'store.dart';

class Peer {
  String name;
  bool online;
  Peer(this.name, this.online);
}

class CallPeer {
  final String id;
  final RTCVideoRenderer r = RTCVideoRenderer();
  late final Future<void> ready;
  Future<RTCPeerConnection>? pcf;
  RTCPeerConnection? pc;
  bool present = false, connected = false, remoteSet = false, offered = false;
  final pending = <RTCIceCandidate>[];
  CallPeer(this.id) {
    ready = r.initialize();
  }
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
    final c = HttpClient();
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

  Future<void> retryDownload(Msg m) => _download(m);

  Future<void> _download(Msg m) async {
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
    final c = HttpClient();
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
    } catch (_) {
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
    final m = jsonDecode(d as String) as Map;
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
      case 'rtc':
        _onRtc(m);
        break;
    }
  }

  // ================= calls (mesh WebRTC over the hotspot LAN) =================
  bool inCall = false, iAmCaller = false, callVideo = false;
  bool muted = false, camOff = false, speaker = false;
  String? cid, callThread;
  List<String> all = [];
  final invited = <String>{};
  final cps = <String, CallPeer>{};
  Map<String, dynamic>? incoming;
  MediaStream? local;
  final localR = RTCVideoRenderer();
  bool _localInit = false;
  DateTime? _t0;
  Timer? _ringTimer, _inTimer;

  int get callSeconds => _t0 == null ? 0 : DateTime.now().difference(_t0!).inSeconds;
  String _mmss(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  String mmss(int s) => _mmss(s);

  Future<bool> _openMedia(bool video) async {
    try {
      if (!_localInit) {
        await localR.initialize();
        _localInit = true;
      }
      local = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video ? {'facingMode': 'user'} : false,
      });
      localR.srcObject = local;
      muted = false;
      camOff = false;
      speaker = video;
      try {
        await Helper.setSpeakerphoneOn(speaker);
      } catch (_) {}
      return true;
    } catch (e) {
      onNotice?.call('ক্যামেরা/মাইক্রোফোন চালু করা যায়নি (পারমিশন দিন)');
      return false;
    }
  }

  CallPeer _cp(String id) => cps.putIfAbsent(id, () => CallPeer(id));

  Future<void> startCall(String thread, bool video) async {
    if (inCall || incoming != null) return;
    final targets = callTargets(thread);
    if (targets.isEmpty) {
      onNotice?.call('কেউ অনলাইনে নেই');
      return;
    }
    if (!await _openMedia(video)) return;
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
      if (inCall && !cps.values.any((c) => c.present)) hangup();
    });
  }

  String _threadOfInvite(Map m) {
    final th = (m['thread'] ?? '') as String;
    return (th == 'all' || th.startsWith('g:')) ? th : m['from'] as String;
  }

  void _onInvite(Map m) {
    if (inCall || incoming != null) {
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
    final inc = incoming;
    if (inc == null) return;
    incoming = null;
    _inTimer?.cancel();
    if (!await _openMedia(inc['video'] == true)) {
      declineAll(inc);
      notifyListeners();
      return;
    }
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
      if (inCall && !cps.values.any((c) => c.present)) hangup();
    });
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
    final cp = cps.remove(from);
    if (cp != null) _disposePeer(cp);
    notifyListeners();
    if (!cps.values.any((c) => c.present)) hangup();
  }

  Future<void> _present(String id) async {
    final cp = _cp(id);
    cp.present = true;
    invited.remove(id);
    _ringTimer?.cancel();
    notifyListeners();
    // exactly one side of every pair sends the offer: the smaller id
    if (myId.compareTo(id) < 0 && !cp.offered) {
      cp.offered = true;
      final pc = await _pcFor(id);
      final o = await pc.createOffer();
      await pc.setLocalDescription(o);
      _send({'t': 'rtc', 'to': id, 'cid': cid, 'k': 'offer', 'd': o.toMap()});
    }
  }

  Future<RTCPeerConnection> _pcFor(String id) {
    final cp = _cp(id);
    return cp.pcf ??= _makePc(cp);
  }

  Future<RTCPeerConnection> _makePc(CallPeer cp) async {
    final pc = await createPeerConnection({'iceServers': <Map>[]});
    cp.pc = pc;
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _send({'t': 'rtc', 'to': cp.id, 'cid': cid, 'k': 'cand', 'd': c.toMap()});
      }
    };
    pc.onTrack = (e) async {
      if (e.streams.isNotEmpty) {
        await cp.ready;
        cp.r.srcObject = e.streams.first;
        notifyListeners();
      }
    };
    pc.onConnectionState = (s) {
      cp.connected = s == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      if (cp.connected) _t0 ??= DateTime.now();
      notifyListeners();
    };
    for (final t in local!.getTracks()) {
      await pc.addTrack(t, local!);
    }
    return pc;
  }

  Future<void> _onRtc(Map m) async {
    if (!inCall || m['cid'] != cid) return;
    final from = m['from'] as String;
    final cp = _cp(from);
    final pc = await _pcFor(from);
    final d = m['d'];
    switch (m['k']) {
      case 'offer':
        cp.present = true;
        await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
        cp.remoteSet = true;
        await _flushCands(cp);
        final a = await pc.createAnswer();
        await pc.setLocalDescription(a);
        _send({'t': 'rtc', 'to': from, 'cid': cid, 'k': 'answer', 'd': a.toMap()});
        notifyListeners();
        break;
      case 'answer':
        await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
        cp.remoteSet = true;
        await _flushCands(cp);
        break;
      case 'cand':
        final c = RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']);
        if (cp.remoteSet) {
          await pc.addCandidate(c);
        } else {
          cp.pending.add(c);
        }
        break;
    }
  }

  Future<void> _flushCands(CallPeer cp) async {
    for (final c in cp.pending) {
      await cp.pc?.addCandidate(c);
    }
    cp.pending.clear();
  }

  void _disposePeer(CallPeer cp) {
    cp.pc?.close();
    cp.r.srcObject = null;
    Future.delayed(const Duration(milliseconds: 400), () => cp.r.dispose());
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
    final old = cps.values.toList();
    cps.clear();
    inCall = false;
    cid = null;
    all = [];
    invited.clear();
    _t0 = null;
    final l = local;
    local = null;
    localR.srcObject = null;
    notifyListeners();
    for (final t in l?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await l?.dispose();
    for (final cp in old) {
      _disposePeer(cp);
    }
    if (secs != null) {
      _sysLocal(th, 'কল শেষ • ${_mmss(secs)}');
    } else if (caller) {
      _sysLocal(th, 'অনুত্তরিত কল');
    }
  }

  void toggleMute() {
    muted = !muted;
    for (final t in local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  void toggleCam() {
    camOff = !camOff;
    for (final t in local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !camOff;
    }
    notifyListeners();
  }

  Future<void> switchCam() async {
    final v = local?.getVideoTracks();
    if (v != null && v.isNotEmpty) await Helper.switchCamera(v.first);
  }

  void toggleSpeaker() {
    speaker = !speaker;
    Helper.setSpeakerphoneOn(speaker);
    notifyListeners();
  }
}

final app = Session();
