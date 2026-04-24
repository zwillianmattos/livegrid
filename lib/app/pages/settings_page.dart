import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../models/camera_info.dart';
import '../models/resolution_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms/section_card.dart';
import '../widgets/settings/resolution_row.dart';
import '../widgets/settings/slider_row.dart';
import '../widgets/settings/url_preview.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late CaptureResolution _capture;
  late int _horizontalKbps;
  late int _verticalKbps;
  late int _srtLatency;
  late TextEditingController _obsHostCtrl;
  late TextEditingController _hPortCtrl;
  late TextEditingController _vPortCtrl;
  String? _cameraId;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile;
    final n = widget.controller.network;
    _capture = p.capture;
    _horizontalKbps = p.horizontal.bitrateBps ~/ 1000;
    _verticalKbps = p.vertical.bitrateBps ~/ 1000;
    _srtLatency = n.srtLatencyMs;
    _obsHostCtrl = TextEditingController(text: n.obsHost);
    _hPortCtrl = TextEditingController(text: '${n.horizontalPort}');
    _vPortCtrl = TextEditingController(text: '${n.verticalPort}');
    _cameraId = p.cameraId ?? widget.controller.selectedCamera?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCameras());
  }

  @override
  void dispose() {
    _obsHostCtrl.dispose();
    _hPortCtrl.dispose();
    _vPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureCameras() async {
    if (widget.controller.cameras.isEmpty) {
      await widget.controller.refreshCameras();
      if (!mounted) return;
      setState(() {
        _cameraId ??= widget.controller.selectedCamera?.id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            const Divider(height: 1, color: AppColors.hairline),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 720;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: wide ? _wideLayout() : _narrowLayout(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cameraCard(),
              const SizedBox(height: 16),
              _captureCard(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _networkCard(),
              const SizedBox(height: 16),
              _qualityCard(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cameraCard(),
        const SizedBox(height: 16),
        _captureCard(),
        const SizedBox(height: 16),
        _networkCard(),
        const SizedBox(height: 16),
        _qualityCard(),
      ],
    );
  }

  Widget _cameraCard() {
    final cameras = widget.controller.cameras;
    return SectionCard(
      title: 'CÂMERA',
      children: [
        if (cameras.isEmpty)
          const _EmptyRow(
            icon: Icons.videocam_off,
            message: 'Nenhuma câmera encontrada',
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _cameraIdOrDefault(cameras),
            dropdownColor: AppColors.surfaceHigh,
            icon: const Icon(Icons.expand_more, color: AppColors.textMuted),
            decoration: const InputDecoration(labelText: 'Dispositivo'),
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            items: [
              for (final cam in cameras)
                DropdownMenuItem(
                  value: cam.id,
                  child: Text(_cameraLabel(cam)),
                ),
            ],
            onChanged: (v) => setState(() => _cameraId = v),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              await widget.controller.refreshCameras();
              if (!mounted) return;
              setState(() {});
            },
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Atualizar lista'),
          ),
        ),
      ],
    );
  }

  Widget _captureCard() {
    return SectionCard(
      title: 'CAPTURA',
      children: [
        RadioGroup<CaptureResolution>(
          groupValue: _capture,
          onChanged: (v) {
            if (v != null) setState(() => _capture = v);
          },
          child: Column(
            children: [
              for (final r in CaptureResolution.values)
                ResolutionRow(resolution: r),
            ],
          ),
        ),
      ],
    );
  }

  Widget _networkCard() {
    return SectionCard(
      title: 'REDE',
      children: [
        TextField(
          controller: _obsHostCtrl,
          decoration: const InputDecoration(
            labelText: 'Host OBS',
            hintText: '192.168.1.50',
          ),
          keyboardType: TextInputType.url,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hPortCtrl,
                decoration: const InputDecoration(labelText: 'Porta H'),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _vPortCtrl,
                decoration: const InputDecoration(labelText: 'Porta V'),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SliderRow(
          label: 'Latência SRT',
          value: _srtLatency.toDouble(),
          min: 80,
          max: 400,
          divisions: 16,
          display: '$_srtLatency ms',
          onChanged: (v) => setState(() => _srtLatency = v.toInt()),
        ),
        if (_obsHostCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          UrlPreview(
            label: 'HORIZONTAL',
            url: 'udp://${_obsHostCtrl.text.trim()}:${_hPortCtrl.text}',
          ),
          const SizedBox(height: 6),
          UrlPreview(
            label: 'VERTICAL',
            url: 'udp://${_obsHostCtrl.text.trim()}:${_vPortCtrl.text}',
          ),
        ],
      ],
    );
  }

  Widget _qualityCard() {
    return SectionCard(
      title: 'QUALIDADE',
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
        const SizedBox(height: 20),
        SliderRow(
          label: 'Vertical',
          value: _verticalKbps.toDouble(),
          min: 2000,
          max: 10000,
          divisions: 16,
          display: '${(_verticalKbps / 1000).toStringAsFixed(1)} Mbps',
          onChanged: (v) => setState(() => _verticalKbps = v.toInt()),
        ),
      ],
    );
  }

  String? _cameraIdOrDefault(List<CameraInfo> cameras) {
    if (_cameraId != null && cameras.any((c) => c.id == _cameraId)) {
      return _cameraId;
    }
    return cameras.isEmpty ? null : cameras.first.id;
  }

  String _cameraLabel(CameraInfo cam) {
    final lens = switch (cam.lens) {
      CameraLens.back => 'Traseira',
      CameraLens.front => 'Frontal',
      CameraLens.external => 'Externa',
      CameraLens.unknown => 'Desconhecida',
    };
    final suffix = cam.maxWidth != null && cam.maxHeight != null
        ? ' · ${cam.maxWidth}×${cam.maxHeight}'
        : '';
    final name = cam.label.isEmpty ? '#${cam.id}' : cam.label;
    return '$lens — $name$suffix';
  }

  void _save() {
    final p = widget.controller.profile;
    widget.controller.updateProfile(
      p.copyWith(
        capture: _capture,
        horizontal: p.horizontal.copyWith(bitrateBps: _horizontalKbps * 1000),
        vertical: p.vertical.copyWith(bitrateBps: _verticalKbps * 1000),
        cameraId: _cameraId,
      ),
    );
    widget.controller.updateNetwork(
      widget.controller.network.copyWith(
        obsHost: _obsHostCtrl.text.trim(),
        horizontalPort: int.tryParse(_hPortCtrl.text) ??
            widget.controller.network.horizontalPort,
        verticalPort: int.tryParse(_vPortCtrl.text) ??
            widget.controller.network.verticalPort,
        srtLatencyMs: _srtLatency,
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
          TextButton(onPressed: onClose, child: const Text('Cancelar')),
          const SizedBox(width: 8),
          FilledButton(onPressed: onSave, child: const Text('Salvar')),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textFaint),
        const SizedBox(width: 10),
        Text(
          message,
          style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
        ),
      ],
    );
  }
}
