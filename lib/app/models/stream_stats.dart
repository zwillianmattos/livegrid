import 'thermal_status.dart';

class StreamStats {
  const StreamStats({
    required this.bitrateABps,
    required this.bitrateBBps,
    required this.fps,
    required this.droppedFrames,
    required this.thermalStatus,
    required this.srtRttMs,
    required this.srtLossPct,
    required this.txDatagramsA,
    required this.txBytesA,
    required this.txErrorsA,
    required this.txDatagramsB,
    required this.txBytesB,
    required this.txErrorsB,
    required this.timestampMs,
  });

  final int bitrateABps;
  final int bitrateBBps;
  final double fps;
  final int droppedFrames;
  final ThermalStatus thermalStatus;
  final double srtRttMs;
  final double srtLossPct;
  final int txDatagramsA;
  final int txBytesA;
  final int txErrorsA;
  final int txDatagramsB;
  final int txBytesB;
  final int txErrorsB;
  final int timestampMs;

  static const zero = StreamStats(
    bitrateABps: 0,
    bitrateBBps: 0,
    fps: 0,
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
    timestampMs: 0,
  );

  factory StreamStats.fromMap(Map<Object?, Object?> map) {
    return StreamStats(
      bitrateABps: (map['bitrateA'] as num?)?.toInt() ?? 0,
      bitrateBBps: (map['bitrateB'] as num?)?.toInt() ?? 0,
      fps: (map['fps'] as num?)?.toDouble() ?? 0,
      droppedFrames: (map['droppedFrames'] as num?)?.toInt() ?? 0,
      thermalStatus: ThermalStatus.fromCode(
        (map['thermalStatus'] as num?)?.toInt(),
      ),
      srtRttMs: (map['srtRtt'] as num?)?.toDouble() ?? 0,
      srtLossPct: (map['srtLoss'] as num?)?.toDouble() ?? 0,
      txDatagramsA: (map['txDatagramsA'] as num?)?.toInt() ?? 0,
      txBytesA: (map['txBytesA'] as num?)?.toInt() ?? 0,
      txErrorsA: (map['txErrorsA'] as num?)?.toInt() ?? 0,
      txDatagramsB: (map['txDatagramsB'] as num?)?.toInt() ?? 0,
      txBytesB: (map['txBytesB'] as num?)?.toInt() ?? 0,
      txErrorsB: (map['txErrorsB'] as num?)?.toInt() ?? 0,
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}
