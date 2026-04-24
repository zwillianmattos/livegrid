import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../models/network_profile.dart';
import '../models/session_state.dart';
import '../models/stream_stats.dart';
import '../models/thermal_status.dart';
import 'settings_page.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
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

  void _onControllerChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PreviewLayer(textureId: c.textureId),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _TopBar(
                state: c.state,
                stats: c.stats,
                wifiBand: c.wifiBand,
                onSettings: () => _openSettings(context),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _BottomControls(
                state: c.state,
                error: c.errorMessage,
                onStart: c.start,
                onStop: c.stop,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsPage(controller: widget.controller),
    ));
  }
}

class _PreviewLayer extends StatelessWidget {
  const _PreviewLayer({required this.textureId});

  final int? textureId;

  @override
  Widget build(BuildContext context) {
    if (textureId == null || textureId! < 0) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: Colors.white24, size: 48),
              SizedBox(height: 12),
              Text(
                'Preview indisponível (câmera não inicializada)',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Texture(textureId: textureId!),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.stats,
    required this.wifiBand,
    required this.onSettings,
  });

  final SessionState state;
  final StreamStats stats;
  final WifiBand wifiBand;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StateBadge(state: state),
        const SizedBox(width: 8),
        if (wifiBand == WifiBand.band24GHz) const _Wifi24Warning(),
        _StatsPill(stats: stats),
        const Spacer(),
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.settings, color: Colors.white),
        ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      SessionState.idle => (Colors.grey, 'IDLE'),
      SessionState.starting => (Colors.orange, 'STARTING'),
      SessionState.live => (Colors.red, 'LIVE'),
      SessionState.degraded => (Colors.amber, 'DEGRADED'),
      SessionState.stopping => (Colors.orange, 'STOPPING'),
      SessionState.error => (Colors.redAccent, 'ERROR'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Wifi24Warning extends StatelessWidget {
  const _Wifi24Warning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi, size: 14, color: Colors.black87),
          SizedBox(width: 4),
          Text(
            'Wi-Fi 2.4 GHz',
            style: TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.state,
    required this.error,
    required this.onStart,
    required this.onStop,
  });

  final SessionState state;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) _ErrorBanner(message: error!),
        if (error != null) const SizedBox(height: 8),
        const SizedBox(height: 16),
        _RecordButton(state: state, onStart: onStart, onStop: onStop),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _StatsPill extends StatelessWidget {
  const _StatsPill({required this.stats});

  final StreamStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatChip(label: 'H', value: _kbps(stats.bitrateABps)),
          _StatChip(label: 'V', value: _kbps(stats.bitrateBBps)),
          _StatChip(label: 'FPS', value: stats.fps.toStringAsFixed(0)),
          _StatChip(label: 'RTT', value: stats.srtRttMs.toStringAsFixed(0)),
          _ThermalChip(status: stats.thermalStatus),
        ],
      ),
    );
  }

  static String _kbps(int bps) {
    if (bps <= 0) return '—';
    return '${(bps / 1000).toStringAsFixed(0)}k';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(color: Colors.white38),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThermalChip extends StatelessWidget {
  const _ThermalChip({required this.status});

  final ThermalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ThermalStatus.none || ThermalStatus.light => Colors.greenAccent,
      ThermalStatus.moderate => Colors.amber,
      ThermalStatus.severe => Colors.orange,
      ThermalStatus.critical ||
      ThermalStatus.emergency ||
      ThermalStatus.shutdown =>
        Colors.redAccent,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final SessionState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final busy =
        state == SessionState.starting || state == SessionState.stopping;
    final live =
        state == SessionState.live || state == SessionState.degraded;

    return GestureDetector(
      onTap: busy ? null : (live ? onStop : onStart),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: live ? 28 : 56,
          height: live ? 28 : 56,
          decoration: BoxDecoration(
            color: busy ? Colors.white38 : Colors.red,
            borderRadius: BorderRadius.circular(live ? 6 : 999),
          ),
        ),
      ),
    );
  }
}
