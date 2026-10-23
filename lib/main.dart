import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const HoldClickerApp());

const control = MethodChannel('com.example.autoclicker/control');

class HoldClickerApp extends StatelessWidget {
  const HoldClickerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hold Clicker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16803C)),
          useMaterial3: true,
        ),
        home: const SettingsPage(),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final hold = TextEditingController(text: '3');
  final breakTime = TextEditingController(text: '1');
  bool floatingEnabled = false;
  bool busy = false;
  Timer? poller;
  Map<String, dynamic> debug = {
    'status': 'Waiting for native status',
    'event': 'APP_OPENED',
    'error': 'None',
    'accepted': 'Not sent',
    'running': false,
    'accessibilityConnected': false,
    'overlayVisible': false,
    'gestureInFlight': false,
    'targetX': -1,
    'targetY': -1,
    'holdSeconds': 3,
    'breakSeconds': 1,
  };

  @override
  void initState() {
    super.initState();
    refreshDebug();
    poller = Timer.periodic(const Duration(milliseconds: 700), (_) => refreshDebug());
  }

  @override
  void dispose() {
    poller?.cancel();
    hold.dispose();
    breakTime.dispose();
    super.dispose();
  }

  int value(TextEditingController controller, int fallback,
      {int min = 0, int max = 86400}) {
    final parsed = int.tryParse(controller.text.trim()) ?? fallback;
    return parsed.clamp(min, max);
  }

  Future<void> refreshDebug() async {
    try {
      final result = await control.invokeMapMethod<String, dynamic>('getDebugState');
      if (mounted && result != null) setState(() => debug = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          debug = {...debug, 'status': 'Cannot read native debug state', 'error': e.toString()};
        });
      }
    }
  }

  Future<void> saveSettings() async {
    final h = value(hold, 3, min: 1, max: 3600);
    final b = value(breakTime, 1, min: 0, max: 86400);
    hold.text = '$h';
    breakTime.text = '$b';
    try {
      await control.invokeMethod('saveSettings', {'holdSeconds': h, 'breakSeconds': b});
      await refreshDebug();
    } catch (e) {
      if (mounted) setState(() => debug = {...debug, 'status': 'Save settings failed', 'error': e.toString()});
    }
  }

  Future<void> enableFloating(bool enable) async {
    if (busy) return;
    setState(() => busy = true);
    await saveSettings();
    try {
      if (enable) {
        final ok = await control.invokeMethod<bool>('enableFloating') ?? false;
        if (mounted) setState(() => floatingEnabled = ok);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Overlay permission চালু করে ফিরে এসে আবার Enable Floating চাপুন।')),
          );
        }
      } else {
        await control.invokeMethod('disableFloating');
        if (mounted) setState(() => floatingEnabled = false);
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => debug = {...debug, 'status': 'Floating control failed', 'error': '${e.code}: ${e.message}'});
    } catch (e) {
      if (mounted) setState(() => debug = {...debug, 'status': 'Floating control failed', 'error': e.toString()});
    } finally {
      await refreshDebug();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openAccessibility() async {
    await saveSettings();
    try {
      await control.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      if (mounted) setState(() => debug = {...debug, 'status': 'Could not open Accessibility settings', 'error': e.toString()});
    }
  }

  Color _stateColor(bool value) => value ? Colors.green : Colors.red;

  Widget _statusRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 142, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: SelectableText(value, style: TextStyle(color: color))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Hold Clicker'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh diagnostics',
              onPressed: refreshDebug,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Automation Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: hold,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hold Time', suffixText: 'seconds', border: OutlineInputBorder()),
              onEditingComplete: saveSettings,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: breakTime,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Break Time', suffixText: 'seconds', border: OutlineInputBorder()),
              onEditingComplete: saveSettings,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Floating'),
              subtitle: const Text('Start ▶ · Stop ■ · Close ✕'),
              value: floatingEnabled,
              onChanged: busy ? null : enableFloating,
            ),
            OutlinedButton.icon(
              onPressed: openAccessibility,
              icon: const Icon(Icons.accessibility_new),
              label: const Text('Open Accessibility Settings'),
            ),
            const SizedBox(height: 18),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: const [
                      Icon(Icons.bug_report),
                      SizedBox(width: 8),
                      Expanded(child: Text('Live Diagnostics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 8),
                    const Text('এই অংশ প্রতি ০.৭ সেকেন্ডে আপডেট হয়।'),
                    const Divider(),
                    _statusRow('Status', '${debug['status'] ?? '-'}'),
                    _statusRow('Last event', '${debug['event'] ?? '-'}'),
                    _statusRow('Accessibility', (debug['accessibilityConnected'] == true) ? 'CONNECTED' : 'NOT CONNECTED',
                        color: _stateColor(debug['accessibilityConnected'] == true)),
                    _statusRow('Floating overlay', (debug['overlayVisible'] == true) ? 'VISIBLE' : 'NOT VISIBLE',
                        color: _stateColor(debug['overlayVisible'] == true)),
                    _statusRow('Automation', (debug['running'] == true) ? 'RUNNING' : 'STOPPED',
                        color: _stateColor(debug['running'] == true)),
                    _statusRow('Gesture in flight', '${debug['gestureInFlight'] ?? false}'),
                    _statusRow('Target X / Y', '${debug['targetX']} / ${debug['targetY']}'),
                    _statusRow('Dispatch result', '${debug['accepted'] ?? '-'}'),
                    _statusRow('Last error', '${debug['error'] ?? 'None'}',
                        color: (debug['error'] == null || debug['error'] == 'None') ? null : Colors.red),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: refreshDebug,
                        icon: const Icon(Icons.sync),
                        label: const Text('Refresh diagnostic state'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Text(
              'নোট: Android আগে পাঠানো জেসচার সঙ্গে সঙ্গে বাতিল নাও করতে পারে। “Android accepted gesture request: true” মানে শুধু অনুরোধ গ্রহণ করেছে; স্ক্রিনে কাজ হয়েছে—এটি নিশ্চিত নয়।',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      );
}
