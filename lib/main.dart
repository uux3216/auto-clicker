import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const HexApp());

class HexApp extends StatelessWidget {
  const HexApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hex Editor',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark),
        home: const HexPage(),
      );
}

class Edit {
  final int off, oldV, newV;
  Edit(this.off, this.oldV, this.newV);
}

class HexPage extends StatefulWidget {
  const HexPage({super.key});
  @override
  State<HexPage> createState() => _HexPageState();
}

class _HexPageState extends State<HexPage> {
  static const cols = 8;
  static const rowH = 28.0;
  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

  Uint8List data = Uint8List(0);
  String name = '';
  bool dirty = false;
  final undoStack = <Edit>[];
  final redoStack = <Edit>[];
  int? sel;
  int hitStart = -1, hitLen = 0;
  List<int> pattern = [];
  final scroll = ScrollController();
  final hexCtl = TextEditingController();
  final ascCtl = TextEditingController();
  final searchCtl = TextEditingController();
  bool searchHex = false;
  String lastQuery = '';
  bool lastHex = false;

  void msg(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s)));

  // ---------- file ----------
  Future<void> openFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null || r.files.single.bytes == null) return;
    setState(() {
      data = Uint8List.fromList(r.files.single.bytes!);
      name = r.files.single.name;
      dirty = false;
      sel = null;
      hitStart = -1;
      undoStack.clear();
      redoStack.clear();
    });
  }

  Future<void> saveFile() async {
    if (data.isEmpty) return;
    final p = await FilePicker.platform
        .saveFile(dialogTitle: 'Save', fileName: name, bytes: data);
    if (p != null) {
      setState(() => dirty = false);
      msg('Saved');
    }
  }

  // ---------- editing ----------
  void applyByte(int off, int v) {
    final old = data[off];
    if (old == v) return;
    data[off] = v;
    undoStack.add(Edit(off, old, v));
    redoStack.clear();
    dirty = true;
  }

  void select(int? i) {
    sel = i;
    if (i != null && i < data.length) {
      hexCtl.text = data[i].toRadixString(16).padLeft(2, '0').toUpperCase();
      final b = data[i];
      ascCtl.text = (b >= 32 && b < 127) ? String.fromCharCode(b) : '';
    }
  }

  void commitHex() {
    final i = sel;
    final v = int.tryParse(hexCtl.text, radix: 16);
    if (i == null || v == null) return;
    setState(() {
      applyByte(i, v);
      select(i + 1 < data.length ? i + 1 : i);
    });
  }

  void commitAscii(String s) {
    final i = sel;
    if (i == null || s.isEmpty) return;
    final c = s.codeUnitAt(0);
    if (c > 127) {
      msg('Only ASCII here. Use the Hex field for other bytes.');
      return;
    }
    setState(() {
      applyByte(i, c);
      select(i + 1 < data.length ? i + 1 : i);
    });
  }

  void undo() {
    if (undoStack.isEmpty) return;
    final e = undoStack.removeLast();
    setState(() {
      data[e.off] = e.oldV;
      redoStack.add(e);
      dirty = undoStack.isNotEmpty;
      select(e.off);
    });
    jumpTo(e.off);
  }

  void redo() {
    if (redoStack.isEmpty) return;
    final e = redoStack.removeLast();
    setState(() {
      data[e.off] = e.newV;
      undoStack.add(e);
      dirty = true;
      select(e.off);
    });
    jumpTo(e.off);
  }

  // ---------- navigation ----------
  void jumpTo(int off) {
    if (!scroll.hasClients) return;
    final y = (off ~/ cols) * rowH - 120;
    scroll.jumpTo(y.clamp(0, scroll.position.maxScrollExtent).toDouble());
  }

  Future<void> gotoDialog() async {
    final ctl = TextEditingController();
    await showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Go to offset (hex)'),
              content: TextField(
                  controller: ctl,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '1A0 or 0x1A0')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      Navigator.pop(c);
                      final o = int.tryParse(
                          ctl.text.trim().replaceFirst('0x', ''),
                          radix: 16);
                      if (o == null || o < 0 || o >= data.length) {
                        msg('Invalid offset');
                        return;
                      }
                      setState(() => select(o));
                      jumpTo(o);
                    },
                    child: const Text('Go')),
              ],
            ));
  }

  // ---------- search ----------
  bool buildPattern(String text, bool hex) {
    if (hex) {
      final t = text.replaceAll(RegExp(r'\s'), '');
      if (t.isEmpty || t.length.isOdd) {
        msg('Hex needs an even number of digits (e.g. 48 65 6C)');
        return false;
      }
      final p = <int>[];
      for (var i = 0; i < t.length; i += 2) {
        final v = int.tryParse(t.substring(i, i + 2), radix: 16);
        if (v == null) {
          msg('Invalid hex');
          return false;
        }
        p.add(v);
      }
      pattern = p;
    } else {
      if (text.isEmpty) return false;
      pattern = utf8.encode(text);
    }
    return true;
  }

  void searchFromBar() {
    FocusScope.of(context).unfocus();
    if (data.isEmpty) return;
    final q = searchCtl.text;
    final changed = q != lastQuery || searchHex != lastHex;
    if (!buildPattern(q, searchHex)) return;
    lastQuery = q;
    lastHex = searchHex;
    findNext(fromStart: changed);
  }

  void findNext({bool fromStart = false}) {
    if (pattern.isEmpty || data.isEmpty) return;
    final n = data.length, m = pattern.length;
    final start = fromStart ? 0 : (sel ?? -1) + 1;
    for (var k = 0; k < n; k++) {
      final i = (start + k) % n;
      if (i + m > n) continue;
      var ok = true;
      for (var j = 0; j < m; j++) {
        if (data[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        setState(() {
          select(i);
          hitStart = i;
          hitLen = m;
        });
        jumpTo(i);
        msg('Found at offset 0x${i.toRadixString(16)} ($i)');
        return;
      }
    }
    setState(() => hitStart = -1);
    msg('Not found');
  }

  // ---------- checksum ----------
  int crc32(Uint8List d) {
    var c = 0xFFFFFFFF;
    for (final b in d) {
      c ^= b;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
      }
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  void checksumDialog() {
    if (data.isEmpty) return;
    final t = 'Size: ${data.length} bytes\n'
        'CRC32: ${crc32(data).toRadixString(16).padLeft(8, '0')}\n'
        'MD5: ${md5.convert(data)}\n'
        'SHA1: ${sha1.convert(data)}\n'
        'SHA256: ${sha256.convert(data)}';
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Checksums'),
              content: SelectableText(t, style: mono),
              actions: [
                TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: t));
                      Navigator.pop(c);
                    },
                    child: const Text('Copy')),
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Close')),
              ],
            ));
  }

  // ---------- UI ----------
  String inspector() {
    final i = sel!;
    final bd = ByteData.sublistView(data);
    final b = data[i];
    final s = StringBuffer(
        'Offset $i (0x${i.toRadixString(16)})   u8=$b  i8=${bd.getInt8(i)}\n'
        'bin=${b.toRadixString(2).padLeft(8, '0')}');
    if (i + 2 <= data.length) {
      s.write('\nu16 LE=${bd.getUint16(i, Endian.little)}  '
          'BE=${bd.getUint16(i, Endian.big)}');
    }
    if (i + 4 <= data.length) {
      s.write('\nu32 LE=${bd.getUint32(i, Endian.little)}  '
          'BE=${bd.getUint32(i, Endian.big)}');
      s.write('\nfloat LE=${bd.getFloat32(i, Endian.little)}');
    }
    return s.toString();
  }

  Widget cell(int idx, bool asc) {
    final b = data[idx];
    final inHit = idx >= hitStart && idx < hitStart + hitLen;
    final bg = idx == sel
        ? Colors.indigo
        : inHit
            ? const Color(0x66FFC107)
            : null;
    final txt = asc
        ? (b >= 32 && b < 127 ? String.fromCharCode(b) : '.')
        : b.toRadixString(16).padLeft(2, '0').toUpperCase();
    return GestureDetector(
      onTap: () => setState(() => select(idx)),
      child: Container(
          width: asc ? 10 : 26,
          alignment: Alignment.center,
          color: bg,
          child: Text(txt, style: mono)),
    );
  }

  Widget row(int r) {
    final base = r * cols;
    final w = <Widget>[
      SizedBox(
          width: 68,
          child: Text(base.toRadixString(16).padLeft(8, '0'),
              style: mono.copyWith(color: Colors.grey))),
    ];
    for (var i = 0; i < cols; i++) {
      w.add(base + i < data.length
          ? cell(base + i, false)
          : const SizedBox(width: 26));
    }
    w.add(const SizedBox(width: 8));
    for (var i = 0; i < cols; i++) {
      if (base + i < data.length) w.add(cell(base + i, true));
    }
    return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(children: w));
  }

  Widget searchBar() => Material(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(children: [
            OutlinedButton(
                onPressed: () => setState(() => searchHex = !searchHex),
                child: Text(searchHex ? 'HEX' : 'TXT')),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: searchCtl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => searchFromBar(),
                    decoration: InputDecoration(
                        hintText: searchHex ? '48 65 6C 6C 6F' : 'Search text',
                        isDense: true,
                        border: const OutlineInputBorder()))),
            const SizedBox(width: 8),
            FilledButton(
                onPressed: searchFromBar, child: const Text('Find next')),
          ]),
        ),
      );

  Widget editorBar() => Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(inspector(), style: mono.copyWith(fontSize: 11))),
              const SizedBox(height: 6),
              Row(children: [
                SizedBox(
                    width: 80,
                    child: TextField(
                        controller: hexCtl,
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))
                        ],
                        onSubmitted: (_) => commitHex(),
                        decoration: const InputDecoration(
                            labelText: 'Hex', counterText: '', isDense: true))),
                const SizedBox(width: 8),
                FilledButton(onPressed: commitHex, child: const Text('Set')),
                const SizedBox(width: 16),
                SizedBox(
                    width: 70,
                    child: TextField(
                        controller: ascCtl,
                        maxLength: 1,
                        onChanged: commitAscii,
                        decoration: const InputDecoration(
                            labelText: 'ASCII',
                            counterText: '',
                            isDense: true))),
                const Spacer(),
                IconButton(
                    onPressed: () => setState(() => sel = null),
                    icon: const Icon(Icons.close)),
              ]),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = (data.length + cols - 1) ~/ cols;
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Hex Editor' : '${dirty ? '● ' : ''}$name',
            style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(onPressed: openFile, icon: const Icon(Icons.folder_open)),
          IconButton(
              onPressed: undoStack.isEmpty ? null : undo,
              icon: const Icon(Icons.undo)),
          IconButton(
              onPressed: redoStack.isEmpty ? null : redo,
              icon: const Icon(Icons.redo)),
          IconButton(onPressed: saveFile, icon: const Icon(Icons.save)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'next') findNext();
              if (v == 'goto') gotoDialog();
              if (v == 'sum') checksumDialog();
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'next', child: Text('Find next')),
              PopupMenuItem(value: 'goto', child: Text('Go to offset')),
              PopupMenuItem(value: 'sum', child: Text('Checksums')),
            ],
          ),
        ],
      ),
      body: data.isEmpty
          ? Center(
              child: FilledButton.icon(
                  onPressed: openFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open file')))
          : Column(children: [
              Expanded(
                  child: Scrollbar(
                      controller: scroll,
                      thumbVisibility: true,
                      interactive: true,
                      thickness: 12,
                      radius: const Radius.circular(6),
                      child: ListView.builder(
                          controller: scroll,
                          itemExtent: rowH,
                          itemCount: rows,
                          itemBuilder: (c, r) => row(r)))),
              searchBar(),
              if (sel != null) editorBar(),
            ]),
    );
  }
}
//git