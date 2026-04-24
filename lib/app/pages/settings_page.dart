import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../models/camera_info.dart';
import '../models/resolution_profile.dart';

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
    final cameras = widget.controller.cameras;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Câmera'),
            if (cameras.isEmpty)
              const ListTile(
                leading: Icon(Icons.videocam_off),
                title: Text('Nenhuma câmera encontrada'),
                subtitle: Text('Verifique permissões e tente novamente'),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _cameraIdOrDefault(cameras),
                decoration: const InputDecoration(
                  labelText: 'Dispositivo',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final cam in cameras)
                    DropdownMenuItem(
                      value: cam.id,
                      child: Text(_cameraLabel(cam)),
                    ),
                ],
                onChanged: (v) => setState(() => _cameraId = v),
              ),
            TextButton.icon(
              onPressed: () async {
                await widget.controller.refreshCameras();
                if (!mounted) return;
                setState(() {});
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Atualizar lista'),
            ),
            const Divider(),
            _section('Captura'),
            RadioGroup<CaptureResolution>(
              groupValue: _capture,
              onChanged: (v) {
                if (v != null) setState(() => _capture = v);
              },
              child: Column(
                children: [
                  for (final r in CaptureResolution.values)
                    RadioListTile<CaptureResolution>(
                      value: r,
                      enabled: r.coversVertical1080p,
                      title: Text('${r.width} × ${r.height}'),
                      subtitle: Text(
                        r.coversVertical1080p
                            ? 'Cobre 1080p vertical'
                            : 'Abaixo do mínimo (1080p vertical)',
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            _section('Bitrate horizontal'),
            Slider(
              value: _horizontalKbps.toDouble(),
              min: 2000,
              max: 12000,
              divisions: 20,
              label: '$_horizontalKbps kbps',
              onChanged: (v) => setState(() => _horizontalKbps = v.toInt()),
            ),
            _section('Bitrate vertical'),
            Slider(
              value: _verticalKbps.toDouble(),
              min: 2000,
              max: 10000,
              divisions: 20,
              label: '$_verticalKbps kbps',
              onChanged: (v) => setState(() => _verticalKbps = v.toInt()),
            ),
            const Divider(),
            _section('OBS (destino UDP)'),
            TextField(
              controller: _obsHostCtrl,
              decoration: const InputDecoration(
                labelText: 'Host (IP do PC com OBS)',
                hintText: '192.168.1.50',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hPortCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Porta H',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _vPortCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Porta V',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_obsHostCtrl.text.isNotEmpty)
              Text(
                'OBS Media Source:\nudp://@:${_hPortCtrl.text}  (horizontal)\nudp://@:${_vPortCtrl.text}  (vertical)',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            const Divider(),
            _section('SRT latency (ms)'),
            Slider(
              value: _srtLatency.toDouble(),
              min: 80,
              max: 400,
              divisions: 16,
              label: '$_srtLatency ms',
              onChanged: (v) => setState(() => _srtLatency = v.toInt()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
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

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

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
        horizontalPort:
            int.tryParse(_hPortCtrl.text) ??
            widget.controller.network.horizontalPort,
        verticalPort:
            int.tryParse(_vPortCtrl.text) ??
            widget.controller.network.verticalPort,
        srtLatencyMs: _srtLatency,
      ),
    );
    Navigator.of(context).pop();
  }
}
