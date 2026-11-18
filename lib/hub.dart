import 'dart:convert';
import 'dart:io';

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
      final m = jsonDecode(d as String) as Map;
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
