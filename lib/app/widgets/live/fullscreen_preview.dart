import 'package:flutter/material.dart';

import '../../constants/crop.dart';
import '../../theme/app_theme.dart';
import 'test_pattern.dart';

enum PreviewMode { hub, framing, recording }

class FullscreenPreview extends StatelessWidget {
  const FullscreenPreview({
    super.key,
    required this.textureId,
    required this.mode,
    required this.cropCenterX,
    required this.onCropChanged,
    required this.showGrid,
  });

  final int? textureId;
  final PreviewMode mode;
  final double cropCenterX;
  final ValueChanged<double> onCropChanged;
  final bool showGrid;

  static double clampCenter(double value) =>
      value.clamp(kHalfCropRatio, 1.0 - kHalfCropRatio).toDouble();

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
            final cropRect = Rect.fromLTWH(
              cropCenterX * w - cropW / 2,
              0,
              cropW,
              h,
            );
            final framing = mode == PreviewMode.framing;

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
                    child: const CustomPaint(painter: _RuleOfThirdsPainter()),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _GuidePainter(cropRect: cropRect, mode: mode),
                  ),
                ),
                if (mode == PreviewMode.hub)
                  Positioned(
                    top: 56,
                    left: cropRect.left + 8,
                    child: IgnorePointer(
                      child: Text(
                        '9:16',
                        style: AppTheme.label(color: AppColors.text),
                      ),
                    ),
                  ),
                if (framing)
                  Positioned.fromRect(
                    rect: cropRect,
                    child: const IgnorePointer(child: _DragHandle()),
                  ),
                if (framing)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (d) => onCropChanged(
                        clampCenter(cropCenterX + d.delta.dx / w),
                      ),
                      onTapDown: (d) =>
                          onCropChanged(clampCenter(d.localPosition.dx / w)),
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

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: AppColors.edit,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 14, color: AppColors.background),
            const SizedBox(width: 6),
            Text(
              'ARRASTE',
              style: AppTheme.label(
                color: AppColors.background,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.cropRect, required this.mode});

  final Rect cropRect;
  final PreviewMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case PreviewMode.hub:
        _dimSides(canvas, size, 0.35);
        final line = Paint()
          ..color = AppColors.text.withValues(alpha: 0.6)
          ..strokeWidth = 1;
        canvas.drawLine(cropRect.topLeft, cropRect.bottomLeft, line);
        canvas.drawLine(cropRect.topRight, cropRect.bottomRight, line);
      case PreviewMode.framing:
        _dimSides(canvas, size, 0.6);
        final thirds = Paint()
          ..color = AppColors.edit.withValues(alpha: 0.4)
          ..strokeWidth = 1;
        for (final f in const [1 / 3, 2 / 3]) {
          final x = cropRect.left + cropRect.width * f;
          canvas.drawLine(
            Offset(x, cropRect.top),
            Offset(x, cropRect.bottom),
            thirds,
          );
        }
        canvas.drawRect(
          cropRect.deflate(1),
          Paint()
            ..color = AppColors.edit
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      case PreviewMode.recording:
        final dash = Paint()
          ..color = AppColors.text.withValues(alpha: 0.4)
          ..strokeWidth = 1;
        _dashed(canvas, cropRect.left, cropRect.top, cropRect.bottom, dash);
        _dashed(canvas, cropRect.right, cropRect.top, cropRect.bottom, dash);
    }
  }

  void _dimSides(Canvas canvas, Size size, double opacity) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(cropRect);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );
  }

  void _dashed(Canvas canvas, double x, double top, double bottom, Paint p) {
    const dashLen = 4.0;
    for (var y = top; y < bottom; y += dashLen * 2) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + dashLen).clamp(top, bottom)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.cropRect != cropRect || oldDelegate.mode != mode;
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
