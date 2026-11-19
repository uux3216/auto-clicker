import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

/// Chat history + identity, saved as one JSON file (written safely via a temp file).
class Store {
  late File _file;
  late Directory media;
  Timer? _t;
  bool _writing = false, _again = false;
  String id = '', name = '';
  final msgs = <Msg>[];
  final _ids = <String>{};
  final names = <String, String>{};
  final groups = <String, Group>{};
  final unread = <String, int>{};

  static String rid([int n = 12]) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  bool has(String mid) => _ids.contains(mid);
  void add(Msg m) {
    msgs.add(m);
    _ids.add(m.id);
  }

  void remove(Msg m) {
    msgs.remove(m);
    _ids.remove(m.id);
  }

  List<Msg> thread(String t) => [for (final m in msgs) if (m.thread == t) m];

  Msg? last(String t) {
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].thread == t) return msgs[i];
    }
    return null;
  }

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    _file = File('${docs.path}/hotspotlink.json');
    Directory? ext;
    try {
      ext = await getExternalStorageDirectory();
    } catch (_) {}
    media = Directory('${(ext ?? docs).path}/media');
    await media.create(recursive: true);
    if (!await _file.exists()) return;
    try {
      final j = jsonDecode(await _file.readAsString()) as Map;
      id = j['id'] ?? '';
      name = j['name'] ?? '';
      (j['names'] as Map? ?? {}).forEach((k, v) => names['$k'] = '$v');
      (j['unread'] as Map? ?? {}).forEach((k, v) => unread['$k'] = v as int);
      for (final g in (j['groups'] as List? ?? [])) {
        final gr = Group.fromJson(g as Map);
        groups[gr.gid] = gr;
      }
      for (final m in (j['msgs'] as List? ?? [])) {
        add(Msg.fromJson(m as Map));
      }
    } catch (_) {}
  }

  void save() {
    _t?.cancel();
    _t = Timer(const Duration(seconds: 1), _flush);
  }

  Future<void> _flush() async {
    if (_writing) {
      _again = true;
      return;
    }
    _writing = true;
    try {
      final j = {
        'id': id,
        'name': name,
        'names': names,
        'unread': unread,
        'groups': [for (final g in groups.values) g.toJson()],
        'msgs': [for (final m in msgs) m.toJson()],
      };
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(j));
      await tmp.rename(_file.path);
    } catch (_) {
    } finally {
      _writing = false;
      if (_again) {
        _again = false;
        save();
      }
    }
  }
}
