import 'package:flutter/material.dart';

import '../../models/resolution_profile.dart';
import '../../theme/app_theme.dart';

class ResolutionRow extends StatelessWidget {
  const ResolutionRow({super.key, required this.resolution});

  final CaptureResolution resolution;

  @override
  Widget build(BuildContext context) {
    final q = resolution.verticalQuality;
    final cropW = resolution.verticalCropWidth;
    final cropH = resolution.verticalCropHeight;
    final qColor = switch (q) {
      VerticalQuality.pristine => AppColors.safe,
      VerticalQuality.fullHd => AppColors.safe,
      VerticalQuality.reduced => AppColors.warn,
      VerticalQuality.sub => AppColors.live,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RadioListTile<CaptureResolution>(
        value: resolution,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Row(
          children: [
            Text(
              '${resolution.width} × ${resolution.height}',
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            _QualityBadge(label: q.label, color: qColor),
          ],
        ),
        subtitle: Text(
          'Vertical: $cropW × $cropH · ${q.description}',
          style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
        ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
