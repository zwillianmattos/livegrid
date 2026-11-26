import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../models/resolution_profile.dart';
import '../../theme/app_theme.dart';
import '../settings/slider_row.dart';

const double _kSheetWidth = 480;

Future<void> showQualitySheet(
  BuildContext context,
  SessionController controller,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar qualidade',
    barrierColor: const Color(0x73000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => QualitySheet(controller: controller),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.25, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class QualitySheet extends StatefulWidget {
  const QualitySheet({super.key, required this.controller});

  final SessionController controller;

  @override
  State<QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<QualitySheet> {
  late final CaptureResolution _initialTier;
  late final int _initialHorizontalKbps;
  late final int _initialVerticalKbps;
  late CaptureResolution _tier;
  late int _horizontalKbps;
  late int _verticalKbps;
  late int _fps;
  bool _bitrateTouched = false;
  bool _advancedOpen = false;
  bool _saving = false;

  static const List<(int, String)> _fpsOptions = [
    (24, 'Cinema'),
    (30, 'Stories / Reels'),
    (60, 'Fluido'),
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile;
    _initialTier = p.capture;
    _tier = p.capture;
    _initialHorizontalKbps = p.horizontal.bitrateBps ~/ 1000;
    _initialVerticalKbps = p.vertical.bitrateBps ~/ 1000;
    _horizontalKbps = _initialHorizontalKbps;
    _verticalKbps = _initialVerticalKbps;
    _fps = p.horizontal.fps;
  }

  void _selectTier(CaptureResolution tier) {
    setState(() {
      _tier = tier;
      if (_bitrateTouched) return;
      if (tier == _initialTier) {
        _horizontalKbps = _initialHorizontalKbps;
        _verticalKbps = _initialVerticalKbps;
      } else {
        _horizontalKbps = tier.defaultHorizontalEncoder.bitrateBps ~/ 1000;
        _verticalKbps = tier.defaultVerticalEncoder.bitrateBps ~/ 1000;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final controller = widget.controller;
    if (_tier != controller.profile.capture) {
      await controller.switchCapture(_tier);
    }
    final p = controller.profile;
    final hBps = _horizontalKbps.clamp(2000, kHorizontalMaxKbps) * 1000;
    final vBps = _verticalKbps.clamp(2000, kVerticalMaxKbps) * 1000;
    await controller.updateProfile(
      p.copyWith(
        horizontal: p.horizontal.copyWith(
          bitrateBps: hBps,
          fps: _fps,
          gop: _fps,
        ),
        vertical: p.vertical.copyWith(bitrateBps: vBps, fps: _fps, gop: _fps),
        mode: CaptureMode.recording,
      ),
    );
    if (controller.isLive) {
      await controller.stop();
      await controller.start();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(_kSheetWidth, MediaQuery.sizeOf(context).width);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Material(
          color: AppColors.surface,
          shape: const Border(left: BorderSide(color: AppColors.hairline)),
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _Header(
                    onCancel: () => Navigator.of(context).pop(),
                    onSave: _save,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: _body(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final h = _tier.defaultHorizontalEncoder;
    final v = _tier.defaultVerticalEncoder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('NITIDEZ DO 9:16', style: _sectionLabel),
        const SizedBox(height: 6),
        _Segmented(
          children: [
            _SegmentOption(
              key: const ValueKey('tier-balanced'),
              title: 'PADRÃO',
              subtitle: 'Sensor 1080p · esquenta menos',
              selected: _tier == CaptureResolution.balanced,
              onTap: () => _selectTier(CaptureResolution.balanced),
            ),
            _SegmentOption(
              key: const ValueKey('tier-quality'),
              title: 'ALTA',
              subtitle: 'Sensor 4K · esquenta mais',
              selected: _tier == CaptureResolution.quality,
              onTap: () => _selectTier(CaptureResolution.quality),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Arquivos: 16:9 ${h.width}×${h.height} + 9:16 ${v.width}×${v.height}',
          style: AppTheme.numeric(
            size: 12,
            color: AppColors.textMuted,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 14),
        Text('FPS', style: _sectionLabel),
        const SizedBox(height: 6),
        _Segmented(
          children: [
            for (final (fps, caption) in _fpsOptions)
              _SegmentOption(
                key: ValueKey('fps-$fps'),
                title: '$fps',
                subtitle: caption,
                numericTitle: true,
                selected: _fps == fps,
                onTap: () => setState(() => _fps = fps),
              ),
          ],
        ),
        if (_fps == 24) ...[
          const SizedBox(height: 6),
          const Text(
            '24 pode piscar com luz artificial. Em ambiente interno use 30.',
            style: TextStyle(color: AppColors.warn, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        _advanced(),
      ],
    );
  }

  Widget _advanced() {
    final hText = (_horizontalKbps / 1000).toStringAsFixed(1);
    final vText = (_verticalKbps / 1000).toStringAsFixed(1);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('bitrate-toggle'),
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'BITRATE · AVANÇADO',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sectionLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'H $hText · V $vText Mbps',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppTheme.numeric(size: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _advancedOpen ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_advancedOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SliderRow(
                      key: const ValueKey('slider-horizontal'),
                      label: 'HORIZONTAL 16:9',
                      value: _horizontalKbps
                          .clamp(2000, kHorizontalMaxKbps)
                          .toDouble(),
                      min: 2000,
                      max: kHorizontalMaxKbps.toDouble(),
                      divisions: (kHorizontalMaxKbps - 2000) ~/ 1000,
                      display: '$hText Mbps',
                      onChanged: (v) => setState(() {
                        _bitrateTouched = true;
                        _horizontalKbps = v.toInt();
                      }),
                    ),
                    const SizedBox(height: 8),
                    SliderRow(
                      key: const ValueKey('slider-vertical'),
                      label: 'VERTICAL 9:16',
                      value: _verticalKbps
                          .clamp(2000, kVerticalMaxKbps)
                          .toDouble(),
                      min: 2000,
                      max: kVerticalMaxKbps.toDouble(),
                      divisions: (kVerticalMaxKbps - 2000) ~/ 1000,
                      display: '$vText Mbps',
                      onChanged: (v) => setState(() {
                        _bitrateTouched = true;
                        _verticalKbps = v.toInt();
                      }),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final TextStyle _sectionLabel = AppTheme.label(color: AppColors.textMuted);

class _Header extends StatelessWidget {
  const _Header({required this.onCancel, required this.onSave});

  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const Text(
            'Qualidade',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: onCancel, child: const Text('CANCELAR')),
          const SizedBox(width: 8),
          FilledButton(onPressed: onSave, child: const Text('SALVAR')),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final c in children) Expanded(child: c)],
        ),
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.numericTitle = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool numericTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = selected ? AppColors.text : AppColors.textMuted;
    final titleStyle = numericTitle
        ? AppTheme.numeric(size: 11, color: titleColor)
        : TextStyle(
            color: titleColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          );
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          color: selected ? AppColors.surfaceHigh : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
