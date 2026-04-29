import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/models/resolution_profile.dart';
import 'package:livegrid/app/models/stream_stats.dart';
import 'package:livegrid/app/models/thermal_status.dart';

void main() {
  group('CaptureResolution', () {
    test('quality (4K) cobre 1080p vertical', () {
      expect(CaptureResolution.quality.coversVertical1080p, isTrue);
    });

    test('balanced (1080p) NÃO cobre 1080p vertical', () {
      expect(CaptureResolution.balanced.coversVertical1080p, isFalse);
    });

    test('economic (720p) NÃO cobre 1080p vertical', () {
      expect(CaptureResolution.economic.coversVertical1080p, isFalse);
    });

    test('thermalHint reflete o esforço esperado', () {
      expect(CaptureResolution.economic.thermalHint, ThermalHint.cool);
      expect(CaptureResolution.balanced.thermalHint, ThermalHint.normal);
      expect(CaptureResolution.quality.thermalHint, ThermalHint.hot);
    });

    test('defaultHorizontalEncoder acompanha a captura', () {
      expect(CaptureResolution.economic.defaultHorizontalEncoder.height, 720);
      expect(CaptureResolution.balanced.defaultHorizontalEncoder.height, 1080);
      expect(CaptureResolution.quality.defaultHorizontalEncoder.height, 1080);
    });

    test('defaultVerticalEncoder = crop nativo', () {
      final v = CaptureResolution.balanced.defaultVerticalEncoder;
      expect(v.width, CaptureResolution.balanced.verticalCropWidth);
      expect(v.height, CaptureResolution.balanced.verticalCropHeight);
    });
  });

  group('EncoderProfile', () {
    test('copyWith preserva dimensões e troca bitrate', () {
      final p = EncoderProfile.horizontal1080p.copyWith(bitrateBps: 4000000);
      expect(p.width, 1920);
      expect(p.height, 1080);
      expect(p.bitrateBps, 4000000);
      expect(p.fps, 30);
    });

    test('toMap serializa os campos', () {
      final m = EncoderProfile.vertical1080p.toMap();
      expect(m['width'], 1080);
      expect(m['height'], 1920);
      expect(m['fps'], 30);
      expect(m['bitrateBps'], 3500000);
      expect(m['gop'], 30);
    });
  });

  group('ThermalStatus', () {
    test('fromCode mapeia todos os níveis conhecidos', () {
      expect(ThermalStatus.fromCode(0), ThermalStatus.none);
      expect(ThermalStatus.fromCode(2), ThermalStatus.moderate);
      expect(ThermalStatus.fromCode(5), ThermalStatus.emergency);
    });

    test('fromCode desconhecido volta none', () {
      expect(ThermalStatus.fromCode(null), ThermalStatus.none);
      expect(ThermalStatus.fromCode(99), ThermalStatus.none);
    });

    test('shouldDegrade a partir de moderate', () {
      expect(ThermalStatus.none.shouldDegrade, isFalse);
      expect(ThermalStatus.light.shouldDegrade, isFalse);
      expect(ThermalStatus.moderate.shouldDegrade, isTrue);
      expect(ThermalStatus.severe.shouldDegrade, isTrue);
    });

    test('shouldStop a partir de emergency', () {
      expect(ThermalStatus.critical.shouldStop, isFalse);
      expect(ThermalStatus.emergency.shouldStop, isTrue);
      expect(ThermalStatus.shutdown.shouldStop, isTrue);
    });
  });

  group('StreamStats.fromMap', () {
    test('tolera mapa vazio', () {
      final s = StreamStats.fromMap({});
      expect(s.bitrateABps, 0);
      expect(s.fps, 0);
      expect(s.thermalStatus, ThermalStatus.none);
    });

    test('parseia valores numéricos', () {
      final s = StreamStats.fromMap({
        'bitrateA': 6000000,
        'bitrateB': 4500000,
        'fps': 29.97,
        'droppedFrames': 2,
        'thermalStatus': 2,
        'srtRtt': 18.4,
        'srtLoss': 0.12,
        'timestampMs': 1700000000000,
      });
      expect(s.bitrateABps, 6000000);
      expect(s.bitrateBBps, 4500000);
      expect(s.fps, closeTo(29.97, 0.001));
      expect(s.droppedFrames, 2);
      expect(s.thermalStatus, ThermalStatus.moderate);
      expect(s.srtRttMs, closeTo(18.4, 0.001));
      expect(s.srtLossPct, closeTo(0.12, 0.001));
      expect(s.timestampMs, 1700000000000);
    });
  });
}
