import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
    t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Widget _body() {
    final peers = app.cps.values.where((c) => c.present).toList();
    if (peers.isEmpty) {
      return Center(
          child: Text(app.iAmCaller ? 'কল করা হচ্ছে…' : 'সংযোগ হচ্ছে…',
              style: const TextStyle(color: Colors.white, fontSize: 20)));
    }
    if (app.callVideo) {
      return GridView.count(
        crossAxisCount: peers.length == 1 ? 1 : 2,
        children: [
          for (final p in peers)
            Stack(fit: StackFit.expand, children: [
              RTCVideoView(p.r,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              Positioned(
                  left: 8,
                  bottom: 8,
                  child: Text(app.nameOf(p.id),
                      style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)]))),
            ]),
        ],
      );
    }
    return Center(
      child: Wrap(spacing: 24, runSpacing: 24, alignment: WrapAlignment.center, children: [
        for (final p in peers)
          Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 48, child: Icon(Icons.person, size: 48)),
            const SizedBox(height: 8),
            Text(app.nameOf(p.id), style: const TextStyle(color: Colors.white, fontSize: 18)),
          ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = app.callThread == null ? '' : app.titleOf(app.callThread!);
    return Scaffold(
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
        if (app.callVideo && !app.camOff)
          Positioned(
              top: 48,
              right: 12,
              width: 100,
              height: 140,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: RTCVideoView(app.localR,
                      mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
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
    final inc = app.incoming!;
    final th = (inc['thread'] ?? '') as String;
    final group = th == 'all' || th.startsWith('g:');
    return Scaffold(
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
    );
  }
}
