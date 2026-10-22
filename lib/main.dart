import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AutoClickerApp());
const native = MethodChannel('com.example.autoclicker/control');

class AutoClickerApp extends StatelessWidget {
  const AutoClickerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Auto Clicker', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)), useMaterial3: true),
    home: const HomePage());
}
enum Mode { single, multiple, hold }
class TargetPoint { double x, y; TargetPoint(this.x, this.y); }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  Mode mode = Mode.single;
  final breakController = TextEditingController(text: '100');
  final repeatController = TextEditingController(text: '100');
  final holdController = TextEditingController(text: '3000');
  final holdBreakController = TextEditingController(text: '500');
  bool infinity = true, running = false, overlayEnabled = false, paused = false;
  final points = <TargetPoint>[TargetPoint(540, 960)];

  @override void dispose() {
    breakController.dispose(); repeatController.dispose(); holdController.dispose(); holdBreakController.dispose(); super.dispose();
  }
  int number(TextEditingController c, int fallback) => int.tryParse(c.text.trim())?.clamp(0, 86400000) ?? fallback;
  Future<void> enableOverlay() async {
    try {
      final ok = await native.invokeMethod<bool>('enableOverlay') ?? false;
      if (mounted) setState(() => overlayEnabled = ok);
      if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('অনুমতি চালু করে অ্যাপে ফিরে Enable আবার চাপুন।')));
    } on PlatformException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Overlay চালু হয়নি'))); }
  }
  Future<void> addPoint() async {
    if (points.length >= 20) return;
    setState(() => points.add(TargetPoint(540 + points.length * 35, 960 + points.length * 35)));
    try { await native.invokeMethod('addPoint'); } catch (_) {}
  }
  Future<void> removePoint() async {
    if (points.length <= 1) return;
    setState(() => points.removeLast());
    try { await native.invokeMethod('removePoint'); } catch (_) {}
  }
  Future<void> start() async {
    final settings = <String, Object>{
      'mode': mode.name, 'breakMs': number(breakController, 100),
      'repeatSeconds': number(repeatController, 100), 'infinity': infinity,
      'holdMs': number(holdController, 3000), 'holdBreakMs': number(holdBreakController, 500),
      'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
      'startedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await native.invokeMethod('start', settings);
      if (mounted) setState(() { running = true; paused = false; });
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Start হয়নি')));
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Native Android bridge পাওয়া যায়নি।')));
    }
  }
  Future<void> stop() async {
    try { await native.invokeMethod('stop'); } catch (_) {}
    if (mounted) setState(() { running = false; paused = false; });
  }
  Future<void> togglePause() async {
    try {
      if (paused) { await native.invokeMethod('resume'); } else { await native.invokeMethod('pause'); }
      if (mounted) setState(() => paused = !paused);
    } catch (_) {}
  }
  Widget field(String label, TextEditingController controller, {String suffix = 'ms'}) => TextField(
    controller: controller, keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()));
  @override Widget build(BuildContext context) {
    final isHold = mode == Mode.hold;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto Clicker'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SegmentedButton<Mode>(segments: const [
          ButtonSegment(value: Mode.single, label: Text('Single Click'), icon: Icon(Icons.touch_app)),
          ButtonSegment(value: Mode.multiple, label: Text('Multiple'), icon: Icon(Icons.grid_view)),
          ButtonSegment(value: Mode.hold, label: Text('Hold'), icon: Icon(Icons.pan_tool_alt)),
        ], selected: {mode}, onSelectionChanged: (s) => setState(() => mode = s.first)),
        const SizedBox(height: 16),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enable floating controls'),
          subtitle: const Text('অন্য অ্যাপের ওপর ভাসমান প্যানেল ও টার্গেট পয়েন্ট দেখাবে'),
          value: overlayEnabled, onChanged: (_) => enableOverlay()),
        if (mode == Mode.multiple) ...[
          Row(children: [
            const Expanded(child: Text('Target points', style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(onPressed: removePoint, icon: const Icon(Icons.remove_circle_outline), tooltip: 'শেষ পয়েন্ট রিমুভ'),
            IconButton(onPressed: addPoint, icon: const Icon(Icons.add_circle_outline), tooltip: 'পয়েন্ট যোগ'),
          ]),
          for (int i = 0; i < points.length; i++)
            ListTile(leading: CircleAvatar(child: Text('P${i+1}')),
              title: Text('X ${points[i].x.round()} · Y ${points[i].y.round()}'),
              trailing: IconButton(onPressed: points.length <= 1 ? null : () {
                setState(() => points.removeAt(i));
                native.invokeMethod('removePoint');
              }, icon: const Icon(Icons.delete_outline))),
        ],
        if (!isHold) ...[
          field('Break Time', breakController),
          const SizedBox(height: 12),
          field('Repeat Time', repeatController, suffix: 'sec'),
        ] else ...[
          field('Hold Time', holdController),
          const SizedBox(height: 12),
          field('Hold Break Time', holdBreakController),
        ],
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Infinity'),
          subtitle: const Text('Stop চাপা পর্যন্ত চালু থাকবে'), value: infinity,
          onChanged: (v) => setState(() => infinity = v)),
        FilledButton.icon(onPressed: start, icon: const Icon(Icons.play_arrow), label: const Text('Start')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: togglePause, icon: Icon(paused ? Icons.play_arrow : Icons.pause), label: Text(paused ? 'Resume' : 'Pause')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: stop, icon: const Icon(Icons.stop), label: const Text('Stop')),
        const SizedBox(height: 12),
        const Text('Safety: Android may not immediately cancel a gesture already in progress. First test on a non-sensitive screen.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}
