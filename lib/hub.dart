import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

String safeName(String n) => n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

/// Runs on the phone that owns the hotspot. Relays chat + call signalling,
/// stores files for download, keeps a mailbox for offline members.
class Hub {
  static const port = 8080;
  final Directory dir;
  final served = <String, String>{}; // fid -> file path
  final _socks = <String, WebSocket>{};
  final _names = <String, String>{};
  final _mailbox = <String, List<String>>{};
  HttpServer? _http;

  Hub(this.dir);

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    try {
      for (final e in dir.listSync()) {
        if (e is File) {
          final n = e.uri.pathSegments.last;
          final i = n.indexOf('_');
          if (i > 0) served[n.substring(0, i)] = e.path;
        }
      }
    } catch (_) {}
    _http!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    for (final s in _socks.values) {
      try {
        await s.close();
      } catch (_) {}
    }
    _socks.clear();
    await _http?.close(force: true);
    _http = null;
  }

  Future<void> _handle(HttpRequest r) async {
    final p = r.uri.pathSegments;
    try {
      if (p.isNotEmpty && p[0] == 'ws' && WebSocketTransformer.isUpgradeRequest(r)) {
        _client(await WebSocketTransformer.upgrade(r));
      } else if (r.method == 'PUT' && p.length == 3 && p[0] == 'up') {
        final f = File('${dir.path}/${p[1]}_${safeName(p[2])}');
        final sink = f.openWrite();
        await sink.addStream(r);
        await sink.close();
        served[p[1]] = f.path;
        r.response.statusCode = 200;
        await r.response.close();
      } else if (r.method == 'GET' && p.length == 2 && p[0] == 'dl' && served[p[1]] != null) {
        final f = File(served[p[1]]!);
        r.response.headers.contentType = ContentType.binary;
        r.response.contentLength = await f.length();
        await r.response.addStream(f.openRead());
        await r.response.close();
      } else {
        r.response.statusCode = 404;
        await r.response.close();
      }
    } catch (_) {
      try {
        r.response.statusCode = 500;
        await r.response.close();
      } catch (_) {}
    }
  }

  void _client(WebSocket ws) {
    String? id;
    ws.pingInterval = const Duration(seconds: 5);
    ws.listen((d) {
      if (d is! String) {
        if (id != null) _routeBinary(id!, d as List<int>);
        return;
      }
      final m = jsonDecode(d) as Map;
      if (m['t'] == 'hello') {
        final me = m['id'] as String;
        id = me;
        _names[me] = m['name'] as String;
        final old = _socks[me];
        _socks[me] = ws;
        old?.close();
        _broadcastPeers();
        for (final x in _mailbox.remove(me) ?? <String>[]) {
          ws.add(x);
        }
        return;
      }
      if (id != null) _route(id!, m);
    }, onDone: () {
      final me = id;
      if (me != null && _socks[me] == ws) {
        _socks.remove(me);
        _broadcastPeers();
      }
    }, onError: (_) {});
  }

  /// Media frame from a client: [type][n][n x 12-byte target ids][payload]
  /// -> every target gets: [type][12-byte sender id][payload]
  void _routeBinary(String from, List<int> d) {
    if (d.length < 2) return;
    final n = d[1];
    final end = 2 + n * 12;
    if (d.length < end) return;
    final b = BytesBuilder(copy: false);
    b.addByte(d[0]);
    b.add(ascii.encode(from.padRight(12).substring(0, 12)));
    b.add(d.sublist(end));
    final out = b.takeBytes();
    for (var i = 0; i < n; i++) {
      final t = ascii.decode(d.sublist(2 + i * 12, 2 + (i + 1) * 12)).trim();
      _socks[t]?.add(out);
    }
  }

  void _route(String from, Map m) {
    m['from'] = from;
    m['fromName'] = _names[from];
    final to = m['to'] as String?;
    final isMsg = m['t'] == 'msg';
    List<String> targets;
    if (to == 'all') {
      targets = _names.keys.where((k) => k != from).toList();
    } else if (to != null && to.startsWith('g:')) {
      targets = [for (final x in (m['members'] as List? ?? [])) x as String]
          .where((k) => k != from)
          .toList();
    } else {
      targets = to == null ? [] : [to];
    }
    final out = jsonEncode(m);
    for (final t in targets) {
      final s = _socks[t];
      if (s != null) {
        s.add(out);
      } else if (isMsg) {
        (_mailbox[t] ??= []).add(out);
      }
    }
    if (isMsg) _socks[from]?.add(jsonEncode({'t': 'ack', 'mid': m['mid']}));
  }

  void _broadcastPeers() {
    final list = [
      for (final e in _names.entries)
        {'id': e.key, 'name': e.value, 'online': _socks.containsKey(e.key)}
    ];
    final s = jsonEncode({'t': 'peers', 'list': list});
    for (final w in _socks.values) {
      w.add(s);
    }
  }
}
