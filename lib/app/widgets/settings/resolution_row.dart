import 'package:flutter/material.dart';

import '../../models/resolution_profile.dart';
import '../../theme/app_theme.dart';

class ResolutionRow extends StatelessWidget {
  const ResolutionRow({super.key, required this.resolution});

  final CaptureResolution resolution;

  @override
  Widget build(BuildContext context) {
    final thermal = resolution.thermalHint;
    final thermalColor = switch (thermal) {
      ThermalHint.cool => AppColors.safe,
      ThermalHint.normal => AppColors.safe,
      ThermalHint.hot => AppColors.warn,
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
              resolution.label,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${resolution.width} × ${resolution.height}',
              style: const TextStyle(
                color: AppColors.textSubtle,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
            _Badge(label: thermal.label, color: thermalColor),
          ],
        ),
        subtitle: Text(
          resolution.summary,
          style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

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
