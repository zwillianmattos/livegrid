import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/camera_info.dart';
import '../models/network_profile.dart';
import '../models/resolution_profile.dart';
import '../models/session_state.dart';
import '../models/stream_stats.dart';
import '../models/thermal_status.dart';
import '../services/native_bridge.dart';

typedef PermissionGate = Future<bool> Function();

class SessionController extends ChangeNotifier {
  SessionController({NativeBridge? bridge, PermissionGate? permissionGate})
      : _bridge = bridge ?? NativeBridge(),
        _permissionGate = permissionGate ?? _defaultPermissionGate;

  final NativeBridge _bridge;
  final PermissionGate _permissionGate;

  SessionState _state = SessionState.idle;
  int? _textureId;
  StreamStats _stats = StreamStats.zero;
  WifiBand _wifiBand = WifiBand.unknown;
  String? _errorMessage;
  SessionProfile _profile = SessionProfile.defaultProfile;
  NetworkProfile _network = NetworkProfile.defaults;
  List<CameraInfo> _cameras = const [];

  StreamSubscription<StreamStats>? _statsSub;

  SessionState get state => _state;
  int? get textureId => _textureId;
  StreamStats get stats => _stats;
  WifiBand get wifiBand => _wifiBand;
  String? get errorMessage => _errorMessage;
  SessionProfile get profile => _profile;
  NetworkProfile get network => _network;
  List<CameraInfo> get cameras => _cameras;

  CameraInfo? get selectedCamera {
    if (_cameras.isEmpty) return null;
    if (_profile.cameraId == null) return _cameras.first;
    return _cameras.firstWhere(
      (c) => c.id == _profile.cameraId,
      orElse: () => _cameras.first,
    );
  }

  bool get isLive =>
      _state == SessionState.live || _state == SessionState.degraded;

  Future<void> initialize() async {
    try {
      _textureId = await _bridge.init();
      _wifiBand = await _bridge.wifiBand();
      _cameras = await _bridge.listCameras();
      if (_profile.cameraId == null && _cameras.isNotEmpty) {
        final back = _cameras.firstWhere(
          (c) => c.lens == CameraLens.back,
          orElse: () => _cameras.first,
        );
        _profile = _profile.copyWith(cameraId: back.id);
      }
      _statsSub ??= _bridge.statsStream.listen(_onStats, onError: _onStatsError);
      notifyListeners();
    } catch (e) {
      _setError('init failed: $e');
    }
  }

  Future<void> refreshCameras() async {
    _cameras = await _bridge.listCameras();
    notifyListeners();
  }

  void selectCamera(String cameraId) {
    _profile = _profile.copyWith(cameraId: cameraId);
    notifyListeners();
  }

  void updateProfile(SessionProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  void updateNetwork(NetworkProfile network) {
    _network = network;
    notifyListeners();
  }

  Future<void> start() async {
    if (_state != SessionState.idle && _state != SessionState.error) return;
    _errorMessage = null;
    _state = SessionState.starting;
    notifyListeners();
    try {
      if (!await _permissionGate()) {
        _setError('Permissão de câmera/microfone/notificação negada');
        return;
      }
      await _bridge.startCapture(profile: _profile, network: _network);
      _state = SessionState.live;
      notifyListeners();
    } catch (e) {
      _setError('start failed: $e');
    }
  }

  static Future<bool> _defaultPermissionGate() async {
    final needed = <Permission>[Permission.camera, Permission.microphone];
    if (Platform.isAndroid) {
      needed.add(Permission.notification);
    }
    final statuses = await needed.request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> stop() async {
    if (_state == SessionState.idle) return;
    _state = SessionState.stopping;
    notifyListeners();
    try {
      await _bridge.stop();
      _state = SessionState.idle;
      notifyListeners();
    } catch (e) {
      _setError('stop failed: $e');
    }
  }

  Future<void> switchCapture(CaptureResolution resolution) async {
    _profile = _profile.copyWith(capture: resolution);
    notifyListeners();
    if (isLive) {
      await _bridge.switchResolution(resolution);
    }
  }

  Future<void> refreshWifiBand() async {
    _wifiBand = await _bridge.wifiBand();
    notifyListeners();
  }

  void _onStats(StreamStats sample) {
    _stats = sample;
    _applyThermalPolicy(sample.thermalStatus);
    notifyListeners();
  }

  void _onStatsError(Object error) {
    _setError('stats stream error: $error');
  }

  Future<void> _applyThermalPolicy(ThermalStatus status) async {
    if (!isLive) return;
    switch (status) {
      case ThermalStatus.none:
      case ThermalStatus.light:
        if (_state == SessionState.degraded) {
          _state = SessionState.live;
        }
        break;
      case ThermalStatus.moderate:
        _state = SessionState.degraded;
        await _bridge.setBitrate(
          horizontalBps: (_profile.horizontal.bitrateBps * 0.75).toInt(),
          verticalBps: (_profile.vertical.bitrateBps * 0.75).toInt(),
        );
        break;
      case ThermalStatus.severe:
        _state = SessionState.degraded;
        await _bridge.switchResolution(CaptureResolution.fhd2880x2160);
        break;
      case ThermalStatus.critical:
        _state = SessionState.degraded;
        await _bridge.setBitrate(
          horizontalBps: 4000000,
          verticalBps: 0,
        );
        break;
      case ThermalStatus.emergency:
      case ThermalStatus.shutdown:
        await stop();
        break;
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    _state = SessionState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }
}
