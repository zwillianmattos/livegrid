import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/camera_info.dart';
import '../models/network_profile.dart';
import '../models/resolution_profile.dart';
import '../models/session_state.dart';
import '../models/stream_stats.dart';
import '../models/thermal_status.dart';
import '../services/native_bridge.dart';
import '../services/permission_probe.dart';

export '../services/native_bridge.dart' show CameraCapabilities;
export '../services/permission_probe.dart';

typedef PermissionGate = Future<bool> Function();

class SessionController extends ChangeNotifier {
  SessionController({
    NativeBridge? bridge,
    PermissionGate? permissionGate,
    PermissionProbe? permissionProbe,
  }) : _bridge = bridge ?? NativeBridge(),
       _permissionGate = permissionGate,
       _permissionProbe = permissionProbe ?? const SystemPermissionProbe();

  final NativeBridge _bridge;
  final PermissionGate? _permissionGate;
  final PermissionProbe _permissionProbe;
  PermissionStatuses _permissions = const {
    AppPermission.camera: AppPermissionStatus.pending,
    AppPermission.microphone: AppPermissionStatus.pending,
    AppPermission.photos: AppPermissionStatus.pending,
  };

  SessionState _state = SessionState.idle;
  int? _textureId;
  StreamStats _stats = StreamStats.zero;
  WifiBand _wifiBand = WifiBand.unknown;
  String? _errorMessage;
  SessionProfile _profile = SessionProfile.defaultProfile;
  NetworkProfile _network = NetworkProfile.defaults;
  List<CameraInfo> _cameras = const [];

  StreamSubscription<StreamStats>? _statsSub;
  ThermalStatus? _appliedThermal;
  CaptureStartInfo? _lastStart;
  bool _torchEnabled = false;
  int _exposureValue = 0;
  CameraCapabilities _capabilities = CameraCapabilities.none;

  SessionState get state => _state;
  int? get textureId => _textureId;
  StreamStats get stats => _stats;
  WifiBand get wifiBand => _wifiBand;
  String? get errorMessage => _errorMessage;
  SessionProfile get profile => _profile;
  NetworkProfile get network => _network;
  List<CameraInfo> get cameras => _cameras;
  CaptureStartInfo? get lastStart => _lastStart;
  bool get torchEnabled => _torchEnabled;
  int get exposureValue => _exposureValue;
  CameraCapabilities get capabilities => _capabilities;
  PermissionStatuses get permissions => Map.unmodifiable(_permissions);

  AppPermissionStatus permissionStatus(AppPermission permission) =>
      _permissions[permission] ?? AppPermissionStatus.pending;

  bool get permissionsReady =>
      permissionStatus(AppPermission.camera) == AppPermissionStatus.granted;

  bool get hasPermanentlyDeniedPermission =>
      _permissions.values.contains(AppPermissionStatus.permanentlyDenied);

  Future<void> checkPermissions() async {
    _setPermissions(await _permissionProbe.check());
  }

  Future<void> requestPermissions() async {
    _setPermissions(await _permissionProbe.request());
  }

  Future<bool> openPermissionSettings() => _permissionProbe.openSettings();

  void _setPermissions(PermissionStatuses statuses) {
    _permissions = {..._permissions, ...statuses};
    notifyListeners();
  }

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

