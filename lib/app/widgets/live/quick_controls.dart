import 'package:flutter/material.dart';

import '../../models/camera_info.dart';
import '../../models/resolution_profile.dart';
import '../../theme/app_theme.dart';
import '../atoms/blur_pill.dart';

class QuickControls extends StatelessWidget {
  const QuickControls({
    super.key,
    required this.cameras,
    required this.selectedCamera,
    required this.resolution,
    required this.onCameraTap,
    required this.onResolutionTap,
  });

  final List<CameraInfo> cameras;
  final CameraInfo? selectedCamera;
  final CaptureResolution resolution;
  final VoidCallback onCameraTap;
  final VoidCallback onResolutionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cameras.length > 1) ...[
          _Chip(
            icon: Icons.cameraswitch_outlined,
            label: _lensLabel(selectedCamera),
            onTap: onCameraTap,
          ),
          const SizedBox(width: 8),
        ],
        _Chip(
          icon: Icons.aspect_ratio,
          label: resolution.label,
          onTap: onResolutionTap,
        ),
      ],
    );
  }

  static String _lensLabel(CameraInfo? cam) {
    if (cam == null) return '—';
    return switch (cam.lens) {
      CameraLens.back => 'Traseira',
      CameraLens.front => 'Frontal',
      CameraLens.external => 'Externa',
      CameraLens.unknown => 'Câmera',
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: BlurPill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.text),
            const SizedBox(width: 6),
            Text(label, style: AppTheme.label(size: 11, color: AppColors.text)),
          ],
        ),
      ),
    );
  }
}
