import 'dart:async';
import 'package:flutter/material.dart';
import 'session.dart';
import 'ui_call.dart';
import 'ui_home.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) => FlutterError.presentError(d);
    // In release mode a broken widget would be an invisible grey/black box.
    // Show the real error text instead so problems can be diagnosed.
    ErrorWidget.builder = (d) => Material(
        color: Colors.white,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('ত্রুটি: ${d.exceptionAsString()}',
                style: const TextStyle(color: Colors.red, fontSize: 12))));
    app.onNotice = (t) => messengerKey.currentState?.showSnackBar(SnackBar(content: Text(t)));
    runApp(const App());
  }, (e, s) => app.onNotice?.call('ত্রুটি: $e'));
}

ThemeData _theme(Brightness b) =>
    ThemeData(colorSchemeSeed: const Color(0xFF128C7E), brightness: b, useMaterial3: true);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HotspotLink',
      scaffoldMessengerKey: messengerKey,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (ctx, child) => ListenableBuilder(
        listenable: app,
        builder: (_, __) => Stack(fit: StackFit.expand, children: [
          child!,
          if (app.inCall)
            const Positioned.fill(child: CallPage())
          else if (app.incoming != null)
            const Positioned.fill(child: IncomingPage()),
        ]),
      ),
      home: const Boot(),
    );
  }
}

/// Starts the app first, loads saved data after: any failure is shown on screen.
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  late final Future<void> f = app.init();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: f,
      builder: (c, s) {
        if (s.hasError) {
          return Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('অ্যাপ চালু করা যায়নি:\n${s.error}'))));
        }
        if (s.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return const Home();
      },
    );
  }
}
