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
  Completer<List<CameraInfo>>? camerasGate;

  @override
  Future<int?> init() async {
    calls.add('init');
    if (nextInitError != null) throw nextInitError!;
    return 42;
  }

  @override
  Future<CaptureStartInfo> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    calls.add('start');
    if (nextStartError != null) throw nextStartError!;
    return const CaptureStartInfo();
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
  Future<WifiBand> wifiBand() async {
    calls.add('wifiBand');
    return WifiBand.band5GHz;
  }

  @override
  Future<String?> deviceIp() async {
    calls.add('deviceIp');
    return '10.0.0.7';
  }

  static const _cameras = [
    CameraInfo(id: '0', lens: CameraLens.back, label: 'main'),
    CameraInfo(id: '1', lens: CameraLens.front, label: 'selfie'),
  ];

  @override
  Future<List<CameraInfo>> listCameras() async {
    calls.add('listCameras');
    final gate = camerasGate;
    if (gate != null) return gate.future;
    return _cameras;
  }

  @override
  Future<CameraCapabilities> cameraCapabilities() async {
    calls.add('cameraCapabilities');
    return CameraCapabilities.none;
  }

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

  test(
    'initialize é idempotente e expõe textureId antes das câmeras',
    () async {
      final bridge = _FakeBridge()..camerasGate = Completer();
      final c = SessionController(bridge: bridge);
      var notified = 0;
      c.addListener(() => notified++);
      final first = c.initialize();
      final second = c.initialize();
      await pumpEventQueue();
      expect(c.textureId, 42);
      expect(c.cameras, isEmpty);
      expect(notified, greaterThan(0));
      bridge.camerasGate!.complete(_FakeBridge._cameras);
      await Future.wait([first, second]);
      await c.initialize();
      expect(bridge.calls.where((e) => e == 'init'), hasLength(1));
      expect(bridge.calls.where((e) => e == 'listCameras'), hasLength(1));
      expect(c.cameras, hasLength(2));
      expect(c.profile.cameraId, '0');
      expect(bridge.calls, isNot(contains('wifiBand')));
      expect(bridge.calls, isNot(contains('deviceIp')));
    },
  );

  test('init falhando permite nova tentativa', () async {
    final bridge = _FakeBridge()..nextInitError = StateError('boom');
    final c = SessionController(bridge: bridge);
    await c.initialize();
    bridge.nextInitError = null;
    await c.initialize();
    expect(c.textureId, 42);
    expect(bridge.calls.where((e) => e == 'init'), hasLength(2));
  });

  test('start em modo live resolve rede antes de capturar', () async {
    final bridge = _FakeBridge();
    final c = SessionController(
      bridge: bridge,
      permissionGate: () async => true,
    );
    await c.updateProfile(c.profile.copyWith(mode: CaptureMode.live));
    await c.start();
    expect(bridge.calls, containsAllInOrder(['wifiBand', 'deviceIp', 'start']));
    expect(c.wifiBand, WifiBand.band5GHz);
    expect(c.network.obsHost, '10.0.0.7');
  });

  test('start em modo recording não consulta rede', () async {
    final bridge = _FakeBridge();
    final c = SessionController(
      bridge: bridge,
      permissionGate: () async => true,
    );
    await c.start();
    expect(bridge.calls, isNot(contains('wifiBand')));
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
