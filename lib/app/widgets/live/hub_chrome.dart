import 'package:flutter/material.dart';

import '../../models/stream_stats.dart';
import '../../theme/app_theme.dart';
import '../atoms/blur_pill.dart';
import '../atoms/status_dot.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.squareDot = false,
  });

  final String label;
  final Color color;
  final bool squareDot;

  @override
  Widget build(BuildContext context) {
    return BlurPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (squareDot)
            Container(width: 8, height: 8, color: color)
          else
            StatusDot(color: color, size: 8),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.label(color: squareDot ? color : AppColors.text),
          ),
        ],
      ),
    );
  }
}

class FormatPill extends StatelessWidget {
  const FormatPill({super.key, required this.parts, required this.onTap});

  final List<String> parts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppColors.textFaint,
          ),
        );
      }
      children.add(Text(parts[i], style: AppTheme.numeric(size: 11)));
    }
    return Semantics(
      button: true,
      label: 'Formato de saída ${parts.join(', ')}, tocar para ajustar',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: BlurPill(
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

class ExternalMicPill extends StatelessWidget {
  const ExternalMicPill({super.key, required this.type});

  final AudioInputType type;

  @override
  Widget build(BuildContext context) {
    final tag = type == AudioInputType.usb ? 'USB' : 'FIO';
    return Semantics(
      label: 'Microfone externo $tag conectado',
      excludeSemantics: true,
      child: BlurPill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, size: 14, color: AppColors.safe),
            const SizedBox(width: 6),
            Text(
              tag,
              maxLines: 1,
              style: AppTheme.label(color: AppColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class LastRecordingThumb extends StatelessWidget {
  const LastRecordingThumb({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Última gravação',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Última gravação',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 56,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              border: Border.all(color: AppColors.hairlineStrong),
            ),
            child: Row(
              children: [
                Expanded(child: Container(color: AppColors.surfaceHigh)),
                const SizedBox(width: 3),
                Container(width: 12, color: AppColors.surface),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
