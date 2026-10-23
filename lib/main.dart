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
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16803C)), useMaterial3: true),
    home: const SettingsPage(),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final hold = TextEditingController(text: '3');
  final breakTime = TextEditingController(text: '1');
  bool floatingEnabled = false;
  bool busy = false;

  @override
  void dispose() {
    hold.dispose();
    breakTime.dispose();
    super.dispose();
  }

  int value(TextEditingController controller, int fallback, {int min = 0, int max = 86400}) {
    final parsed = int.tryParse(controller.text.trim()) ?? fallback;
    return parsed.clamp(min, max);
  }

  Future<void> saveSettings() async {
    final h = value(hold, 3, min: 1, max: 3600);
    final b = value(breakTime, 1, min: 0, max: 86400);
    hold.text = '$h';
    breakTime.text = '$b';
    try {
      await control.invokeMethod('saveSettings', {'holdSeconds': h, 'breakSeconds': b});
    } catch (_) {}
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
            const SnackBar(content: Text('Overlay permission চালু করে অ্যাপে ফিরে Enable Floating আবার চালু করুন।')),
          );
        }
      } else {
        await control.invokeMethod('disableFloating');
        if (mounted) setState(() => floatingEnabled = false);
      }
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'কাজটি করা যায়নি')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openAccessibility() async {
    await saveSettings();
    try {
      await control.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  InputDecoration fieldDecoration(String label) => InputDecoration(
    labelText: label,
    suffixText: 'sec',
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hold Clicker'), centerTitle: true),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Automation Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(
          controller: hold,
          keyboardType: TextInputType.number,
          decoration: fieldDecoration('Hold Time'),
          onEditingComplete: saveSettings,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: breakTime,
          keyboardType: TextInputType.number,
          decoration: fieldDecoration('Break Time'),
          onEditingComplete: saveSettings,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Floating'),
          subtitle: const Text('স্ক্রিনে শুধু Start ও Stop আইকন দেখাবে'),
          value: floatingEnabled,
          onChanged: busy ? null : enableFloating,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: openAccessibility,
          icon: const Icon(Icons.accessibility_new),
          label: const Text('Accessibility Service Permission'),
        ),
        const SizedBox(height: 20),
        const Text(
          'ফ্লোটিং Start আইকন চাপলে Hold Time অনুযায়ী টাচ ধরে রাখবে, এরপর Break Time বিরতি দিয়ে আবার শুরু হবে। Stop আইকন চাপলে পরবর্তী চক্র বন্ধ হবে।',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        const Text(
          'সতর্কতা: Android আগে থেকে চলমান gesture সঙ্গে সঙ্গে বাতিল করার নিশ্চয়তা দেয় না। প্রথমে নিরাপদ স্ক্রিনে পরীক্ষা করুন।',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );
}
