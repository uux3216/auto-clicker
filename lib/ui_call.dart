import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'session.dart';

class CallPage extends StatefulWidget {
  const CallPage({super.key});
  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Widget _avatar(String id) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircleAvatar(radius: 44, child: Icon(Icons.person, size: 44)),
          const SizedBox(height: 8),
          Text(app.nameOf(id), style: const TextStyle(color: Colors.white, fontSize: 18)),
        ]),
      );

  Widget _remote(CallPeer p) {
    final f = p.frame;
    if (f == null) return _avatar(p.id);
    return Stack(fit: StackFit.expand, children: [
      ClipRect(
          child: RotatedBox(
              quarterTurns: p.rot,
              child: Image.memory(f, gaplessPlayback: true, fit: BoxFit.cover))),
      Positioned(
          left: 8,
          bottom: 8,
          child: Text(app.nameOf(p.id),
              style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)]))),
    ]);
  }

  Widget _body() {
    final peers = app.cps.values.where((c) => c.present).toList();
    if (peers.isEmpty) {
      return Center(
          child: Text(app.iAmCaller ? 'কল করা হচ্ছে…' : 'সংযোগ হচ্ছে…',
              style: const TextStyle(color: Colors.white, fontSize: 20)));
    }
    if (app.callVideo) {
      if (peers.length == 1) return SizedBox.expand(child: _remote(peers.first));
      return GridView.count(crossAxisCount: 2, children: [for (final p in peers) _remote(p)]);
    }
    return Center(
      child: Wrap(spacing: 24, runSpacing: 24, alignment: WrapAlignment.center, children: [
        for (final p in peers) _avatar(p.id),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = app.callThread == null ? '' : app.titleOf(app.callThread!);
    final c = app.cam;
    final showPreview = app.callVideo && !app.camOff && c != null && c.value.isInitialized;
    return PopScope(
      canPop: false, // Back must not close the chat underneath the call
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: _body()),
          Positioned(
            top: 48,
            left: 16,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
              Text(app.mmss(app.callSeconds), style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          if (showPreview)
            Positioned(
                top: 48,
                right: 12,
                width: 100,
                height: 140,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(color: Colors.black54, child: Center(child: CameraPreview(c!))))),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton.filledTonal(
                  onPressed: app.toggleMute, icon: Icon(app.muted ? Icons.mic_off : Icons.mic)),
              IconButton.filledTonal(
                  onPressed: app.toggleSpeaker,
                  icon: Icon(app.speaker ? Icons.volume_up : Icons.hearing)),
              if (app.callVideo) ...[
                IconButton.filledTonal(
                    onPressed: app.toggleCam,
                    icon: Icon(app.camOff ? Icons.videocam_off : Icons.videocam)),
                IconButton.filledTonal(
                    onPressed: app.switchCam, icon: const Icon(Icons.cameraswitch)),
              ],
              IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: app.hangup,
                  icon: const Icon(Icons.call_end)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class IncomingPage extends StatefulWidget {
  const IncomingPage({super.key});
  @override
  State<IncomingPage> createState() => _IncomingPageState();
}

class _IncomingPageState extends State<IncomingPage> {
  Timer? t;

  @override
  void initState() {
    super.initState();
    HapticFeedback.vibrate();
    t = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inc = app.incoming;
    if (inc == null) return const SizedBox.shrink();
    final th = (inc['thread'] ?? '') as String;
    final group = th == 'all' || th.startsWith('g:');
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(children: [
              const CircleAvatar(radius: 56, child: Icon(Icons.person, size: 56)),
              const SizedBox(height: 16),
              Text(inc['fromName'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 26)),
              if (group)
                Text(app.titleOf(th), style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 8),
              Text(inc['video'] == true ? 'ভিডিও কল আসছে…' : 'অডিও কল আসছে…',
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton.filled(
                  iconSize: 36,
                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: app.declineCall,
                  icon: const Icon(Icons.call_end)),
              IconButton.filled(
                  iconSize: 36,
                  style: IconButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: app.acceptCall,
                  icon: const Icon(Icons.call)),
            ]),
          ]),
        ),
      ),
    );
  }
}
