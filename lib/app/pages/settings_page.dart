import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../models/resolution_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/settings/slider_row.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int _horizontalKbps;
  late int _verticalKbps;
  late int _fps;

  static const List<int> _fpsOptions = [24, 30, 60];

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile;
    _horizontalKbps = p.horizontal.bitrateBps ~/ 1000;
    _verticalKbps = p.vertical.bitrateBps ~/ 1000;
    _fps = p.horizontal.fps;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _qualityBody(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderRow(
          label: 'Horizontal',
          value: _horizontalKbps.toDouble(),
          min: 2000,
          max: 12000,
          divisions: 20,
          display: '${(_horizontalKbps / 1000).toStringAsFixed(1)} Mbps',
          onChanged: (v) => setState(() => _horizontalKbps = v.toInt()),
        ),
        const SizedBox(height: 28),
        SliderRow(
          label: 'Vertical',
          value: _verticalKbps.toDouble(),
          min: 2000,
          max: 10000,
          divisions: 16,
          display: '${(_verticalKbps / 1000).toStringAsFixed(1)} Mbps',
          onChanged: (v) => setState(() => _verticalKbps = v.toInt()),
        ),
        const SizedBox(height: 28),
        const Text(
          'FPS DA CÂMERA',
          style: TextStyle(
            color: AppColors.textFaint,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.hairline),
            ),
          ),
          child: Row(
            children: [
              for (final f in _fpsOptions)
                Expanded(
                  child: _FpsOption(
                    selected: f == _fps,
                    label: '$f',
                    onTap: () => setState(() => _fps = f),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _save() {
    final p = widget.controller.profile;
    widget.controller.updateProfile(
      p.copyWith(
        horizontal: p.horizontal.copyWith(
          bitrateBps: _horizontalKbps * 1000,
          fps: _fps,
          gop: _fps,
        ),
        vertical: p.vertical.copyWith(
          bitrateBps: _verticalKbps * 1000,
          fps: _fps,
          gop: _fps,
        ),
        mode: CaptureMode.recording,
      ),
    );
    Navigator.of(context).pop();
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onClose, required this.onSave});

  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
            tooltip: 'Fechar',
          ),
          const SizedBox(width: 4),
          const Text(
            'Configurações',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: onClose, child: const Text('CANCELAR')),
          const SizedBox(width: 8),
          FilledButton(onPressed: onSave, child: const Text('SALVAR')),
        ],
      ),
    );
  }
}

class _FpsOption extends StatelessWidget {
  const _FpsOption({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceHigh : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.text : AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
