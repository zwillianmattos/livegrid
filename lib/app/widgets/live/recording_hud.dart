import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stream_stats.dart';
import '../../theme/app_theme.dart';
import '../atoms/blur_pill.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class RecTimerPill extends StatefulWidget {
  const RecTimerPill({super.key, required this.startedAt});

  final DateTime? startedAt;

  @override
  State<RecTimerPill> createState() => _RecTimerPillState();
}

class _RecTimerPillState extends State<RecTimerPill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAt;
    final elapsed = start == null
        ? Duration.zero
        : DateTime.now().difference(start);
    final text = formatDuration(elapsed);
    return Semantics(
      label: 'Gravando, $text',
      excludeSemantics: true,
      child: BlurPill(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        background: Colors.black.withValues(alpha: 0.55),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.live,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'REC',
              style: AppTheme.label(
                color: AppColors.live,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            Text(text, style: AppTheme.numeric(size: 16)),
          ],
        ),
      ),
    );
  }
}

class MicLevelPill extends StatelessWidget {
  const MicLevelPill({
    super.key,
    required this.level,
    required this.inputType,
    this.inputName = '',
  });

  final double level;
  final AudioInputType inputType;
  final String inputName;

  static const _heights = [4.0, 7.0, 10.0, 12.0, 12.0, 12.0];
  static const _maxNameChars = 14;

  static String shortName(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= _maxNameChars) return trimmed;
    return '${trimmed.substring(0, _maxNameChars - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: inputType == AudioInputType.none ? _muted() : _meter(),
    );
  }

  Widget _muted() {
    return Semantics(
      label: 'Sem áudio, gravação muda',
      excludeSemantics: true,
      child: BlurPill(
        background: Colors.black.withValues(alpha: 0.55),
        borderColor: AppColors.warn,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_off, size: 14, color: AppColors.warn),
            const SizedBox(width: 8),
            Text(
              'SEM ÁUDIO',
              maxLines: 1,
              style: AppTheme.label(color: AppColors.warn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meter() {
    final clamped = level.clamp(0.0, 1.0);
    final lit = (clamped * _heights.length * 2).ceil().clamp(
      0,
      _heights.length,
    );
    final tag = switch (inputType) {
      AudioInputType.builtin => 'INTERNO',
      AudioInputType.usb => 'USB',
      AudioInputType.wired => 'FIO',
      AudioInputType.bluetooth => 'BT',
      AudioInputType.none => '',
    };
    final name = inputType == AudioInputType.builtin
        ? ''
        : shortName(inputName);
    return Semantics(
      label: 'Nível do microfone, $tag${name.isEmpty ? '' : ' $name'}',
      value: '${(clamped * 100).round()}%',
      excludeSemantics: true,
      child: BlurPill(
        background: Colors.black.withValues(alpha: 0.55),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_none, size: 14, color: AppColors.text),
            const SizedBox(width: 8),
            for (var i = 0; i < _heights.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 3,
                height: i < lit ? _heights[i] : 12,
                color: i < lit ? AppColors.safe : AppColors.textFaint,
              ),
            ],
            const SizedBox(width: 8),
            Text(
              tag,
              maxLines: 1,
              style: AppTheme.label(color: AppColors.text),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTheme.numeric(size: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ThermalPill extends StatelessWidget {
  const ThermalPill({super.key, required this.fps});

  final int fps;

  @override
  Widget build(BuildContext context) {
    return BlurPill(
      background: Colors.black.withValues(alpha: 0.55),
      borderColor: AppColors.warn,
      child: Text(
        'AQUECENDO · $fps FPS',
        style: AppTheme.label(color: AppColors.warn),
      ),
    );
  }
}

class BitrateChip extends StatelessWidget {
  const BitrateChip({super.key, required this.label, required this.bps});

  final String label;
  final int bps;

  @override
  Widget build(BuildContext context) {
    return BlurPill(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      background: Colors.black.withValues(alpha: 0.55),
      child: Text(
        '$label ${(bps / 1e6).toStringAsFixed(1)} Mbps',
        style: AppTheme.numeric(size: 11, color: AppColors.textMuted),
      ),
    );
  }
}
