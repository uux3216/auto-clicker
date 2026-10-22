import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AutoClickerApp());

const channel = MethodChannel('com.example.auto_clicker/control');

class AutoClickerApp extends StatelessWidget {
  const AutoClickerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Auto Clicker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)), useMaterial3: true),
    home: const HomePage(),
  );
}

enum ClickMode { single, multiple, hold }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ClickMode mode = ClickMode.single;
  final breakMs = TextEditingController(text: '100');
  final repeats = TextEditingController(text: '100');
  final holdMs = TextEditingController(text: '3000');
  final holdBreakMs = TextEditingController(text: '500');
  bool infinity = true;
  bool overlayEnabled = false;
  bool running = false;

  @override
  void dispose() {
    breakMs.dispose(); repeats.dispose(); holdMs.dispose(); holdBreakMs.dispose();
    super.dispose();
  }

  int parsed(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim())?.clamp(0, 86400000) ?? fallback;

  Future<void> call(String method, [Map<String, Object?>? args]) async {
    try {
      final result = await channel.invokeMethod<Object?>(method, args);
      if (mounted && method == 'enableOverlay') setState(() => overlayEnabled = result == true);
      if (mounted && method == 'start') setState(() => running = true);
      if (mounted && method == 'stop') setState(() => running = false);
      if (mounted && result is String && result.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      }
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Operation failed')));
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Native Android code is not available in this build.')));
    }
  }

  Widget numberField(String title, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: title, suffixText: 'ms', border: const OutlineInputBorder())),
  );

  Map<String, Object?> settings() => {
    'mode': mode.name,
    'breakMs': parsed(breakMs, 100),
    'repeatCount': parsed(repeats, 100),
    'infinity': infinity,
    'holdMs': parsed(holdMs, 3000),
    'holdBreakMs': parsed(holdBreakMs, 500),
  };

  @override
  Widget build(BuildContext context) {
    final hold = mode == ClickMode.hold;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto Clicker'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 10),
        SegmentedButton<ClickMode>(
          segments: const [
            ButtonSegment(value: ClickMode.single, label: Text('Single Click'), icon: Icon(Icons.touch_app)),
            ButtonSegment(value: ClickMode.multiple, label: Text('Multiple'), icon: Icon(Icons.grid_view)),
            ButtonSegment(value: ClickMode.hold, label: Text('Hold'), icon: Icon(Icons.pan_tool_alt)),
          ],
          selected: {mode}, onSelectionChanged: (v) => setState(() => mode = v.first)),
        const SizedBox(height: 18),
        if (mode != ClickMode.hold) ...[
          numberField('Break Time', breakMs),
          if (!infinity) numberField('Repeat Time', repeats),
        ] else ...[
          numberField('Hold Time', holdMs),
          numberField('Hold Break Time', holdBreakMs),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero, title: const Text('Infinity'),
          subtitle: const Text('Repeat until Stop is pressed'),
          value: infinity, onChanged: (v) => setState(() => infinity = v)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => call('enableOverlay'),
          icon: const Icon(Icons.my_location),
          label: Text(overlayEnabled ? 'Floating targets enabled' : 'Enable draggable target points')),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: Text('Enable the overlay, then drag the numbered target dots to the exact places to tap. Use + in the floating panel to add points for Multiple Click. The STOP button stays above other apps while the overlay is active.',
            style: TextStyle(color: Colors.black54, fontSize: 12))),
        FilledButton.icon(
          onPressed: running ? null : () => call('start', settings()),
          icon: const Icon(Icons.play_arrow), label: const Text('Start')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => call('stop'),
          icon: const Icon(Icons.stop_circle_outlined), label: const Text('Stop')),
        const SizedBox(height: 16),
        const Text('Safety: Android may cancel a gesture asynchronously. Stop halts future repeats and requests cancellation of any active gesture; always test on a non-sensitive screen first.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}
