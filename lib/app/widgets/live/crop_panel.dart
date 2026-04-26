import 'dart:ui';

import 'package:flutter/material.dart';

import '../../constants/crop.dart';
import '../../theme/app_theme.dart';

class CropPanel extends StatelessWidget {
  const CropPanel({
    super.key,
    required this.cropCenterX,
    required this.onCropChanged,
    required this.onRecenter,
    required this.onDone,
  });

  final double cropCenterX;
  final ValueChanged<double> onCropChanged;
  final VoidCallback onRecenter;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final centered = (cropCenterX - 0.5).abs() < 0.002;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    _OffsetLabel(cropCenterX: cropCenterX),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.edit,
                          thumbColor: AppColors.edit,
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: cropCenterX.clamp(
                            kHalfCropRatio,
                            1.0 - kHalfCropRatio,
                          ),
                          min: kHalfCropRatio,
                          max: 1.0 - kHalfCropRatio,
                          onChanged: onCropChanged,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _PanelAction(
                      icon: Icons.center_focus_strong,
                      tooltip: 'Centralizar',
                      onPressed: centered ? null : onRecenter,
                    ),
                    const SizedBox(width: 4),
                    _PanelAction(
                      icon: Icons.check,
                      tooltip: 'Concluir',
                      primary: true,
                      onPressed: onDone,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OffsetLabel extends StatelessWidget {
  const _OffsetLabel({required this.cropCenterX});

  final double cropCenterX;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _centerLabel(cropCenterX),
          style: AppTheme.numeric(
            size: 11,
            color: AppColors.textSubtle,
            weight: FontWeight.w500,
          ),
        ),
        Text(
          _percentLabel(cropCenterX),
          style: AppTheme.numeric(
            size: 20,
            color: AppColors.text,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static String _centerLabel(double x) {
    if ((x - 0.5).abs() < 0.002) return 'CENTRO';
    return x > 0.5 ? 'OFFSET DIREITA' : 'OFFSET ESQUERDA';
  }

  static String _percentLabel(double x) {
    final pct = ((x - 0.5) * 200).round();
    if (pct == 0) return '0%';
    return pct > 0 ? '+$pct%' : '$pct%';
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary
            ? AppColors.text
            : Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 16,
              color: primary
                  ? Colors.black
                  : enabled
                  ? AppColors.text
                  : AppColors.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}
