import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Bridge to the native audio engine (MainActivity.kt) used for calls.
class Media {
  static const _m = MethodChannel('hl/media');
  static const _mic = EventChannel('hl/mic');
  static StreamSubscription? _sub;

  static Future<bool> startAudio(
      {required bool speaker, required void Function(Uint8List) onMic}) async {
    await _sub?.cancel();
    _sub = _mic.receiveBroadcastStream().listen((d) {
      if (d is Uint8List) onMic(d);
    }, onError: (_) {});
    final ok = await _m.invokeMethod<bool>('start', {'speaker': speaker}) ?? false;
    if (!ok) {
      await _sub?.cancel();
      _sub = null;
    }
    return ok;
  }

  static Future<void> stopAudio() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _m.invokeMethod<void>('stop');
    } catch (_) {}
  }

  static void play(String id, Uint8List data) {
    _m.invokeMethod<void>('play', {'id': id, 'data': data}).catchError((_) {});
  }

  static Future<void> setSpeaker(bool on) async {
    try {
      await _m.invokeMethod<void>('speaker', {'on': on});
    } catch (_) {}
  }

  static Future<Uint8List> jpeg(CameraImage i) async {
    final y = i.planes[0], u = i.planes[1], v = i.planes[2];
    final r = await _m.invokeMethod<Uint8List>('jpeg', {
      'w': i.width,
      'h': i.height,
      'y': y.bytes,
      'u': u.bytes,
      'v': v.bytes,
      'ys': y.bytesPerRow,
      'uvs': u.bytesPerRow,
      'uvp': u.bytesPerPixel ?? 1,
      'q': 45,
    });
    return r!;
  }
}
