import 'package:flutter/material.dart';

import '../../models/network_profile.dart';
import '../../models/session_state.dart';
import '../../models/stream_stats.dart';
import '../../models/thermal_status.dart';
import '../../theme/app_theme.dart';
import '../atoms/blur_icon_button.dart';
import '../atoms/blur_pill.dart';
import '../atoms/separator_dot.dart';
import '../atoms/status_dot.dart';

class TopChrome extends StatelessWidget {
  const TopChrome({
    super.key,
    required this.state,
    required this.stats,
    required this.wifiBand,
    required this.liveStartedAt,
    required this.configure,
    required this.onConfigure,
    required this.onSettings,
  });

  final SessionState state;
  final StreamStats stats;
  final WifiBand wifiBand;
  final DateTime? liveStartedAt;
  final bool configure;
  final VoidCallback onConfigure;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusPill(state: state, liveStartedAt: liveStartedAt),
        const Spacer(),
        if (!configure) _StatsPill(stats: stats, wifiBand: wifiBand),
        if (configure) const _ConfigureTitle(),
        const SizedBox(width: 8),
        BlurIconButton(
          icon: configure ? Icons.check : Icons.tune,
          active: configure,
          tooltip: configure ? 'Concluir' : 'Ajustar crop',
          onPressed: onConfigure,
        ),
        const SizedBox(width: 8),
        BlurIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Configurações',
          onPressed: onSettings,
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.liveStartedAt});

  final SessionState state;
  final DateTime? liveStartedAt;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      SessionState.idle => (AppColors.textSubtle, 'PRONTO'),
      SessionState.starting => (AppColors.warn, 'INICIANDO'),
      SessionState.live => (AppColors.live, 'AO VIVO'),
      SessionState.degraded => (AppColors.warn, 'DEGRADADO'),
      SessionState.stopping => (AppColors.warn, 'PARANDO'),
      SessionState.error => (AppColors.live, 'ERRO'),
    };
    final pulsing = state == SessionState.live;
    return BlurPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: color, pulsing: pulsing),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.label(size: 11, color: AppColors.text),
          ),
          if (liveStartedAt != null) ...[
            const SizedBox(width: 10),
            const SeparatorDot(),
            const SizedBox(width: 10),
            Text(
              _formatDuration(DateTime.now().difference(liveStartedAt!)),
              style: AppTheme.numeric(
                size: 12,
                color: AppColors.text,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${_two(h)}:${_two(m)}:${_two(s)}';
    return '${_two(m)}:${_two(s)}';
  }
}

class _StatsPill extends StatelessWidget {
  const _StatsPill({required this.stats, required this.wifiBand});

  final StreamStats stats;
  final WifiBand wifiBand;

  @override
  Widget build(BuildContext context) {
    return BlurPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatCell(label: 'H', value: _mbps(stats.bitrateABps)),
          const SizedBox(width: 16),
          _StatCell(label: 'V', value: _mbps(stats.bitrateBBps)),
          const SizedBox(width: 16),
          _StatCell(label: 'FPS', value: stats.fps.toStringAsFixed(0)),
          const SizedBox(width: 16),
          _ThermalCell(status: stats.thermalStatus),
          if (wifiBand == WifiBand.band24GHz) ...[
            const SizedBox(width: 14),
            const SeparatorDot(),
            const SizedBox(width: 14),
            const Icon(Icons.wifi, size: 12, color: AppColors.warn),
            const SizedBox(width: 4),
            Text(
              '2.4G',
              style: AppTheme.numeric(
                size: 11,
                color: AppColors.warn,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _mbps(int bps) {
    if (bps <= 0) return '—';
    final m = bps / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTheme.label(size: 10, color: AppColors.textFaint),
        ),
        const SizedBox(width: 5),
        Text(value, style: AppTheme.numeric(size: 12)),
      ],
    );
  }
}

class _ThermalCell extends StatelessWidget {
  const _ThermalCell({required this.status});

  final ThermalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ThermalStatus.none || ThermalStatus.light => AppColors.safe,
      ThermalStatus.moderate => AppColors.warn,
      ThermalStatus.severe => AppColors.warn,
      ThermalStatus.critical ||
      ThermalStatus.emergency ||
      ThermalStatus.shutdown =>
        AppColors.live,
    };
    return StatusDot(color: color);
  }
}

class _ConfigureTitle extends StatelessWidget {
  const _ConfigureTitle();

  @override
  Widget build(BuildContext context) {
    return BlurPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.crop_portrait, size: 13, color: AppColors.edit),
          const SizedBox(width: 8),
          Text(
            'AJUSTAR CROP 9:16',
            style: AppTheme.label(size: 11, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
