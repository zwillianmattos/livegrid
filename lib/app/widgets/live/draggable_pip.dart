import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'test_pattern.dart';

class DraggablePip extends StatefulWidget {
  const DraggablePip({
    super.key,
    required this.textureId,
    required this.cropCenterX,
  });

  final int? textureId;
  final double cropCenterX;

  @override
  State<DraggablePip> createState() => _DraggablePipState();
}

class _DraggablePipState extends State<DraggablePip> {
  static const double _topInset = 64;
  static const double _bottomInset = 96;
  static const double _sideInset = 12;

  Offset? _pos;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final freeH = (constraints.maxHeight - _topInset - _bottomInset)
            .clamp(140.0, double.infinity);
        final pipH = freeH.clamp(160.0, 280.0).toDouble();
        final pipW = pipH * 9 / 16;

        final minX = _sideInset;
        final maxX = constraints.maxWidth - _sideInset - pipW;
        final minY = _topInset;
        final maxY = constraints.maxHeight - _bottomInset - pipH;

        final initial = Offset(minX, (minY + maxY) / 2);
        _pos ??= initial;
        final pos = Offset(
          _pos!.dx.clamp(minX, maxX),
          _pos!.dy.clamp(minY, maxY),
        );
        if (pos != _pos) _pos = pos;

        return Stack(
          children: [
            AnimatedPositioned(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy,
              width: pipW,
              height: pipH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (d) {
                  setState(() {
                    _pos = Offset(
                      (_pos!.dx + d.delta.dx).clamp(minX, maxX),
                      (_pos!.dy + d.delta.dy).clamp(minY, maxY),
                    );
                  });
                },
                onPanEnd: (_) => _snapToCorner(minX, maxX, minY, maxY),
                child: AnimatedScale(
                  scale: _dragging ? 1.03 : 1.0,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  child: _PipFrame(
                    textureId: widget.textureId,
                    cropCenterX: widget.cropCenterX,
                    elevated: _dragging,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _snapToCorner(double minX, double maxX, double minY, double maxY) {
    final corners = [
      Offset(minX, minY),
      Offset(maxX, minY),
      Offset(minX, maxY),
      Offset(maxX, maxY),
    ];
    var best = corners.first;
    var bestD = double.infinity;
    for (final c in corners) {
      final dist = (c - _pos!).distance;
      if (dist < bestD) {
        bestD = dist;
        best = c;
      }
    }
    setState(() {
      _pos = best;
      _dragging = false;
    });
  }
}

class _PipFrame extends StatelessWidget {
  const _PipFrame({
    required this.textureId,
    required this.cropCenterX,
    this.elevated = false,
  });

  final int? textureId;
  final double cropCenterX;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: elevated ? 0.6 : 0.45),
            blurRadius: elevated ? 36 : 24,
            offset: Offset(0, elevated ? 14 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    final w = constraints.maxWidth;
                    final scaledSrcW = h * 16 / 9;
                    final offsetX = w / 2 - cropCenterX * scaledSrcW;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.black),
                        Positioned(
                          left: offsetX,
                          top: 0,
                          width: scaledSrcW,
                          height: h,
                          child: textureId != null && textureId! >= 0
                              ? Texture(textureId: textureId!)
                              : const TestPattern(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Positioned(top: 8, left: 8, child: _PipLabel()),
          ],
        ),
      ),
    );
  }
}

class _PipLabel extends StatelessWidget {
  const _PipLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.text,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text('9:16', style: AppTheme.label(size: 9)),
        ],
      ),
    );
  }
}