  Future<void>? _initFuture;
  Future<void>? _networkInfoFuture;

  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      _textureId = await _bridge.init();
      _statsSub ??= _bridge.statsStream.listen(
        _onStats,
        onError: _onStatsError,
      );
      notifyListeners();
      final results = await Future.wait<Object>([
        _bridge.listCameras(),
        _bridge.cameraCapabilities(),
      ]);
      _cameras = results[0] as List<CameraInfo>;
      _capabilities = results[1] as CameraCapabilities;
      if (_profile.cameraId == null && _cameras.isNotEmpty) {
        final back = _cameras.firstWhere(
          (c) => c.lens == CameraLens.back,
          orElse: () => _cameras.first,
        );
        _profile = _profile.copyWith(cameraId: back.id);
      }
      notifyListeners();
    } catch (e) {
      _initFuture = null;
      _setError('init failed: $e');
    }
  }

  Future<void> _ensureNetworkInfo() => _networkInfoFuture ??= () async {
    try {
      _wifiBand = await _bridge.wifiBand();
      final ip = await _bridge.deviceIp();
      if (ip != null && ip.isNotEmpty) {
        _network = _network.copyWith(obsHost: ip);
      }
      notifyListeners();
    } catch (e) {
      _networkInfoFuture = null;
      rethrow;
    }
  }();

  Future<void> refreshCameras() async {
    _cameras = await _bridge.listCameras();
    notifyListeners();
  }

  Future<void> refreshDeviceIp() async {
    final ip = await _bridge.deviceIp();
    if (ip != null && ip.isNotEmpty && ip != _network.obsHost) {
      _network = _network.copyWith(obsHost: ip);
      notifyListeners();
    }
  }

  Future<void> selectCamera(String cameraId) async {
    if (cameraId == _profile.cameraId) return;
    _profile = _profile.copyWith(cameraId: cameraId);
    notifyListeners();
    await _bridge.switchCamera(cameraId);
    _capabilities = await _bridge.cameraCapabilities();
    _torchEnabled = false;
    _exposureValue = 0;
    notifyListeners();
  }

  Future<void> updateProfile(SessionProfile profile) async {
    final prev = _profile;
    _profile = profile;
    notifyListeners();
    if (!isLive) return;
    if (prev.capture != profile.capture) {
      await _bridge.switchResolution(profile.capture);
    }
    final hChanged =
        prev.horizontal.bitrateBps != profile.horizontal.bitrateBps;
    final vChanged = prev.vertical.bitrateBps != profile.vertical.bitrateBps;
    if (hChanged || vChanged) {
      await _bridge.setBitrate(
        horizontalBps: hChanged ? profile.horizontal.bitrateBps : null,
        verticalBps: vChanged ? profile.vertical.bitrateBps : null,
      );
    }
    if (prev.horizontal.fps != profile.horizontal.fps) {
      await _bridge.setFrameRate(profile.horizontal.fps);
    }
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
      final gate = _permissionGate ?? _defaultPermissionGate;
      if (!await gate()) {
        _setError('Permissão de câmera negada');
        return;
      }
      if (_profile.mode == CaptureMode.live) await _ensureNetworkInfo();
      _lastStart = await _bridge.startCapture(
        profile: _profile,
        network: _network,
      );
      _state = SessionState.live;
      notifyListeners();
    } catch (e) {
      _setError('start failed: $e');
    }
  }

  Future<bool> _defaultPermissionGate() async {
    _permissions = {..._permissions, ...await _permissionProbe.check()};
    if (permissionsReady) return true;
    _permissions = {..._permissions, ...await _permissionProbe.request()};
    return permissionsReady;
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
    _profile = _profile.copyWith(
      capture: resolution,
      horizontal: resolution.defaultHorizontalEncoder.copyWith(
        bitrateBps: _profile.horizontal.bitrateBps,
        fps: _profile.horizontal.fps,
        gop: _profile.horizontal.gop,
      ),
      vertical: resolution.defaultVerticalEncoder.copyWith(
        bitrateBps: _profile.vertical.bitrateBps,
        fps: _profile.vertical.fps,
        gop: _profile.vertical.gop,
      ),
    );
    notifyListeners();
    if (isLive) {
      await _bridge.switchResolution(resolution);
    }
  }

  Future<void> setVerticalCropCenter(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (_profile.verticalCropCenterX == clamped) return;
    _profile = _profile.copyWith(verticalCropCenterX: clamped);
    notifyListeners();
  }

  Future<void> toggleTorch() async {
    if (!_capabilities.hasFlash) return;
    _torchEnabled = !_torchEnabled;
    notifyListeners();
    await _bridge.setTorch(_torchEnabled);
  }

  Future<void> setExposure(int value) async {
    if (!_capabilities.hasExposureControl) return;
    final clamped = value.clamp(
      _capabilities.exposureMin,
      _capabilities.exposureMax,
    );
    if (clamped == _exposureValue) return;
    _exposureValue = clamped;
    notifyListeners();
    await _bridge.setExposure(clamped);
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
    if (_appliedThermal == status) return;
    _appliedThermal = status;

    final hBase = _profile.horizontal.bitrateBps;
    final vBase = _profile.vertical.bitrateBps;
    final fpsBase = _profile.horizontal.fps;

    switch (status) {
      case ThermalStatus.none:
      case ThermalStatus.light:
        _state = SessionState.live;
        await _bridge.setFrameRate(fpsBase);
        await _bridge.setBitrate(horizontalBps: hBase, verticalBps: vBase);
        break;
      case ThermalStatus.moderate:
        _state = SessionState.live;
        await _bridge.setFrameRate(fpsBase);
        await _bridge.setBitrate(
          horizontalBps: (hBase * 0.90).toInt(),
          verticalBps: (vBase * 0.90).toInt(),
        );
        break;
      case ThermalStatus.severe:
        _state = SessionState.degraded;
        await _bridge.setFrameRate(24);
        await _bridge.setBitrate(
          horizontalBps: (hBase * 0.75).toInt(),
          verticalBps: (vBase * 0.75).toInt(),
        );
        break;
      case ThermalStatus.critical:
        _state = SessionState.degraded;
        await _bridge.setFrameRate(24);
        await _bridge.setBitrate(
          horizontalBps: (hBase * 0.60).toInt(),
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

  Future<void> shareFile(String path) async {
    try {
      await _bridge.shareFile(path);
    } on Exception catch (e) {
      debugPrint('shareFile failed: $e');
    }
  }

  Future<void> openGallery() async {
    try {
      await _bridge.openGallery();
    } on Exception catch (e) {
      debugPrint('openGallery failed: $e');
    }
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }
}
