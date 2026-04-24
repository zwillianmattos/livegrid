import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class SeparatorDot extends StatelessWidget {
  const SeparatorDot({super.key, this.size = 2, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? AppColors.textFaint,
        shape: BoxShape.circle,
      ),
    );
  }
}
