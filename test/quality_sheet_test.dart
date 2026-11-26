import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/controllers/session_controller.dart';
import 'package:livegrid/app/models/camera_info.dart';
import 'package:livegrid/app/models/network_profile.dart';
import 'package:livegrid/app/models/resolution_profile.dart';
import 'package:livegrid/app/models/stream_stats.dart';
import 'package:livegrid/app/services/native_bridge.dart';
import 'package:livegrid/app/theme/app_theme.dart';
import 'package:livegrid/app/widgets/quality/quality_sheet.dart';

class _FakeBridge extends NativeBridge {
  _FakeBridge()
    : super(
        control: const MethodChannel('livegrid/control.test'),
        stats: const EventChannel('livegrid/stats.test'),
      );

  final List<String> calls = [];
  final _statsCtrl = StreamController<StreamStats>.broadcast();

  @override
  Future<int?> init() async => 42;

  @override
  Future<CaptureStartInfo> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    calls.add('start');
    return const CaptureStartInfo();
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> switchResolution(CaptureResolution resolution) async {
    calls.add('switch:${resolution.width}x${resolution.height}');
  }

  @override
  Future<void> setBitrate({int? horizontalBps, int? verticalBps}) async {
    calls.add('bitrate:$horizontalBps/$verticalBps');
  }

  @override
  Future<void> setFrameRate(int fps) async => calls.add('fps:$fps');

  @override
  Future<WifiBand> wifiBand() async => WifiBand.unknown;

  @override
  Future<List<CameraInfo>> listCameras() async => const [];

  @override
  Stream<StreamStats> get statsStream => _statsCtrl.stream;
}

class _SpyController extends SessionController {
  _SpyController(_FakeBridge bridge)
    : super(bridge: bridge, permissionGate: () async => true);

  final List<SessionProfile> updates = [];

  @override
  Future<void> updateProfile(SessionProfile profile) {
    updates.add(profile);
    return super.updateProfile(profile);
  }
}

Future<void> _open(WidgetTester tester, SessionController controller) async {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showQualitySheet(context, controller),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return semantics.properties.selected ?? false;
}

void main() {
  testWidgets('mostra o tier atual e troca seleção', (tester) async {
    final controller = _SpyController(_FakeBridge());
    await _open(tester, controller);

    expect(find.text('Qualidade'), findsOneWidget);
    expect(_selected(tester, 'tier-balanced'), isTrue);
    expect(_selected(tester, 'tier-quality'), isFalse);
    expect(
      find.text('Arquivos: 16:9 1920×1080 + 9:16 1080×1920'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('tier-quality')));
    await tester.pump();
    expect(_selected(tester, 'tier-quality'), isTrue);
    expect(find.text('H 16.0 · V 14.0 Mbps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aviso de 24 fps só aparece com 24 selecionado', (tester) async {
    final controller = _SpyController(_FakeBridge());
    await _open(tester, controller);
    const hint =
        '24 pode piscar com luz artificial. Em ambiente interno use 30.';

    expect(find.text(hint), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fps-24')));
    await tester.pump();
    expect(find.text(hint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fps-60')));
    await tester.pump();
    expect(find.text(hint), findsNothing);
  });

  testWidgets('salvar chama updateProfile com gop = fps', (tester) async {
    final controller = _SpyController(_FakeBridge());
    await _open(tester, controller);

    await tester.tap(find.byKey(const ValueKey('fps-60')));
    await tester.pump();
    await tester.tap(find.text('SALVAR'));
    await tester.pumpAndSettle();

    expect(controller.updates, hasLength(1));
    final p = controller.updates.single;
    expect(p.horizontal.fps, 60);
    expect(p.horizontal.gop, 60);
    expect(p.vertical.fps, 60);
    expect(p.vertical.gop, 60);
    expect(p.mode, CaptureMode.recording);
    expect(p.capture, CaptureResolution.balanced);
    expect(find.text('Qualidade'), findsNothing);
  });

  testWidgets('trocar tier aplica switchCapture e bitrates padrão', (
    tester,
  ) async {
    final controller = _SpyController(_FakeBridge());
    await _open(tester, controller);

    await tester.tap(find.byKey(const ValueKey('tier-quality')));
    await tester.pump();
    await tester.tap(find.text('SALVAR'));
    await tester.pumpAndSettle();

    final p = controller.profile;
    expect(p.capture, CaptureResolution.quality);
    expect(p.horizontal.bitrateBps, 16000000);
    expect(p.vertical.bitrateBps, 14000000);
    expect(p.horizontal.gop, p.horizontal.fps);
  });

  testWidgets('cancelar e toque fora não alteram o perfil', (tester) async {
    final controller = _SpyController(_FakeBridge());
    await _open(tester, controller);

    await tester.tap(find.byKey(const ValueKey('tier-quality')));
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();
    expect(controller.updates, isEmpty);
    expect(controller.profile.capture, CaptureResolution.balanced);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 195));
    await tester.pumpAndSettle();
    expect(find.text('Qualidade'), findsNothing);
    expect(controller.updates, isEmpty);
  });

  testWidgets('bitrate avançado expande sem overflow e salva', (tester) async {
    final controller = _SpyController(_FakeBridge());
    await _open(tester, controller);

    await tester.tap(find.byKey(const ValueKey('bitrate-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slider-horizontal')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final slider = find.descendant(
      of: find.byKey(const ValueKey('slider-vertical')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(slider) - const Offset(150, 0));
    await tester.pump();
    expect(find.text('H 12.0 · V 10.0 Mbps'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('tier-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tier-quality')));
    await tester.pump();
    await tester.tap(find.text('SALVAR'));
    await tester.pumpAndSettle();

    final p = controller.profile;
    expect(p.capture, CaptureResolution.quality);
    expect(p.horizontal.bitrateBps, 12000000);
    expect(p.vertical.bitrateBps, lessThan(10000000));
  });

  testWidgets('salvar em sessão ativa reinicia a captura', (tester) async {
    final bridge = _FakeBridge();
    final controller = _SpyController(bridge);
    await controller.start();
    await _open(tester, controller);

    await tester.tap(find.text('SALVAR'));
    await tester.pumpAndSettle();
    expect(bridge.calls.where((c) => c == 'start'), hasLength(2));
    expect(bridge.calls, contains('stop'));
  });
}
