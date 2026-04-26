import 'package:flutter/material.dart';

import '../../constants/crop.dart';
import '../../theme/app_theme.dart';
import 'test_pattern.dart';

class FullscreenPreview extends StatelessWidget {
  const FullscreenPreview({
    super.key,
    required this.textureId,
    required this.configure,
    required this.configureAnim,
    required this.cropCenterX,
    required this.onCropChanged,
    required this.showGrid,
  });

  final int? textureId;
  final bool configure;
  final Animation<double> configureAnim;
  final double cropCenterX;
  final ValueChanged<double> onCropChanged;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final cropW = w * kCropWidthRatio;
            final leftPx = cropCenterX * w - cropW / 2;
            final cropRect = Rect.fromLTWH(leftPx, 0, cropW, h);

            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                if (textureId != null && textureId! >= 0)
                  Texture(textureId: textureId!)
                else
                  const TestPattern(),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showGrid ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: const CustomPaint(painter: _RuleOfThirdsPainter()),
                  ),
                ),
                AnimatedBuilder(
                  animation: configureAnim,
                  builder: (context, child) {
                    final t = configureAnim.value;
                    if (t == 0) return const SizedBox.shrink();
                    return Opacity(opacity: t, child: child);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CropDimPainter(
                            cropRect: cropRect,
                            opacity: 0.42,
                          ),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: cropRect,
                        child: const IgnorePointer(child: _CropFrame()),
                      ),
                    ],
                  ),
                ),
                if (configure)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (d) {
                        final newRatio = (cropCenterX + d.delta.dx / w).clamp(
                          kHalfCropRatio,
                          1.0 - kHalfCropRatio,
                        );
                        onCropChanged(newRatio.toDouble());
                      },
                      onTapDown: (d) {
                        final ratio = (d.localPosition.dx / w).clamp(
                          kHalfCropRatio,
                          1.0 - kHalfCropRatio,
                        );
                        onCropChanged(ratio.toDouble());
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CropFrame extends StatelessWidget {
  const _CropFrame();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.edit.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
        ),
        const CustomPaint(painter: _CropCornersPainter()),
      ],
    );
  }
}

class _CropCornersPainter extends CustomPainter {
  const _CropCornersPainter();

  static const double _len = 18;
  static const double _w = 2.2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.edit
      ..strokeWidth = _w
      ..strokeCap = StrokeCap.round;
    final width = size.width;
    final height = size.height;
    canvas.drawLine(const Offset(0, 0), const Offset(_len, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, _len), paint);
    canvas.drawLine(Offset(width - _len, 0), Offset(width, 0), paint);
    canvas.drawLine(Offset(width, 0), Offset(width, _len), paint);
    canvas.drawLine(Offset(0, height), Offset(_len, height), paint);
    canvas.drawLine(Offset(0, height - _len), Offset(0, height), paint);
    canvas.drawLine(Offset(width - _len, height), Offset(width, height), paint);
    canvas.drawLine(Offset(width, height - _len), Offset(width, height), paint);
  }

  @override
  bool shouldRepaint(covariant _CropCornersPainter oldDelegate) => false;
}

class _RuleOfThirdsPainter extends CustomPainter {
  const _RuleOfThirdsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), paint);
    canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), paint);
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), paint);
    canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), paint);
  }

  @override
  bool shouldRepaint(covariant _RuleOfThirdsPainter oldDelegate) => false;
}

class _CropDimPainter extends CustomPainter {
  _CropDimPainter({required this.cropRect, required this.opacity});

  final Rect cropRect;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRect(cropRect);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _CropDimPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect || oldDelegate.opacity != opacity;
}
