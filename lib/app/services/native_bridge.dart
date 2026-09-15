import 'dart:async';

import 'package:flutter/services.dart';

import '../models/camera_info.dart';
import '../models/network_profile.dart';
import '../models/resolution_profile.dart';
import '../models/stream_stats.dart';

class NativeBridge {
  NativeBridge({MethodChannel? control, EventChannel? stats})
    : _control = control ?? const MethodChannel('livegrid/control'),
      _stats = stats ?? const EventChannel('livegrid/stats');

  final MethodChannel _control;
  final EventChannel _stats;

  Stream<StreamStats>? _statsCache;

  Future<int?> init() async {
    return _control.invokeMethod<int>('init');
  }

  Future<List<CameraInfo>> listCameras() async {
    final result = await _control.invokeMethod<List<Object?>>('listCameras');
    if (result == null) return const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(CameraInfo.fromMap)
        .toList(growable: false);
  }

  Future<CaptureStartInfo> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    final raw = await _control.invokeMethod<Object?>('startCapture', {
      'profile': profile.toMap(),
      'network': network.toMap(),
    });
    final map = (raw is Map)
        ? raw.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    return CaptureStartInfo.fromMap(map);
  }

  Future<void> stop() async {
    await _control.invokeMethod<void>('stop');
  }

  Future<void> switchResolution(CaptureResolution resolution) async {
    await _control.invokeMethod<void>('switchResolution', {
      'width': resolution.width,
      'height': resolution.height,
    });
  }

  Future<void> setBitrate({int? horizontalBps, int? verticalBps}) async {
    await _control.invokeMethod<void>('setBitrate', {
      'horizontalBps': ?horizontalBps,
      'verticalBps': ?verticalBps,
    });
  }

  Future<void> setFrameRate(int fps) async {
    try {
      await _control.invokeMethod<void>('setFrameRate', {'fps': fps});
    } on MissingPluginException {
      return;
    }
  }

  Future<void> requestKeyframe() async {
    await _control.invokeMethod<void>('requestKeyframe');
  }

  Future<void> setVerticalCrop(double centerX) async {
    try {
      await _control.invokeMethod<void>('setVerticalCrop', {
        'centerX': centerX,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> switchCamera(String cameraId) async {
    try {
      await _control.invokeMethod<void>('switchCamera', {'cameraId': cameraId});
    } on MissingPluginException {
      return;
    }
  }

  Future<void> setTorch(bool enabled) async {
    try {
      await _control.invokeMethod<void>('setTorch', {'enabled': enabled});
    } on MissingPluginException {
      return;
    }
  }

  Future<void> setExposure(int value) async {
    try {
      await _control.invokeMethod<void>('setExposure', {'value': value});
    } on MissingPluginException {
      return;
    }
  }

  Future<CameraCapabilities> cameraCapabilities() async {
    try {
      final raw = await _control.invokeMethod<Object?>('cameraCapabilities');
      final map = (raw is Map)
          ? raw.cast<Object?, Object?>()
          : const <Object?, Object?>{};
      return CameraCapabilities.fromMap(map);
    } on MissingPluginException {
      return CameraCapabilities.none;
    }
  }

  Future<String?> deviceIp() async {
    try {
      return await _control.invokeMethod<String>('deviceIp');
    } on MissingPluginException {
      return null;
    }
  }

  Future<WifiBand> wifiBand() async {
    final raw = await _control.invokeMethod<String>('wifiBand');
    switch (raw) {
      case '2.4':
        return WifiBand.band24GHz;
      case '5':
        return WifiBand.band5GHz;
      default:
        return WifiBand.unknown;
    }
  }

  Stream<StreamStats> get statsStream {
    return _statsCache ??= _stats.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      return StreamStats.fromMap(map);
    });
  }
}

class CameraCapabilities {
  const CameraCapabilities({
    required this.hasFlash,
    required this.exposureMin,
    required this.exposureMax,
    required this.exposureStepEv,
  });

  final bool hasFlash;
  final int exposureMin;
  final int exposureMax;
  final double exposureStepEv;

  bool get hasExposureControl => exposureMax > exposureMin;

  static const none = CameraCapabilities(
    hasFlash: false,
    exposureMin: 0,
    exposureMax: 0,
    exposureStepEv: 0,
  );

  static CameraCapabilities fromMap(Map<Object?, Object?> map) {
    return CameraCapabilities(
      hasFlash: map['hasFlash'] as bool? ?? false,
      exposureMin: (map['exposureMin'] as num?)?.toInt() ?? 0,
      exposureMax: (map['exposureMax'] as num?)?.toInt() ?? 0,
      exposureStepEv: (map['exposureStepEv'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CaptureStartInfo {
  const CaptureStartInfo({
    this.horizontalUrl,
    this.verticalUrl,
    this.horizontalFile,
    this.verticalFile,
  });

  final String? horizontalUrl;
  final String? verticalUrl;
  final String? horizontalFile;
  final String? verticalFile;

  bool get hasFiles => horizontalFile != null || verticalFile != null;

  static CaptureStartInfo fromMap(Map<Object?, Object?> map) {
    return CaptureStartInfo(
      horizontalUrl: map['horizontalUrl'] as String?,
      verticalUrl: map['verticalUrl'] as String?,
      horizontalFile: map['horizontalFile'] as String?,
      verticalFile: map['verticalFile'] as String?,
    );
  }
}
