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
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: active
                  ? AppColors.edit
                  : Colors.black.withValues(alpha: 0.45),
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    icon,
                    size: 18,
                    color: active ? AppColors.background : AppColors.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
