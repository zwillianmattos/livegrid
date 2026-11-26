import 'package:flutter/material.dart';

import '../../constants/crop.dart';
import '../../theme/app_theme.dart';

class CropPanel extends StatelessWidget {
  const CropPanel({
    super.key,
    required this.cropCenterX,
    required this.onCropChanged,
    required this.onRecenter,
    required this.onDone,
  });

  final double cropCenterX;
  final ValueChanged<double> onCropChanged;
  final VoidCallback onRecenter;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final percent = (cropCenterX * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.85),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Text('CENTRO', style: AppTheme.label(color: AppColors.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: cropCenterX,
              min: kHalfCropRatio,
              max: 1.0 - kHalfCropRatio,
              semanticFormatterCallback: (v) => '${(v * 100).round()}%',
              onChanged: onCropChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: AppTheme.numeric(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onRecenter,
            child: const Text('CENTRALIZAR'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: onDone,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
