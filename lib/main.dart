import 'package:flutter/material.dart';
import 'session.dart';
import 'ui_call.dart';
import 'ui_home.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  app.onNotice = (t) => messengerKey.currentState?.showSnackBar(SnackBar(content: Text(t)));
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HotspotLink',
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF128C7E), useMaterial3: true),
      builder: (ctx, child) => ListenableBuilder(
        listenable: app,
        builder: (_, __) => Stack(children: [
          child!,
          if (app.inCall)
            const Positioned.fill(child: CallPage())
          else if (app.incoming != null)
            const Positioned.fill(child: IncomingPage()),
        ]),
      ),
      home: const Home(),
    );
  }
}
