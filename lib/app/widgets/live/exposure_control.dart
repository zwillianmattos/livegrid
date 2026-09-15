import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../atoms/blur_pill.dart';

class ExposureControl extends StatelessWidget {
  const ExposureControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.stepEv,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final double stepEv;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ev = value * stepEv;
    return BlurPill(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tap(
            icon: Icons.remove,
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(1)}',
              textAlign: TextAlign.center,
              style: AppTheme.numeric(size: 11, color: AppColors.text),
            ),
          ),
          _Tap(
            icon: Icons.add,
            onTap: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.text : AppColors.textFaint,
        ),
      ),
    );
  }
}
