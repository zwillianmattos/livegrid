import 'package:flutter/material.dart';

class RightRail extends StatelessWidget {
  const RightRail({
    super.key,
    required this.top,
    required this.center,
    required this.bottom,
    this.background = const Color(0xB3041B15),
  });

  static const double width = 96;

  final List<Widget> top;
  final Widget center;
  final List<Widget> bottom;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Container(
      width: width + pad.right,
      color: background,
      padding: EdgeInsets.only(
        right: pad.right,
        top: pad.top + 16,
        bottom: pad.bottom + 16,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: _Column(children: top),
          ),
          center,
          Align(
            alignment: Alignment.bottomCenter,
            child: _Column(children: bottom),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 8));
      spaced.add(children[i]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: spaced);
  }
}
