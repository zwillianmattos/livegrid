import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/controllers/session_controller.dart';
import 'package:livegrid/app/models/camera_info.dart';
import 'package:livegrid/app/models/network_profile.dart';
import 'package:livegrid/app/models/resolution_profile.dart';
import 'package:livegrid/app/models/stream_stats.dart';
import 'package:livegrid/app/models/thermal_status.dart';
import 'package:livegrid/app/pages/live_page.dart';
import 'package:livegrid/app/services/native_bridge.dart';
import 'package:livegrid/app/theme/app_theme.dart';

class _FakeBridge extends NativeBridge {
  _FakeBridge()
    : super(
        control: const MethodChannel('livegrid/control.test'),
        stats: const EventChannel('livegrid/stats.test'),
      );

  final List<String> calls = [];
  final _statsCtrl = StreamController<StreamStats>.broadcast();

  @override
  Future<int?> init() async => -1;

  @override
  Future<WifiBand> wifiBand() async => WifiBand.unknown;

  @override
  Future<String?> deviceIp() async => null;

  @override
  Future<List<CameraInfo>> listCameras() async => const [
    CameraInfo(id: '0', lens: CameraLens.back, label: '4.3mm'),
    CameraInfo(id: '1', lens: CameraLens.front, label: '2.2mm'),
  ];

  @override
  Future<CameraCapabilities> cameraCapabilities() async =>
      CameraCapabilities.none;

  @override
  Future<CaptureStartInfo> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    calls.add('start');
    return const CaptureStartInfo(
      horizontalFile: '/tmp/LG_20261126_0748_H.mp4',
      verticalFile: '/tmp/LG_20261126_0748_V.mp4',
    );
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> shareFile(String path) async => calls.add('share:$path');

  @override
  Future<void> openGallery() async => calls.add('gallery');

  @override
  Stream<StreamStats> get statsStream => _statsCtrl.stream;

  void emitAudio(AudioInputType type, {String name = '', double level = 0.4}) {
    _statsCtrl.add(
      StreamStats(
        bitrateABps: 0,
        bitrateBBps: 0,
        fps: 30,
        droppedFrames: 0,
        thermalStatus: ThermalStatus.none,
        srtRttMs: 0,
        srtLossPct: 0,
        txDatagramsA: 0,
        txBytesA: 0,
        txErrorsA: 0,
        txDatagramsB: 0,
        txBytesB: 0,
        txErrorsB: 0,
        audioLevel: level,
        audioInputType: type,
        audioInputName: name,
        timestampMs: 0,
      ),
    );
  }
}

Future<void> _startRecording(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Gravar'));
  await tester.pump();
  await tester.pump();
}

Future<_FakeBridge> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(844, 390),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bridge = _FakeBridge();
  final controller = SessionController(
    bridge: bridge,
    permissionGate: () async => true,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: LivePage(controller: controller),
    ),
  );
  await tester.pump();
  await tester.pump();
  return bridge;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('hub idle mostra PRONTO, ENQUADRAR e formato', (tester) async {
    await _pumpPage(tester);
    expect(find.text('PRONTO'), findsOneWidget);
    expect(find.text('ENQUADRAR'), findsOneWidget);
    expect(find.text('NITIDEZ PADRÃO'), findsOneWidget);
    expect(find.text('30 · STORIES'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('16:9 1080p'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('hub, enquadrar e gravando não estouram em 932x430', (
    tester,
  ) async {
    await _pumpPage(tester, size: const Size(932, 430));
    expect(find.text('PRONTO'), findsOneWidget);
    await tester.tap(find.text('ENQUADRAR'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Gravar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('REC'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('nitidez alterna entre padrão e alta', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.text('NITIDEZ PADRÃO'));
    await tester.pump();
    expect(find.text('NITIDEZ ALTA'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('entra e sai do modo enquadrar', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.text('ENQUADRAR'));
    await tester.pump();
    expect(find.text('ENQUADRAR 9:16'), findsOneWidget);
    expect(find.text('ARRASTE'), findsOneWidget);
    expect(find.text('CENTRALIZAR'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.bySemanticsLabel('Gravar'), findsNothing);
    expect(find.text('PRONTO'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text('ENQUADRAR 9:16'), findsNothing);
    expect(find.text('PRONTO'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('gravando mostra REC e timer e esconde o hub', (tester) async {
    final bridge = await _pumpPage(tester);
    await tester.tap(find.bySemanticsLabel('Gravar'));
    await tester.pump();
    await tester.pump();
    expect(bridge.calls, contains('start'));
    expect(find.text('REC'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('ENQUADRAR'), findsNothing);
    expect(find.text('PRONTO'), findsNothing);
    expect(find.text('H 0.0 Mbps'), findsOneWidget);
    expect(find.bySemanticsLabel('Parar gravação'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('parar mostra SALVO com os arquivos e ações', (tester) async {
    final bridge = await _pumpPage(tester);
    await tester.tap(find.bySemanticsLabel('Gravar'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Parar gravação'));
    await tester.pump();
    await tester.pump();
    expect(bridge.calls, contains('stop'));
    expect(find.text('SALVO NA GALERIA'), findsOneWidget);
    expect(find.text('LG_20261126_0748_H.mp4'), findsOneWidget);
    expect(find.text('LG_20261126_0748_V.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('COMPARTILHAR 9:16'));
    await tester.tap(find.text('ABRIR GALERIA'));
    await tester.pump();
    expect(bridge.calls, contains('share:/tmp/LG_20261126_0748_V.mp4'));
    expect(bridge.calls, contains('gallery'));

    await tester.tap(find.text('NOVA GRAVAÇÃO'));
    await tester.pump();
    expect(find.text('SALVO NA GALERIA'), findsNothing);
    expect(find.text('PRONTO'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Última gravação'));
    await tester.pump();
    expect(find.text('SALVO NA GALERIA'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('gravando com mic interno mostra INTERNO', (tester) async {
    final bridge = await _pumpPage(tester);
    await _startRecording(tester);
    bridge.emitAudio(AudioInputType.builtin, name: 'Microfone');
    await tester.pump();
    await tester.pump();
    expect(find.text('INTERNO'), findsOneWidget);
    expect(find.text('Microfone'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('mic externo mostra USB e nome truncado', (tester) async {
    final bridge = await _pumpPage(tester);
    bridge.emitAudio(AudioInputType.usb, name: 'RØDE Wireless GO II RX');
    await tester.pump();
    await tester.pump();
    expect(find.text('USB'), findsOneWidget);
    await _startRecording(tester);
    bridge.emitAudio(AudioInputType.usb, name: 'RØDE Wireless GO II RX');
    await tester.pump();
    await tester.pump();
    expect(find.text('USB'), findsOneWidget);
    expect(find.text('RØDE Wireless…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('gravando sem entrada de áudio mostra SEM ÁUDIO', (tester) async {
    final bridge = await _pumpPage(tester);
    await _startRecording(tester);
    bridge.emitAudio(AudioInputType.none, level: 0);
    await tester.pump();
    await tester.pump();
    expect(find.text('SEM ÁUDIO'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
