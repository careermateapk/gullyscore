// Talks to the phone's camera and the YouTube stream (Android code in
// packages/gs_live). Tests swap in [FakeLiveEngine].
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gs_live/gs_live.dart';

class LiveEvent {
  const LiveEvent(this.type, [this.data = const {}]);
  final String type; // connecting, live, reconnecting, failed, stopped, bitrate, replayStarted, replayDone
  final Map<String, Object?> data;
}

abstract class LiveEngine {
  /// False in tests: no camera, no picture of the score.
  bool get real;
  Stream<LiveEvent> get events;
  Future<bool> permissions();
  Future<void> prepare({required int width, required int height, required int bitrate});
  Future<void> start(String url);
  Future<void> stop();
  Future<void> release();
  Future<void> overlay(Uint8List png);
  Future<void> startSegment(String path);
  Future<void> cutSegment(String? next);
  Future<int> durationMs(String path);
  Future<bool> trim(String src, String dst, int fromMs, int toMs);
  Future<bool> concat(List<String> srcs, String dst);
  Future<void> replay(String path);
  Future<void> switchCamera();
  Future<void> mute(bool on);
  Future<void> zoom(double level);
  Widget preview();
}

LiveEngine liveEngine = ChannelLiveEngine();

class ChannelLiveEngine implements LiveEngine {
  ChannelLiveEngine() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'event' && call.arguments is Map) {
        final m = Map<String, Object?>.from(call.arguments as Map);
        _events.add(LiveEvent('${m['type']}', m));
      }
    });
  }

  final _ch = const MethodChannel(gsLiveChannel);
  final _events = StreamController<LiveEvent>.broadcast();

  @override
  bool get real => true;
  @override
  Stream<LiveEvent> get events => _events.stream;

  Future<T?> _call<T>(String m, [Map<String, Object?>? args]) => _ch.invokeMethod<T>(m, args);

  @override
  Future<bool> permissions() async => (await _call<bool>('permissions')) ?? false;
  @override
  Future<void> prepare({required int width, required int height, required int bitrate}) =>
      _call('prepare', {'width': width, 'height': height, 'bitrate': bitrate, 'fps': 30});
  @override
  Future<void> start(String url) => _call('start', {'url': url});
  @override
  Future<void> stop() => _call('stop');
  @override
  Future<void> release() => _call('release');
  @override
  Future<void> overlay(Uint8List png) => _call('overlay', {'png': png});
  @override
  Future<void> startSegment(String path) => _call('startSegment', {'path': path});
  @override
  Future<void> cutSegment(String? next) => _call('cutSegment', {'next': next});
  @override
  Future<int> durationMs(String path) async => ((await _call<num>('duration', {'path': path})) ?? 0).toInt();
  @override
  Future<bool> trim(String src, String dst, int fromMs, int toMs) async =>
      (await _call<bool>('trim', {'src': src, 'dst': dst, 'fromMs': fromMs, 'toMs': toMs})) ?? false;
  @override
  Future<bool> concat(List<String> srcs, String dst) async => (await _call<bool>('concat', {'srcs': srcs, 'dst': dst})) ?? false;
  @override
  Future<void> replay(String path) => _call('replay', {'path': path});
  @override
  Future<void> switchCamera() => _call('switchCamera');
  @override
  Future<void> mute(bool on) => _call('mute', {'on': on});
  @override
  Future<void> zoom(double level) => _call('zoom', {'level': level});

  @override
  Widget preview() => PlatformViewLink(
        viewType: gsLivePreviewView,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) {
          final c = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: gsLivePreviewView,
            layoutDirection: TextDirection.ltr,
            creationParamsCodec: const StandardMessageCodec(),
          );
          c.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
          c.create();
          return c;
        },
      );
}

/// Does nothing; remembers what was asked (for tests).
class FakeLiveEngine implements LiveEngine {
  final calls = <String>[];
  final _events = StreamController<LiveEvent>.broadcast();
  void emit(LiveEvent e) => _events.add(e);

  @override
  bool get real => false;
  @override
  Stream<LiveEvent> get events => _events.stream;
  @override
  Future<bool> permissions() async => true;
  @override
  Future<void> prepare({required int width, required int height, required int bitrate}) async => calls.add('prepare');
  @override
  Future<void> start(String url) async {
    calls.add('start');
    emit(const LiveEvent('live'));
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> release() async => calls.add('release');
  @override
  Future<void> overlay(Uint8List png) async => calls.add('overlay');
  @override
  Future<void> startSegment(String path) async => calls.add('segment');
  @override
  Future<void> cutSegment(String? next) async => calls.add('cut');
  @override
  Future<int> durationMs(String path) async => 0;
  @override
  Future<bool> trim(String src, String dst, int fromMs, int toMs) async => false;
  @override
  Future<bool> concat(List<String> srcs, String dst) async => false;
  @override
  Future<void> replay(String path) async {
    calls.add('replay');
    emit(const LiveEvent('replayDone'));
  }

  @override
  Future<void> switchCamera() async => calls.add('camera');
  @override
  Future<void> mute(bool on) async => calls.add('mute');
  @override
  Future<void> zoom(double level) async {}
  @override
  Widget preview() => const ColoredBox(color: Color(0xFF3D7D2B));
}
