import 'package:flutter/material.dart';

class TestPattern extends StatelessWidget {
  const TestPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _TestPatternPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _TestPatternPainter extends CustomPainter {
  const _TestPatternPainter();

  static const _labels = <(double, String)>[
    (0.1, '-40'),
    (0.3, '-20'),
    (0.5, '0'),
    (0.7, '+20'),
    (0.9, '+40'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xFF0F172A),
        Color(0xFF1E1B4B),
        Color(0xFF4C1D95),
        Color(0xFF831843),
        Color(0xFF7C2D12),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);

    final bandW = size.width / 10;
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(bandW * i, size.height * 0.78),
        Offset(bandW * i, size.height * 0.92),
        tick,
      );
    }
    final centerTick = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.1),
      Offset(size.width / 2, size.height * 0.9),
      centerTick,
    );

    for (final (xRatio, label) in _labels) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: size.height * 0.05,
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
          size.height * 0.42 - tp.height / 2,
        ),
      );
    }

    final label = TextPainter(
      text: TextSpan(
        text: 'LIVEGRID',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.18),
          fontSize: size.height * 0.1,
          fontWeight: FontWeight.w800,
          letterSpacing: size.height * 0.015,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(
        size.width / 2 - label.width / 2,
        size.height * 0.2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _TestPatternPainter oldDelegate) => false;
}
