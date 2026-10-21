import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AutoClickerApp());

const native = MethodChannel('com.example.autoclicker/control');

class AutoClickerApp extends StatelessWidget {
  const AutoClickerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Auto Clicker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      useMaterial3: true),
    home: const HomePage(),
  );
}

enum Mode { single, multiple, hold }

class TargetPoint {
  double x, y;
  TargetPoint(this.x, this.y);
}

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
  bool infinity = true;
  bool running = false;
  final points = <TargetPoint>[TargetPoint(540, 960)];

  @override
  void dispose() {
    breakController.dispose(); repeatController.dispose();
    holdController.dispose(); holdBreakController.dispose();
    super.dispose();
  }

  int number(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim())?.clamp(0, 86400000) ?? fallback;

  Future<void> start() async {
    final settings = <String, Object>{
      'mode': mode.name,
      'breakMs': number(breakController, 100),
      'repeatCount': infinity ? 0 : number(repeatController, 100),
      'infinity': infinity,
      'holdMs': number(holdController, 3000),
      'holdBreakMs': number(holdBreakController, 500),
      'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
    };
    try {
      await native.invokeMethod('start', settings);
      setState(() => running = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start request sent. Enable the Accessibility Service if prompted.')));
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not start service')));
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Native Android bridge is not installed yet.')));
    }
  }

  Future<void> stop() async {
    try { await native.invokeMethod('stop'); } catch (_) {}
    if (mounted) setState(() => running = false);
  }

  Widget field(String label, TextEditingController controller) => TextField(
    controller: controller, keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: 'ms', border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) {
    final isHold = mode == Mode.hold;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto Clicker'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Select mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SegmentedButton<Mode>(
          segments: const [
            ButtonSegment(value: Mode.single, label: Text('Single'), icon: Icon(Icons.touch_app)),
            ButtonSegment(value: Mode.multiple, label: Text('Multiple'), icon: Icon(Icons.grid_view)),
            ButtonSegment(value: Mode.hold, label: Text('Hold'), icon: Icon(Icons.pan_tool_alt)),
          ],
          selected: {mode}, onSelectionChanged: (s) => setState(() => mode = s.first),
        ),
        const SizedBox(height: 18),
        if (mode == Mode.multiple) ...[
          const Text('Target points (screen coordinates)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('This starter uses coordinate fields. Screen overlay point-picking is a follow-up implementation.',
            style: TextStyle(color: Colors.black54)),
          for (int i = 0; i < points.length; i++)
            Card(child: ListTile(
              leading: CircleAvatar(child: Text('P${i + 1}')),
              title: Text('X: ${points[i].x.round()}   Y: ${points[i].y.round()}'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline),
                onPressed: points.length == 1 ? null : () => setState(() => points.removeAt(i))),
              onTap: () async {
                final x = TextEditingController(text: points[i].x.round().toString());
                final y = TextEditingController(text: points[i].y.round().toString());
                final result = await showDialog<List<double>>(context: context, builder: (ctx) => AlertDialog(
                  title: Text('Edit point P${i + 1}'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: x, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'X coordinate')),
                    TextField(controller: y, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Y coordinate')),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, [
                      double.tryParse(x.text) ?? points[i].x, double.tryParse(y.text) ?? points[i].y]), child: const Text('Save')),
                  ]));
                if (result != null) setState(() { points[i].x = result[0]; points[i].y = result[1]; });
              },
            )),
          OutlinedButton.icon(onPressed: () => setState(() => points.add(TargetPoint(540, 960))),
            icon: const Icon(Icons.add), label: const Text('Add point')),
          const SizedBox(height: 12),
        ],
        if (!isHold) ...[
          field('Break Time', breakController),
          const SizedBox(height: 12),
          if (!infinity) field('Repeat Time', repeatController),
        ] else ...[
          field('Hold Time', holdController),
          const SizedBox(height: 12),
          field('Hold Break Time', holdBreakController),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, title: const Text('Infinity'),
          subtitle: const Text('Keep repeating until Stop is pressed'),
          value: infinity, onChanged: (v) => setState(() => infinity = v)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: running ? null : start, icon: const Icon(Icons.play_arrow), label: const Text('Start')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: running ? stop : null, icon: const Icon(Icons.stop), label: const Text('Stop')),
        const SizedBox(height: 12),
        const Text('Note: Enable the app’s Accessibility Service in Android Settings before running gestures. The first target defaults to X=540, Y=960; coordinates depend on device resolution.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}
