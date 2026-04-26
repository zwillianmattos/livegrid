import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../models/camera_info.dart';
import '../models/resolution_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/settings/resolution_row.dart';
import '../widgets/settings/slider_row.dart';
import '../widgets/settings/url_preview.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late CaptureResolution _capture;
  late int _horizontalKbps;
  late int _verticalKbps;
  late ChannelMode _channelMode;
  late TextEditingController _obsHostCtrl;
  late TextEditingController _hPortCtrl;
  late TextEditingController _vPortCtrl;
  late TabController _tabController;
  String? _cameraId;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile;
    final n = widget.controller.network;
    _capture = p.capture;
    _horizontalKbps = p.horizontal.bitrateBps ~/ 1000;
    _verticalKbps = p.vertical.bitrateBps ~/ 1000;
    _channelMode = p.channelMode;
    _obsHostCtrl = TextEditingController(text: n.obsHost);
    _hPortCtrl = TextEditingController(text: '${n.horizontalPort}');
    _vPortCtrl = TextEditingController(text: '${n.verticalPort}');
    _cameraId = p.cameraId ?? widget.controller.selectedCamera?.id;
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCameras());
  }

  @override
  void dispose() {
    _obsHostCtrl.dispose();
    _hPortCtrl.dispose();
    _vPortCtrl.dispose();
    _tabController.dispose();
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
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Câmera'),
                Tab(text: 'Captura'),
                Tab(text: 'Rede'),
                Tab(text: 'Qualidade'),
              ],
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.text,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2,
              dividerColor: AppColors.hairline,
              dividerHeight: 1,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
              overlayColor: WidgetStatePropertyAll(
                AppColors.text.withValues(alpha: 0.04),
              ),
              splashFactory: NoSplash.splashFactory,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _panel(_cameraBody()),
                  _panel(_captureBody()),
                  _panel(_networkBody()),
                  _panel(_qualityBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }

  Widget _cameraBody() {
    final cameras = widget.controller.cameras;
    if (cameras.isEmpty) {
      return const _EmptyState(
        icon: Icons.videocam_off_outlined,
        title: 'Nenhuma câmera encontrada',
        message:
            'Verifique permissões e reconecte o dispositivo para continuar.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _cameraIdOrDefault(cameras),
          dropdownColor: AppColors.surfaceHigh,
          icon: const Icon(Icons.expand_more, color: AppColors.textMuted),
          decoration: const InputDecoration(labelText: 'Dispositivo'),
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          items: cameras
              .map(
                (cam) => DropdownMenuItem(
                  value: cam.id,
                  child: Text(
                    _cameraLabel(cam),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              )
              .toList(),
          selectedItemBuilder: (context) => cameras
              .map(
                (cam) => Text(
                  _cameraLabel(cam),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                ),
              )
              .toList(),
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
            label: const Text('ATUALIZAR LISTA'),
          ),
        ),
      ],
    );
  }

  Widget _captureBody() {
    return RadioGroup<CaptureResolution>(
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
    );
  }

  Widget _networkBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _obsHostCtrl,
          decoration: const InputDecoration(
            labelText: 'IP do iPhone na LAN',
            hintText: '192.168.1.50',
            helperText: 'OBS conecta nesse endereço (TCP)',
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
        if (_obsHostCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 24),
          _UrlPreviewBlock(
            host: _obsHostCtrl.text.trim(),
            hPort: _hPortCtrl.text,
            vPort: _vPortCtrl.text,
          ),
        ],
      ],
    );
  }

  Widget _qualityBody() {
    final hEnabled = _channelMode != ChannelMode.verticalOnly;
    final vEnabled = _channelMode != ChannelMode.horizontalOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelModeSelector(
          value: _channelMode,
          onChanged: (m) => setState(() => _channelMode = m),
        ),
        const SizedBox(height: 28),
        Opacity(
          opacity: hEnabled ? 1 : 0.35,
          child: IgnorePointer(
            ignoring: !hEnabled,
            child: SliderRow(
              label: 'Horizontal',
              value: _horizontalKbps.toDouble(),
              min: 2000,
              max: 12000,
              divisions: 20,
              display: '${(_horizontalKbps / 1000).toStringAsFixed(1)} Mbps',
              onChanged: (v) => setState(() => _horizontalKbps = v.toInt()),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Opacity(
          opacity: vEnabled ? 1 : 0.35,
          child: IgnorePointer(
            ignoring: !vEnabled,
            child: SliderRow(
              label: 'Vertical',
              value: _verticalKbps.toDouble(),
              min: 2000,
              max: 10000,
              divisions: 16,
              display: '${(_verticalKbps / 1000).toStringAsFixed(1)} Mbps',
              onChanged: (v) => setState(() => _verticalKbps = v.toInt()),
            ),
          ),
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
        channelMode: _channelMode,
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

class _UrlPreviewBlock extends StatelessWidget {
  const _UrlPreviewBlock({
    required this.host,
    required this.hPort,
    required this.vPort,
  });

  final String host;
  final String hPort;
  final String vPort;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        children: [
          UrlPreview(label: 'HORIZONTAL', url: 'tcp://$host:$hPort'),
          const SizedBox(height: 6),
          UrlPreview(label: 'VERTICAL', url: 'tcp://$host:$vPort'),
        ],
      ),
    );
  }
}

class _ChannelModeSelector extends StatelessWidget {
  const _ChannelModeSelector({required this.value, required this.onChanged});

  final ChannelMode value;
  final ValueChanged<ChannelMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CANAIS ATIVOS',
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
              for (final m in ChannelMode.values)
                Expanded(
                  child: _ChannelModeOption(
                    selected: m == value,
                    label: switch (m) {
                      ChannelMode.both => 'AMBOS',
                      ChannelMode.horizontalOnly => 'HORIZONTAL',
                      ChannelMode.verticalOnly => 'VERTICAL',
                    },
                    onTap: () => onChanged(m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value == ChannelMode.both
              ? 'Dois encoders em paralelo. Maior consumo térmico.'
              : 'Um encoder único. Recomendado em iPhone que esquenta.',
          style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
        ),
      ],
    );
  }
}

class _ChannelModeOption extends StatelessWidget {
  const _ChannelModeOption({
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textFaint),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
