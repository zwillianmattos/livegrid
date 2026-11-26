import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/controllers/session_controller.dart';
import 'package:livegrid/app/pages/permission_page.dart';
import 'package:livegrid/app/services/native_bridge.dart';
import 'package:livegrid/app/theme/app_theme.dart';

class _Probe implements PermissionProbe {
  _Probe({required this.checked, required this.requested});

  PermissionStatuses checked;
  PermissionStatuses requested;
  int requests = 0;
  int settings = 0;

  @override
  Future<PermissionStatuses> check() async => checked;

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

const _pending = {
  AppPermission.camera: AppPermissionStatus.pending,
  AppPermission.microphone: AppPermissionStatus.pending,
  AppPermission.photos: AppPermissionStatus.pending,
};

SessionController _controller(_Probe probe) => SessionController(
  bridge: NativeBridge(
    control: const MethodChannel('livegrid/control.test'),
    stats: const EventChannel('livegrid/stats.test'),
  ),
  permissionProbe: probe,
);

Future<void> _pump(
  WidgetTester tester,
  SessionController c, {
  VoidCallback? onReady,
  Size size = const Size(844, 390),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: PermissionPage(controller: c, onReady: onReady ?? () {}),
    ),
  );
}

void main() {
  testWidgets('mostra copy, três linhas pendentes e botão', (tester) async {
    final c = _controller(_Probe(checked: _pending, requested: _pending));
    await _pump(tester, c);
    expect(find.text('Grave uma vez, saia com dois vídeos'), findsOneWidget);
    expect(find.text('Câmera'), findsOneWidget);
    expect(find.text('Microfone'), findsOneWidget);
    expect(find.text('Galeria'), findsOneWidget);
    expect(find.text('PENDENTE'), findsNWidgets(3));
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
    expect(find.text('PERMITIR ACESSOS'), findsOneWidget);
    expect(find.text('Sem microfone o app grava mudo.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('não estoura em landscape pequeno', (tester) async {
    final c = _controller(_Probe(checked: _pending, requested: _pending));
    await _pump(tester, c, size: const Size(640, 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('permitir com câmera concedida chama onReady', (tester) async {
    final probe = _Probe(
      checked: _pending,
      requested: {
        AppPermission.camera: AppPermissionStatus.granted,
        AppPermission.microphone: AppPermissionStatus.permanentlyDenied,
        AppPermission.photos: AppPermissionStatus.granted,
      },
    );
    final c = _controller(probe);
    var ready = 0;
    await _pump(tester, c, onReady: () => ready++);
    await tester.tap(find.text('PERMITIR ACESSOS'));
    await tester.pumpAndSettle();
    expect(probe.requests, 1);
    expect(ready, 1);
    expect(find.text('OK'), findsNWidgets(2));
    expect(find.text('NEGADO'), findsOneWidget);
  });

  testWidgets('câmera negada de vez vira ABRIR AJUSTES', (tester) async {
    final probe = _Probe(
      checked: _pending,
      requested: {
        AppPermission.camera: AppPermissionStatus.permanentlyDenied,
        AppPermission.microphone: AppPermissionStatus.granted,
        AppPermission.photos: AppPermissionStatus.granted,
      },
    );
    final c = _controller(probe);
    var ready = 0;
    await _pump(tester, c, onReady: () => ready++);
    await tester.tap(find.text('PERMITIR ACESSOS'));
    await tester.pumpAndSettle();
    expect(ready, 0);
    expect(find.text('ABRIR AJUSTES'), findsOneWidget);
    await tester.tap(find.text('ABRIR AJUSTES'));
    await tester.pumpAndSettle();
    expect(probe.settings, 1);
    expect(probe.requests, 1);
  });
}
