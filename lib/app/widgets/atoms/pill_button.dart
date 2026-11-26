import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.accent,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final fg = onPressed == null
        ? AppColors.textFaint
        : (accent ?? AppColors.text);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: accent == null
                ? const RoundedRectangleBorder()
                : RoundedRectangleBorder(side: BorderSide(color: fg)),
            child: InkWell(
              onTap: onPressed,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
