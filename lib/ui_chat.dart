import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'models.dart';
import 'session.dart';

class ChatPage extends StatefulWidget {
  final String thread;
  const ChatPage({super.key, required this.thread});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final tc = TextEditingController();
  final rec = AudioRecorder();
  bool recording = false, hasText = false;
  DateTime? recStart;
  Timer? tick;

  bool get isGroup => widget.thread == 'all' || widget.thread.startsWith('g:');

  @override
  void initState() {
    super.initState();
    app.openThread = widget.thread;
    app.clearUnread(widget.thread);
    tc.addListener(() {
      final h = tc.text.trim().isNotEmpty;
      if (h != hasText) setState(() => hasText = h);
    });
  }

  @override
  void dispose() {
    app.openThread = null;
    tick?.cancel();
    rec.dispose();
    tc.dispose();
    super.dispose();
  }

  void _send() {
    app.sendText(widget.thread, tc.text);
    tc.clear();
  }

  Future<void> _attach() async {
    final c = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ক্যামেরা (ছবি)'),
              onTap: () => Navigator.pop(context, 'cam')),
          ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('ক্যামেরা (ভিডিও)'),
              onTap: () => Navigator.pop(context, 'vid')),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('গ্যালারি (ছবি/ভিডিও)'),
              onTap: () => Navigator.pop(context, 'gal')),
          ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('ডকুমেন্ট / যেকোনো ফাইল'),
              onTap: () => Navigator.pop(context, 'doc')),
        ]),
      ),
    );
    if (c == null) return;
    final ip = ImagePicker();
    try {
      switch (c) {
        case 'cam':
          final x = await ip.pickImage(source: ImageSource.camera);
          if (x != null) await app.sendFile(widget.thread, x.path);
          break;
        case 'vid':
          final x = await ip.pickVideo(source: ImageSource.camera);
          if (x != null) await app.sendFile(widget.thread, x.path);
          break;
        case 'gal':
          for (final x in await ip.pickMultipleMedia()) {
            await app.sendFile(widget.thread, x.path);
          }
          break;
        case 'doc':
          final r = await FilePicker.platform.pickFiles(allowMultiple: true);
          if (r != null) {
            for (final f in r.files) {
              if (f.path != null) await app.sendFile(widget.thread, f.path!);
            }
          }
          break;
      }
    } catch (e) {
      app.onNotice?.call('ফাইল নেওয়া যায়নি: $e');
    }
  }

  Future<void> _startRec() async {
    if (!await rec.hasPermission()) {
      app.onNotice?.call('মাইক্রোফোনের পারমিশন দিন');
      return;
    }
    final p = '${app.store.media.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: p);
    recStart = DateTime.now();
    tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() => recording = true);
  }

  Future<void> _stopRec(bool send) async {
    tick?.cancel();
    final p = await rec.stop();
    final ms = DateTime.now().difference(recStart!).inMilliseconds;
    setState(() => recording = false);
    if (p == null) return;
    if (send && ms > 700) {
      await app.sendFile(widget.thread, p, kind: 'voice');
    }
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final msgs = app.store.thread(widget.thread);
        final online = isGroup
            ? '${app.membersOf(widget.thread).where(app.isOnline).length} জন অনলাইন'
            : (app.isOnline(widget.thread) ? 'অনলাইন' : 'অফলাইন');
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.titleOf(widget.thread)),
              Text(online, style: const TextStyle(fontSize: 12)),
            ]),
            actions: [
              IconButton(
                  icon: const Icon(Icons.call), onPressed: () => app.startCall(widget.thread, false)),
              IconButton(
                  icon: const Icon(Icons.videocam),
                  onPressed: () => app.startCall(widget.thread, true)),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: msgs.length,
                itemBuilder: (c, i) => Bubble(m: msgs[msgs.length - 1 - i], group: isGroup),
              ),
            ),
            SafeArea(child: recording ? _recBar() : _inputBar()),
          ]),
        );
      },
    );
  }

  Widget _inputBar() => Row(children: [
        IconButton(icon: const Icon(Icons.attach_file), onPressed: _attach),
        Expanded(
            child: TextField(
                controller: tc,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'মেসেজ লিখুন'))),
        hasText
            ? IconButton(icon: const Icon(Icons.send), onPressed: _send)
            : IconButton(icon: const Icon(Icons.mic), onPressed: _startRec),
      ]);

  Widget _recBar() {
    final s = recStart == null ? 0 : DateTime.now().difference(recStart!).inSeconds;
    return Row(children: [
      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _stopRec(false)),
      const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
      const SizedBox(width: 8),
      Text('${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'),
      const Spacer(),
      IconButton(icon: const Icon(Icons.send), onPressed: () => _stopRec(true)),
    ]);
  }
}

class Bubble extends StatelessWidget {
  final Msg m;
  final bool group;
  const Bubble({super.key, required this.m, required this.group});

