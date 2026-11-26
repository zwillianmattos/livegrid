import 'dart:ui';

import 'package:flutter/material.dart';

class BlurPill extends StatelessWidget {
  const BlurPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.height = 32,
    this.background,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? height;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: height,
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background ?? Colors.black.withValues(alpha: 0.45),
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
