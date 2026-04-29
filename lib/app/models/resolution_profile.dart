enum CaptureResolution {
  economic(
    1280,
    720,
    'Econômico',
    'Frio. Horizontal 720p · Vertical 405×720 (upscale forte).',
  ),
  balanced(
    1920,
    1080,
    'Equilibrado',
    'Padrão. Horizontal 1080p nativo · Vertical 607×1080 (sub-HD).',
  ),
  quality(
    3840,
    2160,
    'Qualidade',
    'Aquece. Horizontal 1080p (downscale) · Vertical 1215×2160 nativo.',
  );

  const CaptureResolution(this.width, this.height, this.label, this.summary);

  final int width;
  final int height;
  final String label;
  final String summary;

  int get verticalCropWidth {
    final w = (height * 9) ~/ 16;
    return w.isEven ? w : w - 1;
  }

  int get verticalCropHeight => height;

  bool get coversVertical1080p => verticalCropWidth >= 1080;

  VerticalQuality get verticalQuality {
    final w = verticalCropWidth;
    if (w >= 1080) return VerticalQuality.fullHd;
    if (w >= 720) return VerticalQuality.reduced;
    return VerticalQuality.sub;
  }

  ThermalHint get thermalHint {
    switch (this) {
      case CaptureResolution.economic:
        return ThermalHint.cool;
      case CaptureResolution.balanced:
        return ThermalHint.normal;
      case CaptureResolution.quality:
        return ThermalHint.hot;
    }
  }

  EncoderProfile get defaultHorizontalEncoder {
    switch (this) {
      case CaptureResolution.economic:
        return const EncoderProfile(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 3000000,
          gop: 30,
        );
      case CaptureResolution.balanced:
        return const EncoderProfile(
          width: 1920,
          height: 1080,
          fps: 30,
          bitrateBps: 5000000,
          gop: 30,
        );
      case CaptureResolution.quality:
        return const EncoderProfile(
          width: 1920,
          height: 1080,
          fps: 30,
          bitrateBps: 6000000,
          gop: 30,
        );
    }
  }

  EncoderProfile get defaultVerticalEncoder {
    final w = verticalCropWidth;
    final h = verticalCropHeight;
    final bps = switch (this) {
      CaptureResolution.economic => 2000000,
      CaptureResolution.balanced => 3000000,
      CaptureResolution.quality => 5000000,
    };
    return EncoderProfile(
      width: w,
      height: h,
      fps: 30,
      bitrateBps: bps,
      gop: 30,
    );
  }
}

enum VerticalQuality {
  fullHd('FHD', 'Sem upscale'),
  reduced('HD', 'Upscale leve'),
  sub('SUB-HD', 'Upscale agressivo');

  const VerticalQuality(this.label, this.description);

  final String label;
  final String description;
}

enum ThermalHint {
  cool('Frio', 'Sustenta indefinido'),
  normal('OK', 'Sustenta sessão longa'),
  hot('Esquenta', 'Aquece em ~10 min, monitorar térmica');

  const ThermalHint(this.label, this.description);

  final String label;
  final String description;
}

enum CaptureMode {
  live('live', 'Live (OBS)', 'Stream único pro OBS. Crop final na cena.'),
  recording(
    'recording',
    'Gravação',
    'Salva 16:9 e 9:16 como MP4 no celular. Sem rede.',
  );

  const CaptureMode(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

class EncoderProfile {
  const EncoderProfile({
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateBps,
    required this.gop,
  });

  final int width;
  final int height;
  final int fps;
  final int bitrateBps;
  final int gop;

  static const horizontal1080p = EncoderProfile(
    width: 1920,
    height: 1080,
    fps: 30,
    bitrateBps: 4000000,
    gop: 30,
  );

  static const vertical1080p = EncoderProfile(
    width: 1080,
    height: 1920,
    fps: 30,
    bitrateBps: 3500000,
    gop: 30,
  );

  EncoderProfile copyWith({int? bitrateBps, int? fps}) => EncoderProfile(
    width: width,
    height: height,
    fps: fps ?? this.fps,
    bitrateBps: bitrateBps ?? this.bitrateBps,
    gop: gop,
  );

  Map<String, Object> toMap() => {
    'width': width,
    'height': height,
    'fps': fps,
    'bitrateBps': bitrateBps,
    'gop': gop,
  };
}

class SessionProfile {
  const SessionProfile({
    required this.capture,
    required this.horizontal,
    required this.vertical,
    this.cameraId,
    this.verticalCropCenterX = 0.5,
    this.mode = CaptureMode.live,
  });

  final CaptureResolution capture;
  final EncoderProfile horizontal;
  final EncoderProfile vertical;
  final String? cameraId;
  final double verticalCropCenterX;
  final CaptureMode mode;

  static SessionProfile get defaultProfile => SessionProfile(
    capture: CaptureResolution.balanced,
    horizontal: CaptureResolution.balanced.defaultHorizontalEncoder,
    vertical: CaptureResolution.balanced.defaultVerticalEncoder,
    mode: CaptureMode.live,
  );

  SessionProfile copyWith({
    CaptureResolution? capture,
    EncoderProfile? horizontal,
    EncoderProfile? vertical,
    String? cameraId,
    double? verticalCropCenterX,
    CaptureMode? mode,
  }) => SessionProfile(
    capture: capture ?? this.capture,
    horizontal: horizontal ?? this.horizontal,
    vertical: vertical ?? this.vertical,
    cameraId: cameraId ?? this.cameraId,
    verticalCropCenterX: verticalCropCenterX ?? this.verticalCropCenterX,
    mode: mode ?? this.mode,
  );

  Map<String, Object?> toMap() => {
    'capture': {'width': capture.width, 'height': capture.height},
    'horizontal': horizontal.toMap(),
    'vertical': vertical.toMap(),
    'cameraId': cameraId,
    'verticalCropCenterX': verticalCropCenterX,
    'mode': mode.wireValue,
  };
}
