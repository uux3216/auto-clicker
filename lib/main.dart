import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const HoldApp());

const _channel = MethodChannel('com.example.autoclicker/control');

class HoldApp extends StatelessWidget {
  const HoldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Simple Hold',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16a34a)),
        useMaterial3: true,
      ),
      home: const HoldHome(),
    );
  }
}

class HoldHome extends StatefulWidget {
  const HoldHome({super.key});

  @override
  State<HoldHome> createState() => _HoldHomeState();
}

class _HoldHomeState extends State<HoldHome> {
  final _holdController = TextEditingController(text: '2');
  final _breakController = TextEditingController(text: '1');
  bool _floatingEnabled = false;
  String _status = 'Ready';

  Future<void> _enableFloating(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        enabled ? 'enableOverlay' : 'disableOverlay',
      );
      if (!mounted) return;
      if (enabled && result != true) {
        setState(() => _status = 'Allow “Display over other apps”, then try again.');
      } else {
        setState(() {
          _floatingEnabled = enabled;
          _status = enabled ? 'Floating controls enabled' : 'Floating controls disabled';
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _status = e.message ?? 'Could not change floating controls');
    }
  }

  Future<void> _start() async {
    final hold = double.tryParse(_holdController.text.trim());
    final rest = double.tryParse(_breakController.text.trim());
    if (hold == null || rest == null || hold <= 0 || rest < 0 || hold > 60 || rest > 3600) {
      setState(() => _status = 'Hold: 0–60 sec; Break: 0–3600 sec (Hold must be > 0).');
      return;
    }
    try {
      await _channel.invokeMethod('start', {
        'mode': 'hold',
        'holdSeconds': hold,
        'holdBreakSeconds': rest,
        'infinity': true,
        'points': [{'x': 540.0, 'y': 960.0}],
      });
      if (mounted) setState(() => _status = 'Hold running');
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _status = e.message ?? 'Enable Accessibility Service, then press Start.');
      }
    }
  }

  Future<void> _stop() async {
    try {
      await _channel.invokeMethod('stop');
      if (mounted) setState(() => _status = 'Stopped');
    } on PlatformException catch (e) {
      if (mounted) setState(() => _status = e.message ?? 'Stop failed');
    }
  }

  @override
  void dispose() {
    _holdController.dispose();
    _breakController.dispose();
    super.dispose();
  }

  Widget _timeField(String label, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'seconds',
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple Hold Auto Clicker')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.touch_app, size: 64, color: Color(0xff16a34a)),
          const SizedBox(height: 20),
          _timeField('Hold Time', _holdController, 'e.g. 2'),
          const SizedBox(height: 16),
          _timeField('Break Time', _breakController, 'e.g. 1'),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              value: _floatingEnabled,
              onChanged: _enableFloating,
              title: const Text('Enable Floating'),
              subtitle: const Text('Only Start ▶ and Stop ■ icons'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
          const SizedBox(height: 20),
          Text(_status, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text(
            'Before using, enable Auto Clicker in Android Accessibility settings. '
            'Choose the target point by positioning the floating controls over the desired screen area; '
            'Android may restrict cancelling an already-dispatched gesture.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
