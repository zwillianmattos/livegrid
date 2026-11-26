import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/controllers/session_controller.dart';
import 'package:livegrid/app/models/network_profile.dart';
import 'package:livegrid/app/models/resolution_profile.dart';
import 'package:livegrid/app/models/session_state.dart';
import 'package:livegrid/app/services/native_bridge.dart';
import 'package:permission_handler/permission_handler.dart';

class _FakeBridge extends NativeBridge {
  _FakeBridge()
    : super(
        control: const MethodChannel('livegrid/control.test'),
        stats: const EventChannel('livegrid/stats.test'),
      );

  final List<String> calls = [];

  @override
  Future<CaptureStartInfo> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    calls.add('start');
    return const CaptureStartInfo();
  }
}

class FakeProbe implements PermissionProbe {
  FakeProbe({required this.checked, required this.requested});

  PermissionStatuses checked;
  PermissionStatuses requested;
  int checks = 0;
  int requests = 0;
  int settings = 0;

  @override
  Future<PermissionStatuses> check() async {
    checks++;
    return checked;
  }

  @override
  Future<PermissionStatuses> request() async {
    requests++;
    return requested;
  }

  @override
  Future<bool> openSettings() async {
    settings++;
    return true;
  }
}

PermissionStatuses _all(AppPermissionStatus s) => {
  for (final p in AppPermission.values) p: s,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('começa com tudo pendente e não pronto', () {
    final c = SessionController(
      bridge: _FakeBridge(),
      permissionProbe: FakeProbe(checked: {}, requested: {}),
    );
    expect(c.permissionsReady, isFalse);
    for (final p in AppPermission.values) {
      expect(c.permissionStatus(p), AppPermissionStatus.pending);
    }
  });

  test('checkPermissions atualiza status e notifica', () async {
    final probe = FakeProbe(
      checked: _all(AppPermissionStatus.granted),
      requested: {},
    );
    final c = SessionController(bridge: _FakeBridge(), permissionProbe: probe);
    var notified = 0;
    c.addListener(() => notified++);
    await c.checkPermissions();
    expect(c.permissionsReady, isTrue);
    expect(notified, 1);
    expect(probe.checks, 1);
  });

  test('microfone negado não impede permissionsReady', () async {
    final c = SessionController(
      bridge: _FakeBridge(),
      permissionProbe: FakeProbe(
        checked: {},
        requested: {
          AppPermission.camera: AppPermissionStatus.granted,
          AppPermission.microphone: AppPermissionStatus.permanentlyDenied,
          AppPermission.photos: AppPermissionStatus.granted,
        },
      ),
    );
    await c.requestPermissions();
    expect(c.permissionsReady, isTrue);
    expect(c.hasPermanentlyDeniedPermission, isTrue);
  });

  test('openPermissionSettings delega ao probe', () async {
    final probe = FakeProbe(checked: {}, requested: {});
    final c = SessionController(bridge: _FakeBridge(), permissionProbe: probe);
    expect(await c.openPermissionSettings(), isTrue);
    expect(probe.settings, 1);
  });

  test('start com câmera já concedida não pede de novo', () async {
    final bridge = _FakeBridge();
    final probe = FakeProbe(
      checked: {
        AppPermission.camera: AppPermissionStatus.granted,
        AppPermission.microphone: AppPermissionStatus.pending,
      },
      requested: {},
    );
    final c = SessionController(bridge: bridge, permissionProbe: probe);
    await c.start();
    expect(c.state, SessionState.live);
    expect(probe.requests, 0);
    expect(bridge.calls, contains('start'));
  });

  test('start grava mudo quando o microfone é negado', () async {
    final bridge = _FakeBridge();
    final probe = FakeProbe(
      checked: _all(AppPermissionStatus.pending),
      requested: {
        AppPermission.camera: AppPermissionStatus.granted,
        AppPermission.microphone: AppPermissionStatus.permanentlyDenied,
      },
    );
    final c = SessionController(bridge: bridge, permissionProbe: probe);
    await c.start();
    expect(probe.requests, 1);
    expect(c.state, SessionState.live);
  });

  test('start sem câmera fica em error e não chama o nativo', () async {
    final bridge = _FakeBridge();
    final probe = FakeProbe(
      checked: _all(AppPermissionStatus.pending),
      requested: {AppPermission.camera: AppPermissionStatus.pending},
    );
    final c = SessionController(bridge: bridge, permissionProbe: probe);
    await c.start();
    expect(c.state, SessionState.error);
    expect(c.errorMessage, contains('câmera'));
    expect(bridge.calls, isNot(contains('start')));
  });

  test('mapPermissionStatus cobre os estados do permission_handler', () {
    expect(
      mapPermissionStatus(PermissionStatus.granted),
      AppPermissionStatus.granted,
    );
    expect(
      mapPermissionStatus(PermissionStatus.limited),
      AppPermissionStatus.granted,
    );
    expect(
      mapPermissionStatus(PermissionStatus.denied),
      AppPermissionStatus.pending,
    );
    expect(
      mapPermissionStatus(PermissionStatus.permanentlyDenied),
      AppPermissionStatus.permanentlyDenied,
    );
    expect(
      mapPermissionStatus(PermissionStatus.restricted),
      AppPermissionStatus.permanentlyDenied,
    );
  });
}
