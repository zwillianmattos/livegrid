import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'recording_hud.dart';

class SavedRecording {
  const SavedRecording({
    this.horizontalFile,
    this.verticalFile,
    this.duration,
    this.startedAt,
  });

  final String? horizontalFile;
  final String? verticalFile;
  final Duration? duration;
  final DateTime? startedAt;
}

class SavedReview extends StatelessWidget {
  const SavedReview({
    super.key,
    required this.recording,
    required this.onClose,
    required this.onShareVertical,
    required this.onOpenGallery,
  });

  final SavedRecording recording;
  final VoidCallback onClose;
  final ValueChanged<String> onShareVertical;
  final VoidCallback onOpenGallery;

  static const _months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  static String basename(String? path) {
    if (path == null) return '—';
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  static String? _size(String? path) {
    if (path == null) return null;
    try {
      final bytes = File(path).lengthSync();
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } catch (_) {
      return null;
    }
  }

  static String _fileLine(String? path) {
    final size = _size(path);
    final name = basename(path);
    return size == null ? name : '$name · $size';
  }

  String _subtitle() {
    final parts = <String>[];
    final d = recording.duration;
    if (d != null) parts.add(formatDuration(d));
    final t = recording.startedAt;
    if (t != null) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      parts.add('${t.day} ${_months[t.month - 1]}, $hh:$mm');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final vertical = recording.verticalFile;
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.safe,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SALVO NA GALERIA',
                    style: AppTheme.label(color: AppColors.safe),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.numeric(
                        color: AppColors.textMuted,
                        weight: FontWeight.w400,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: onClose,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const labelH = 24.0;
                    const gap = 16.0;
                    const buttonsMinW = 200.0;
                    final maxThumbW = constraints.maxWidth - buttonsMinW - gap;
                    var thumbH = (constraints.maxHeight - labelH).clamp(
                      0.0,
                      198.0,
                    );
                    final perH = 16 / 9 + 9 / 16;
                    if (thumbH * perH + gap > maxThumbW) {
                      thumbH = ((maxThumbW - gap) / perH).clamp(0.0, 198.0);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Thumb(
                          width: thumbH * 16 / 9,
                          height: thumbH,
                          tag: '16:9',
                          color: AppColors.surface,
                          caption: _fileLine(recording.horizontalFile),
                        ),
                        const SizedBox(width: gap),
                        _Thumb(
                          width: thumbH * 9 / 16,
                          height: thumbH,
                          tag: '9:16',
                          color: AppColors.surfaceHigh,
                          caption: _fileLine(vertical),
                        ),
                        const SizedBox(width: gap),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: labelH),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (vertical != null) ...[
                                  _OutlinedAction(
                                    label: 'COMPARTILHAR 9:16',
                                    onPressed: () => onShareVertical(vertical),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                _OutlinedAction(
                                  label: 'ABRIR GALERIA',
                                  onPressed: onOpenGallery,
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: onClose,
                                  child: const Text('NOVA GRAVAÇÃO'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.hairlineStrong),
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.width,
    required this.height,
    required this.tag,
    required this.color,
    required this.caption,
  });

  final double width;
  final double height;
  final String tag;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: AppColors.hairline),
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    Icons.play_arrow,
                    size: 28,
                    color: AppColors.text,
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Text(
                      tag,
                      style: AppTheme.label(color: AppColors.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
