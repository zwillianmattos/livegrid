import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/controllers/session_controller.dart';
import 'package:livegrid/app/models/camera_info.dart';
import 'package:livegrid/app/models/network_profile.dart';
import 'package:livegrid/app/models/resolution_profile.dart';
import 'package:livegrid/app/models/session_state.dart';
import 'package:livegrid/app/models/stream_stats.dart';
import 'package:livegrid/app/services/native_bridge.dart';

class _FakeBridge extends NativeBridge {
  _FakeBridge()
      : super(
          control: const MethodChannel('livegrid/control.test'),
          stats: const EventChannel('livegrid/stats.test'),
        );

  final List<String> calls = [];
  final _statsCtrl = StreamController<StreamStats>.broadcast();
  Object? nextInitError;
  Object? nextStartError;

  @override
  Future<int?> init() async {
    calls.add('init');
    if (nextInitError != null) throw nextInitError!;
    return 42;
  }

  @override
  Future<void> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    calls.add('start');
    if (nextStartError != null) throw nextStartError!;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> switchResolution(CaptureResolution resolution) async {
    calls.add('switch:${resolution.width}x${resolution.height}');
  }

  @override
  Future<void> setBitrate({int? horizontalBps, int? verticalBps}) async {
    calls.add('bitrate:$horizontalBps/$verticalBps');
  }

  @override
  Future<WifiBand> wifiBand() async => WifiBand.band5GHz;

  @override
  Future<List<CameraInfo>> listCameras() async => const [
        CameraInfo(id: '0', lens: CameraLens.back, label: 'main'),
        CameraInfo(id: '1', lens: CameraLens.front, label: 'selfie'),
      ];

  @override
  Stream<StreamStats> get statsStream => _statsCtrl.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initialize marca texture id e estado idle', () async {
    final bridge = _FakeBridge();
    final c = SessionController(bridge: bridge);
    await c.initialize();
    expect(bridge.calls, contains('init'));
    expect(c.textureId, 42);
    expect(c.state, SessionState.idle);
  });

  test('init falhando coloca em estado error', () async {
    final bridge = _FakeBridge()..nextInitError = StateError('boom');
    final c = SessionController(bridge: bridge);
    await c.initialize();
    expect(c.state, SessionState.error);
    expect(c.errorMessage, contains('init failed'));
  });

  test('start transita para live', () async {
    final bridge = _FakeBridge();
    final c = SessionController(
      bridge: bridge,
      permissionGate: () async => true,
    );
    await c.start();
    expect(bridge.calls, contains('start'));
    expect(c.state, SessionState.live);
  });

  test('start falhando volta em error', () async {
    final bridge = _FakeBridge()..nextStartError = StateError('nope');
    final c = SessionController(
      bridge: bridge,
      permissionGate: () async => true,
    );
    await c.start();
    expect(c.state, SessionState.error);
  });

  test('start sem permissão volta em error', () async {
    final bridge = _FakeBridge();
    final c = SessionController(
      bridge: bridge,
      permissionGate: () async => false,
    );
    await c.start();
    expect(c.state, SessionState.error);
    expect(c.errorMessage, contains('Permissão'));
    expect(bridge.calls, isNot(contains('start')));
  });

  test('stop a partir de live volta a idle', () async {
    final bridge = _FakeBridge();
    final c = SessionController(
      bridge: bridge,
      permissionGate: () async => true,
    );
    await c.start();
    await c.stop();
    expect(c.state, SessionState.idle);
    expect(bridge.calls.last, 'stop');
  });
}
