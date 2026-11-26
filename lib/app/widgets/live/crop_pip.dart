import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'test_pattern.dart';

class CropPip extends StatelessWidget {
  const CropPip({
    super.key,
    required this.textureId,
    required this.cropCenterX,
    this.width = 72,
    this.height = 128,
  });

  final int? textureId;
  final double cropCenterX;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scaledSrcW = height * 16 / 9;
    final offsetX = width / 2 - cropCenterX * scaledSrcW;
    return Semantics(
      label: 'Prévia 9:16',
      child: Container(
        width: width,
        height: height,
        color: AppColors.surface,
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: AppColors.text.withValues(alpha: 0.4)),
        ),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: offsetX,
                top: 0,
                width: scaledSrcW,
                height: height,
                child: textureId != null && textureId! >= 0
                    ? Texture(textureId: textureId!)
                    : const TestPattern(),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Text(
                  '9:16',
                  style: AppTheme.label(color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
