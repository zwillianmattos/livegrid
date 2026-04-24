enum CaptureResolution {
  uhd4032x3024(4032, 3024),
  uhd3840x2160(3840, 2160),
  fhd2880x2160(2880, 2160);

  const CaptureResolution(this.width, this.height);

  final int width;
  final int height;

  bool get coversVertical1080p {
    final cropW = (height * 9) ~/ 16;
    return cropW >= 1080;
  }
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
    bitrateBps: 6000000,
    gop: 30,
  );

  static const vertical1080p = EncoderProfile(
    width: 1080,
    height: 1920,
    fps: 30,
    bitrateBps: 5000000,
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
  });

  final CaptureResolution capture;
  final EncoderProfile horizontal;
  final EncoderProfile vertical;
  final String? cameraId;

  static const defaultProfile = SessionProfile(
    capture: CaptureResolution.uhd3840x2160,
    horizontal: EncoderProfile.horizontal1080p,
    vertical: EncoderProfile.vertical1080p,
  );

  SessionProfile copyWith({
    CaptureResolution? capture,
    EncoderProfile? horizontal,
    EncoderProfile? vertical,
    String? cameraId,
  }) =>
      SessionProfile(
        capture: capture ?? this.capture,
        horizontal: horizontal ?? this.horizontal,
        vertical: vertical ?? this.vertical,
        cameraId: cameraId ?? this.cameraId,
      );

  Map<String, Object?> toMap() => {
        'capture': {
          'width': capture.width,
          'height': capture.height,
        },
        'horizontal': horizontal.toMap(),
        'vertical': vertical.toMap(),
        'cameraId': cameraId,
      };
}
