enum CameraLens { back, front, external, unknown }

class CameraInfo {
  const CameraInfo({
    required this.id,
    required this.lens,
    required this.label,
    this.maxWidth,
    this.maxHeight,
  });

  final String id;
  final CameraLens lens;
  final String label;
  final int? maxWidth;
  final int? maxHeight;

  factory CameraInfo.fromMap(Map<Object?, Object?> map) {
    return CameraInfo(
      id: map['id'] as String? ?? '',
      lens: _parseLens(map['lens'] as String?),
      label: map['label'] as String? ?? '',
      maxWidth: (map['maxWidth'] as num?)?.toInt(),
      maxHeight: (map['maxHeight'] as num?)?.toInt(),
    );
  }

  static CameraLens _parseLens(String? value) {
    switch (value) {
      case 'back':
        return CameraLens.back;
      case 'front':
        return CameraLens.front;
      case 'external':
        return CameraLens.external;
      default:
        return CameraLens.unknown;
    }
  }
}
