import 'dart:io';

// Folders are resolved without any plugin: some phones crash inside the
// path_provider plugin (Java class loading error), so we avoid it completely.

String _pkg() {
  try {
    final raw = File('/proc/self/cmdline').readAsStringSync();
    final n = raw.split('\u0000').first.trim();
    if (n.isNotEmpty) return n;
  } catch (_) {}
  return 'com.example.hotspotlink';
}

/// Private app folder (chat history lives here).
Directory appDir() {
  final pkg = _pkg();
  for (final p in ['/data/user/0/$pkg/files', '/data/data/$pkg/files']) {
    try {
      final d = Directory(p);
      d.createSync(recursive: true);
      return d;
    } catch (_) {}
  }
  return Directory.systemTemp;
}

/// Received/sent media. Visible in a file manager under Android/data/<package>/files/media.
Directory mediaDir() {
  final pkg = _pkg();
  try {
    final d = Directory('/storage/emulated/0/Android/data/$pkg/files/media');
    d.createSync(recursive: true);
    return d;
  } catch (_) {}
  final d = Directory('${appDir().path}/media');
  d.createSync(recursive: true);
  return d;
}
