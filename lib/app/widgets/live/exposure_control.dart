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
      height: 44,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tap(
            icon: Icons.remove,
            tooltip: 'Menos exposição',
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(1)}',
              textAlign: TextAlign.center,
              style: AppTheme.numeric(size: 11),
            ),
          ),
          _Tap(
            icon: Icons.add,
            tooltip: 'Mais exposição',
            onTap: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 16,
            color: onTap != null ? AppColors.text : AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}
