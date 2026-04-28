import 'package:flutter/material.dart';

import '../constants/crop.dart';
import '../controllers/session_controller.dart';
import '../models/resolution_profile.dart';
import '../theme/page_routes.dart';
import '../widgets/atoms/blur_icon_button.dart';
import '../widgets/live/crop_panel.dart';
import '../widgets/live/draggable_pip.dart';
import '../widgets/live/error_bubble.dart';
import '../widgets/live/fullscreen_preview.dart';
import '../widgets/live/record_button.dart';
import '../widgets/live/top_chrome.dart';
import 'settings_page.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage>
    with SingleTickerProviderStateMixin {
  static const bool _cropEditEnabled = false;
  bool _configureMode = false;
  bool _showGrid = false;
  DateTime? _liveStartedAt;
  late final AnimationController _modeCtrl;

  @override
  void initState() {
    super.initState();
    _modeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.initialize();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _modeCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final wasLive = _liveStartedAt != null;
    final nowLive = widget.controller.isLive;
    if (nowLive && !wasLive) {
      _liveStartedAt = DateTime.now();
    } else if (!nowLive && wasLive) {
      _liveStartedAt = null;
    }
    setState(() {});
  }

  void _toggleConfigure() {
    if (!_cropEditEnabled) return;
    setState(() {
      _configureMode = !_configureMode;
      if (_configureMode) {
        _modeCtrl.forward();
      } else {
        _modeCtrl.reverse();
      }
    });
  }

  void _toggleGrid() => setState(() => _showGrid = !_showGrid);

  void _openSettings() {
    Navigator.of(
      context,
    ).push(fadeRoute((_) => SettingsPage(controller: widget.controller)));
  }

  Future<void> _stopAndAnnounce(SessionController c) async {
    final wasRecording = c.profile.mode == CaptureMode.recording;
    final info = c.lastStart;
    await c.stop();
    if (!mounted) return;
    if (wasRecording && info != null && info.hasFiles) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'Salvo:\n'
            '${_basename(info.horizontalFile)}\n'
            '${_basename(info.verticalFile)}',
          ),
        ),
      );
    }
  }

  static String _basename(String? path) {
    if (path == null) return '—';
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cropCenterX = c.profile.verticalCropCenterX.clamp(
      kHalfCropRatio,
      1.0 - kHalfCropRatio,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FullscreenPreview(
              textureId: c.textureId,
              configure: _configureMode,
              configureAnim: _modeCtrl,
              cropCenterX: cropCenterX,
              onCropChanged: c.setVerticalCropCenter,
              showGrid: _showGrid,
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: TopChrome(
                    state: c.state,
                    stats: c.stats,
                    wifiBand: c.wifiBand,
                    liveStartedAt: _liveStartedAt,
                    configure: _configureMode,
                    onConfigure: _cropEditEnabled ? _toggleConfigure : null,
                    onSettings: _openSettings,
                  ),
                ),
                Positioned.fill(
                  child: DraggablePip(
                    textureId: c.textureId,
                    cropCenterX: cropCenterX,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: Center(
                    child: _FadeHide(
                      anim: _modeCtrl,
                      child: RecordButton(
                        state: c.state,
                        onStart: c.start,
                        onStop: () => _stopAndAnnounce(c),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: _SlideUp(
                    anim: _modeCtrl,
                    child: CropPanel(
                      cropCenterX: cropCenterX,
                      onCropChanged: c.setVerticalCropCenter,
                      onRecenter: () => c.setVerticalCropCenter(0.5),
                      onDone: _toggleConfigure,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: BlurIconButton(
                    icon: Icons.grid_3x3,
                    active: _showGrid,
                    tooltip: 'Grade (rule of thirds)',
                    onPressed: _toggleGrid,
                  ),
                ),
                if (c.errorMessage != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 100,
                    child: Center(child: ErrorBubble(message: c.errorMessage!)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FadeHide extends StatelessWidget {
  const _FadeHide({required this.anim, required this.child});

  final Animation<double> anim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, inner) {
        final t = anim.value;
        return Opacity(
          opacity: 1.0 - t,
          child: IgnorePointer(ignoring: t > 0.5, child: inner),
        );
      },
      child: child,
    );
  }
}

class _SlideUp extends StatelessWidget {
  const _SlideUp({required this.anim, required this.child});

  final Animation<double> anim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, inner) {
        final t = anim.value;
        return IgnorePointer(
          ignoring: t < 0.5,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1.0 - t) * 24),
              child: inner,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
