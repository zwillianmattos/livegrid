import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../models/camera_info.dart';
import '../models/resolution_profile.dart';
import '../models/session_state.dart';
import '../models/thermal_status.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms/blur_icon_button.dart';
import '../widgets/atoms/pill_button.dart';
import '../widgets/live/crop_panel.dart';
import '../widgets/live/crop_pip.dart';
import '../widgets/live/error_bubble.dart';
import '../widgets/live/exposure_control.dart';
import '../widgets/live/fullscreen_preview.dart';
import '../widgets/live/hub_chrome.dart';
import '../widgets/live/record_button.dart';
import '../widgets/live/recording_hud.dart';
import '../widgets/live/right_rail.dart';
import '../widgets/live/saved_review.dart';
import '../widgets/quality/quality_sheet.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  static const double _rail = RightRail.width;

  bool _framing = false;
  bool _showGrid = false;
  bool _exposureOpen = false;
  DateTime? _liveStartedAt;
  SavedRecording? _lastSaved;
  bool _showSaved = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.initialize();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final c = widget.controller;
    if (c.isLive && _liveStartedAt == null) {
      _liveStartedAt = DateTime.now();
    } else if (c.state == SessionState.idle || c.state == SessionState.error) {
      _liveStartedAt = null;
    }
    if (c.state != SessionState.idle) _framing = false;
    setState(() {});
  }

  bool get _recording {
    final s = widget.controller.state;
    return widget.controller.isLive || s == SessionState.stopping;
  }

  void _setFraming(bool value) {
    if (value && widget.controller.state != SessionState.idle) return;
    setState(() {
      _framing = value;
      _exposureOpen = false;
    });
  }

  void _toggleGrid() => setState(() => _showGrid = !_showGrid);

  void _toggleExposure() => setState(() => _exposureOpen = !_exposureOpen);

  void _cycleCamera() {
    final cams = widget.controller.cameras;
    if (cams.length < 2) return;
    final idx = cams.indexWhere(
      (c) => c.id == widget.controller.selectedCamera?.id,
    );
    widget.controller.selectCamera(cams[(idx + 1) % cams.length].id);
  }

  void _toggleSharpness() {
    final current = widget.controller.profile.capture;
    widget.controller.switchCapture(
      current == CaptureResolution.quality
          ? CaptureResolution.balanced
          : CaptureResolution.quality,
    );
  }

  void _openQuality() {
    setState(() => _exposureOpen = false);
    showQualitySheet(context, widget.controller);
  }

  Future<void> _stopAndAnnounce() async {
    final c = widget.controller;
    final wasRecording = c.profile.mode == CaptureMode.recording;
    final info = c.lastStart;
    final startedAt = _liveStartedAt;
    final duration = startedAt == null
        ? null
        : DateTime.now().difference(startedAt);
    await c.stop();
    if (!mounted) return;
    if (wasRecording && info != null && info.hasFiles) {
      setState(() {
        _lastSaved = SavedRecording(
          horizontalFile: info.horizontalFile,
          verticalFile: info.verticalFile,
          duration: duration,
          startedAt: startedAt,
        );
        _showSaved = true;
      });
    }
  }

  SavedRecording? get _reviewable {
    if (_lastSaved != null) return _lastSaved;
    final info = widget.controller.lastStart;
    if (info == null || !info.hasFiles) return null;
    return SavedRecording(
      horizontalFile: info.horizontalFile,
      verticalFile: info.verticalFile,
    );
  }

  String _lensLabel(CameraInfo? cam) {
    if (cam == null) return '1x';
    if (cam.lens == CameraLens.front) return 'FRONTAL';
    if (cam.lens == CameraLens.external) return 'EXTERNA';
    final focal = _focal(cam);
    final main = widget.controller.cameras
        .where((c) => c.lens == CameraLens.back)
        .map(_focal)
        .whereType<double>()
        .firstOrNull;
    if (focal == null || main == null || main <= 0) return '1x';
    final ratio = focal / main;
    final text = ratio == ratio.roundToDouble()
        ? ratio.toStringAsFixed(0)
        : ratio.toStringAsFixed(1);
    return '${text}x';
  }

  static double? _focal(CameraInfo cam) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*mm').firstMatch(cam.label);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static String _fpsLabel(int fps) => switch (fps) {
    <= 24 => '$fps · CINEMA',
    >= 60 => '$fps · FLUIDO',
    _ => '$fps · STORIES',
  };

  List<String> _formatParts(SessionProfile p) => [
    '16:9 ${p.horizontal.height}p',
    '9:16 ${p.vertical.width}p',
    '${p.horizontal.fps} FPS',
  ];

  (String, Color) _status(SessionState s) => switch (s) {
    SessionState.idle => ('PRONTO', AppColors.safe),
    SessionState.starting => ('INICIANDO', AppColors.textMuted),
    SessionState.error => ('ERRO', AppColors.warn),
    _ => ('GRAVANDO', AppColors.live),
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cropCenterX = FullscreenPreview.clampCenter(
      c.profile.verticalCropCenterX,
    );
    final recording = _recording;
    final mode = recording
        ? PreviewMode.recording
        : (_framing ? PreviewMode.framing : PreviewMode.hub);
    final saved = _showSaved ? _lastSaved : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FullscreenPreview(
              textureId: c.textureId,
              mode: mode,
              cropCenterX: cropCenterX,
              onCropChanged: c.setVerticalCropCenter,
              showGrid: _showGrid,
            ),
          ),
          if (mode == PreviewMode.hub) ..._hub(c),
          if (mode == PreviewMode.framing) ..._framingChrome(c, cropCenterX),
          if (mode == PreviewMode.recording)
            ..._recordingChrome(c, cropCenterX),
          if (c.errorMessage != null && saved == null)
            Positioned(
              left: 16,
              right: _rail + 16,
              bottom: 72,
              child: SafeArea(
                child: Center(child: ErrorBubble(message: c.errorMessage!)),
              ),
            ),
          if (saved != null)
            Positioned.fill(
              child: SavedReview(
                recording: saved,
                onClose: () => setState(() => _showSaved = false),
                onShareVertical: c.shareFile,
                onOpenGallery: c.openGallery,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _hub(SessionController c) {
    final idle = c.state == SessionState.idle || c.state == SessionState.error;
    final (statusLabel, statusColor) = _status(c.state);
    final reviewable = _reviewable;
    final quality = c.profile.capture == CaptureResolution.quality;
    return [
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        child: RightRail(
          top: [
            if (c.capabilities.hasFlash)
              BlurIconButton(
                icon: c.torchEnabled ? Icons.flash_on : Icons.flash_off,
                active: c.torchEnabled,
                tooltip: 'Flash',
                onPressed: c.toggleTorch,
              ),
            if (c.capabilities.hasExposureControl)
              BlurIconButton(
                icon: Icons.exposure,
                active: _exposureOpen,
                tooltip: 'Exposição',
                onPressed: _toggleExposure,
              ),
          ],
          center: RecordButton(
            state: c.state,
            onStart: c.start,
            onStop: _stopAndAnnounce,
          ),
          bottom: [
            BlurIconButton(
              icon: Icons.grid_3x3,
              active: _showGrid,
              tooltip: 'Grade',
              onPressed: _toggleGrid,
            ),
          ],
        ),
      ),
      SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 16,
              right: _rail + 72,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusPill(label: statusLabel, color: statusColor),
                    const SizedBox(width: 8),
                    FormatPill(
                      parts: _formatParts(c.profile),
                      onTap: _openQuality,
                    ),
                    if (c.stats.audioInputType.isExternal) ...[
                      const SizedBox(width: 8),
                      ExternalMicPill(type: c.stats.audioInputType),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: _rail + 16,
              child: BlurIconButton(
                icon: Icons.tune,
                tooltip: 'Qualidade',
                onPressed: _openQuality,
              ),
            ),
            if (_exposureOpen && c.capabilities.hasExposureControl)
              Positioned(
                top: 68,
                right: _rail + 8,
                child: ExposureControl(
                  value: c.exposureValue,
                  min: c.capabilities.exposureMin,
                  max: c.capabilities.exposureMax,
                  stepEv: c.capabilities.exposureStepEv,
                  onChanged: c.setExposure,
                ),
              ),
            if (reviewable != null && idle)
              Positioned(
                left: 16,
                bottom: 16,
                child: LastRecordingThumb(
                  onTap: () => setState(() {
                    _lastSaved = reviewable;
                    _showSaved = true;
                  }),
                ),
              ),
            Positioned(
              left: 80,
              right: _rail + 8,
              bottom: 16,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PillButton(
                        label: _lensLabel(c.selectedCamera),
                        semanticLabel: 'Trocar lente',
                        onPressed: idle && c.cameras.length > 1
                            ? _cycleCamera
                            : null,
                      ),
                      const SizedBox(width: 6),
                      PillButton(
                        label: quality ? 'NITIDEZ ALTA' : 'NITIDEZ PADRÃO',
                        onPressed: idle ? _toggleSharpness : null,
                      ),
                      const SizedBox(width: 6),
                      PillButton(
                        label: _fpsLabel(c.profile.horizontal.fps),
                        semanticLabel: 'Quadros por segundo',
                        onPressed: idle ? _openQuality : null,
                      ),
                      const SizedBox(width: 6),
                      PillButton(
                        label: 'ENQUADRAR',
                        accent: AppColors.edit,
                        onPressed: c.state == SessionState.idle
                            ? () => _setFraming(true)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _framingChrome(SessionController c, double cropCenterX) {
    return [
      SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 16,
              left: 16,
              child: StatusPill(
                label: 'ENQUADRAR 9:16',
                color: AppColors.edit,
                squareDot: true,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: CropPanel(
                cropCenterX: cropCenterX,
                onCropChanged: c.setVerticalCropCenter,
                onRecenter: () => c.setVerticalCropCenter(0.5),
                onDone: () => _setFraming(false),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _recordingChrome(SessionController c, double cropCenterX) {
    final hot =
        c.state == SessionState.degraded ||
        c.stats.thermalStatus.index >= ThermalStatus.severe.index;
    return [
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        child: RightRail(
          background: null,
          top: const [],
          center: RecordButton(
            state: c.state,
            onStart: c.start,
            onStop: _stopAndAnnounce,
          ),
          bottom: const [],
        ),
      ),
      SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(child: RecTimerPill(startedAt: _liveStartedAt)),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MicLevelPill(
                    level: c.stats.audioLevel,
                    inputType: c.stats.audioInputType,
                    inputName: c.stats.audioInputName,
                  ),
                  if (hot) const SizedBox(height: 8),
                  if (hot) const ThermalPill(fps: 24),
                ],
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: CropPip(textureId: c.textureId, cropCenterX: cropCenterX),
            ),
            Positioned(
              left: 100,
              bottom: 16,
              child: Row(
                children: [
                  BitrateChip(label: 'H', bps: c.stats.bitrateABps),
                  const SizedBox(width: 6),
                  BitrateChip(label: 'V', bps: c.stats.bitrateBBps),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