  void _menu(BuildContext c) {
    showModalBottomSheet(
      context: c,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          if (m.kind == 'text')
            ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('কপি'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.text));
                  Navigator.pop(c);
                }),
          if (m.isFile && m.path != null && (m.kind == 'image' || m.kind == 'video'))
            ListTile(
                leading: const Icon(Icons.download),
                title: const Text('গ্যালারিতে সেভ করুন'),
                onTap: () {
                  Navigator.pop(c);
                  app.saveToGallery(m);
                }),
          if (m.isFile && m.path != null && m.kind != 'image' && m.kind != 'video')
            ListTile(
                leading: const Icon(Icons.download),
                title: const Text('ফোনের Download ফোল্ডারে সেভ'),
                onTap: () {
                  Navigator.pop(c);
                  app.saveToDownloads(m);
                }),
          ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('ডিলিট (শুধু আমার ফোনে)'),
              onTap: () {
                app.deleteMsg(m);
                Navigator.pop(c);
              }),
        ]),
      ),
    );
  }

  Widget _overlay(Widget child) {
    final ok = m.path != null && File(m.path!).existsSync();
    return Stack(alignment: Alignment.center, children: [
        child,
        if (!m.mine && m.dl == dlLoading)
          CircularProgressIndicator(value: m.progress > 0 ? m.progress : null),
        if (!m.mine && (m.dl == dlFailed || (m.dl == dlDone && !ok)))
          IconButton.filled(onPressed: () => app.retryDownload(m), icon: const Icon(Icons.refresh)),
        if (m.mine && m.status == stSending)
          CircularProgressIndicator(value: m.progress > 0 ? m.progress : null),
      ]);
  }

  Widget _content(BuildContext c) {
    final ok = m.path != null && File(m.path!).existsSync();
    switch (m.kind) {
      case 'image':
        return _overlay(GestureDetector(
          onTap: ok
              ? () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => ImageViewer(path: m.path!)))
              : null,
          child: ok
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Image.file(File(m.path!), cacheWidth: 700, fit: BoxFit.cover))
              : Container(width: 200, height: 150, color: Colors.black12),
        ));
      case 'video':
        return _overlay(GestureDetector(
          onTap: ok
              ? () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => VideoPage(path: m.path!)))
              : null,
          child: Container(
              width: 200,
              height: 130,
              color: Colors.black87,
              child: const Icon(Icons.play_circle, color: Colors.white, size: 48)),
        ));
      case 'audio':
      case 'voice':
        return ok
            ? VoicePlayer(path: m.path!, voice: m.kind == 'voice')
            : _overlay(const SizedBox(width: 160, height: 40));
      case 'file':
        return _overlay(InkWell(
          onTap: ok ? () => OpenFilex.open(m.path!) : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insert_drive_file, size: 28),
            const SizedBox(width: 8),
            Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(fmtSize(m.size),
                  style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ])),
          ]),
        ));
      default:
        return Text(m.text);
    }
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    if (m.kind == 'sys') {
      return Center(
          child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: Text(m.text, style: const TextStyle(fontSize: 12)),
      ));
    }
    final tick = m.status == stSending
        ? Icons.access_time
        : (m.status == stSent ? Icons.done : Icons.done_all);
    return GestureDetector(
      onLongPress: () => _menu(c),
      child: Align(
        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * 0.78),
          decoration: BoxDecoration(
              color: m.mine ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (group && !m.mine)
              Text(m.fromName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary)),
            _content(c),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(hm(m.ts), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                if (m.mine) ...[
                  const SizedBox(width: 3),
                  Icon(tick,
                      size: 14,
                      color: m.status == stDelivered ? Colors.blue : cs.onSurfaceVariant),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  final String path;
  const ImageViewer({super.key, required this.path});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
      );
}

class VoicePlayer extends StatefulWidget {
  final String path;
  final bool voice;
  const VoicePlayer({super.key, required this.path, required this.voice});
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final p = AudioPlayer();
  bool playing = false;
  Duration pos = Duration.zero, dur = Duration.zero;
  final subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    subs.add(p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => playing = s == PlayerState.playing);
    }));
    subs.add(p.onPositionChanged.listen((d) {
      if (mounted) setState(() => pos = d);
    }));
    subs.add(p.onDurationChanged.listen((d) {
      if (mounted) setState(() => dur = d);
    }));
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (playing) {
      await p.pause();
    } else if (pos > Duration.zero && pos < dur) {
      await p.resume();
    } else {
      await p.play(DeviceFileSource(widget.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final max_ = max(1, dur.inMilliseconds).toDouble();
    return SizedBox(
      width: 220,
      child: Row(children: [
        IconButton(
            onPressed: _toggle, icon: Icon(playing ? Icons.pause_circle : Icons.play_circle, size: 32)),
        Expanded(
          child: Slider(
            value: pos.inMilliseconds.clamp(0, max_.toInt()).toDouble(),
            max: max_,
            onChanged: (v) => p.seek(Duration(milliseconds: v.toInt())),
          ),
        ),
        Icon(widget.voice ? Icons.mic : Icons.music_note, size: 16),
      ]),
    );
  }
}


class VideoPage extends StatefulWidget {
  final String path;
  const VideoPage({super.key, required this.path});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController c = VideoPlayerController.file(File(widget.path));
  bool ready = false;

  @override
  void initState() {
    super.initState();
    c.addListener(() {
      if (mounted) setState(() {});
    });
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => ready = true);
      c.play();
    }).catchError((e) {
      app.onNotice?.call('ভিডিও চালানো যায়নি: $e');
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
          child: ready
              ? AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))
              : const CircularProgressIndicator()),
      bottomNavigationBar: ready
          ? SafeArea(
              child: Row(children: [
                IconButton(
                    color: Colors.white,
                    icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () => c.value.isPlaying ? c.pause() : c.play()),
                Expanded(child: VideoProgressIndicator(c, allowScrubbing: true)),
                const SizedBox(width: 12),
              ]),
            )
          : null,
    );
  }
}
