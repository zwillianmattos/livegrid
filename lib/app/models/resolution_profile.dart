enum CaptureResolution {
  uhd4032x3024(4032, 3024),
  uhd3840x2160(3840, 2160),
  fhd2880x2160(2880, 2160),
  fhd1920x1080(1920, 1080),
  hd1280x720(1280, 720);

  const CaptureResolution(this.width, this.height);

  final int width;
  final int height;

  int get verticalCropWidth => (height * 9) ~/ 16;
  int get verticalCropHeight => height;

  bool get coversVertical1080p => verticalCropWidth >= 1080;

  VerticalQuality get verticalQuality {
    final w = verticalCropWidth;
    if (w >= 1440) return VerticalQuality.pristine;
    if (w >= 1080) return VerticalQuality.fullHd;
    if (w >= 720) return VerticalQuality.reduced;
    return VerticalQuality.sub;
  }
}

enum VerticalQuality {
  pristine('FHD+', 'Acima de 1080p'),
  fullHd('FHD', '1080p cheio'),
  reduced('HD', 'Upscale do encoder'),
  sub('SUB-HD', 'Upscale agressivo');

  const VerticalQuality(this.label, this.description);

  final String label;
  final String description;
}

enum ChannelMode {
  both('both', 'Horizontal + Vertical'),
  horizontalOnly('horizontalOnly', 'Apenas horizontal'),
  verticalOnly('verticalOnly', 'Apenas vertical');

  const ChannelMode(this.wireValue, this.label);

  final String wireValue;
  final String label;
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
    this.channelMode = ChannelMode.both,
  });

  final CaptureResolution capture;
  final EncoderProfile horizontal;
  final EncoderProfile vertical;
  final String? cameraId;
  final double verticalCropCenterX;
  final ChannelMode channelMode;

  static const defaultProfile = SessionProfile(
    capture: CaptureResolution.fhd1920x1080,
    horizontal: EncoderProfile.horizontal1080p,
    vertical: EncoderProfile.vertical1080p,
    channelMode: ChannelMode.horizontalOnly,
  );

  SessionProfile copyWith({
    CaptureResolution? capture,
    EncoderProfile? horizontal,
    EncoderProfile? vertical,
    String? cameraId,
    double? verticalCropCenterX,
    ChannelMode? channelMode,
  }) => SessionProfile(
    capture: capture ?? this.capture,
    horizontal: horizontal ?? this.horizontal,
    vertical: vertical ?? this.vertical,
    cameraId: cameraId ?? this.cameraId,
    verticalCropCenterX: verticalCropCenterX ?? this.verticalCropCenterX,
    channelMode: channelMode ?? this.channelMode,
  );

  Map<String, Object?> toMap() => {
    'capture': {'width': capture.width, 'height': capture.height},
    'horizontal': horizontal.toMap(),
    'vertical': vertical.toMap(),
    'cameraId': cameraId,
    'verticalCropCenterX': verticalCropCenterX,
    'channelMode': channelMode.wireValue,
  };
}
