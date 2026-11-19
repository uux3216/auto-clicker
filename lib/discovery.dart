import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const discoveryPort = 41234;

/// Host side: shouts "I am here" on the hotspot network once per second.
class Announcer {
  RawDatagramSocket? _s;
  Timer? _t;

  Future<void> start(String name) async {
    _s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _s!.broadcastEnabled = true;
    final msg = utf8.encode(jsonEncode({'app': 'hotspotlink', 'name': name}));
    _t = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final i in ifs) {
          for (final a in i.addresses) {
            if (a.isLoopback) continue;
            final p = a.rawAddress;
            final b = InternetAddress.fromRawAddress(Uint8List.fromList([p[0], p[1], p[2], 255]));
            _s?.send(msg, b, discoveryPort);
          }
        }
        _s?.send(msg, InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {}
    });
  }

  void stop() {
    _t?.cancel();
    _s?.close();
    _t = null;
    _s = null;
  }
}

/// Guest side: collects hosts that announce themselves.
class Finder {
  RawDatagramSocket? _s;
  final found = <String, String>{}; // ip -> host name
  void Function()? onChange;

  Future<void> start() async {
    _s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
    _s!.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = _s?.receive();
      if (d == null) return;
      try {
        final j = jsonDecode(utf8.decode(d.data)) as Map;
        if (j['app'] == 'hotspotlink') {
          final ip = d.address.address;
          if (found[ip] != j['name']) {
            found[ip] = '${j['name']}';
            onChange?.call();
          }
        }
      } catch (_) {}
    });
  }

  void stop() {
    _s?.close();
    _s = null;
  }
}
