import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class BlurIconButton extends StatelessWidget {
  const BlurIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
    this.size = 36,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: active
              ? AppColors.edit.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.38),
          shape: CircleBorder(
            side: BorderSide(
              color: active
                  ? AppColors.edit.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: tooltip,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  icon,
                  size: size * 0.5,
                  color: active ? Colors.black : AppColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
