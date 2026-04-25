import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class TestPattern extends StatelessWidget {
  const TestPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.background,
            AppColors.surface,
            AppColors.surfaceHigh,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _TicksPainter()),
          Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Opacity(
                opacity: 0.55,
                child: Image(
                  image: AssetImage('assets/images/logo.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  const _TicksPainter();

  static const _labels = <(double, String)>[
    (0.1, '-40'),
    (0.3, '-20'),
    (0.5, '0'),
    (0.7, '+20'),
    (0.9, '+40'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    final bandW = size.width / 10;
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(bandW * i, size.height * 0.82),
        Offset(bandW * i, size.height * 0.92),
        tick,
      );
    }
    final centerTick = Paint()
      ..color = AppColors.hairlineStrong
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.78),
      Offset(size.width / 2, size.height * 0.94),
      centerTick,
    );

    for (final (xRatio, label) in _labels) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: AppColors.textFaint,
            fontSize: size.height * 0.045,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          size.width * xRatio - tp.width / 2,
          size.height * 0.74 - tp.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TicksPainter oldDelegate) => false;
}
