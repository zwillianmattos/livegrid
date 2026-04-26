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

  Future<void> startCapture({
    required SessionProfile profile,
    required NetworkProfile network,
  }) async {
    await _control.invokeMethod<void>('startCapture', {
      'profile': profile.toMap(),
      'network': network.toMap(),
    });
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
