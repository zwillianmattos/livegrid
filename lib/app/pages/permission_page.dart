import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../theme/app_theme.dart';

class PermissionPage extends StatefulWidget {
  const PermissionPage({
    super.key,
    required this.controller,
    required this.onReady,
  });

  final SessionController controller;
  final VoidCallback onReady;

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _busy) return;
    _run(widget.controller.checkPermissions);
  }

  Future<void> _onPressed() async {
    final c = widget.controller;
    if (c.hasPermanentlyDeniedPermission) {
      await c.openPermissionSettings();
      return;
    }
    await _run(c.requestPermissions);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (widget.controller.permissionsReady && !_done) {
      _done = true;
      widget.onReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: _FillScroll(child: _Intro())),
                const SizedBox(width: 32),
                Expanded(
                  child: _FillScroll(
                    child: _Access(
                      controller: widget.controller,
                      busy: _busy,
                      onPressed: _onPressed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FillScroll extends StatelessWidget {
  const _FillScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LIVEGRID', style: AppTheme.label(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        Text(
          'Grave uma vez, saia com dois vídeos',
          style: theme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Cada gravação gera um 16:9 e um 9:16 direto na sua galeria. '
          'Pra isso o app precisa de três acessos.',
          style: theme.bodyMedium?.copyWith(height: 1.5),
        ),
        const Spacer(),
        const SizedBox(height: 20),
        const _FormatIllustration(),
      ],
    );
  }
}

class _FormatIllustration extends StatelessWidget {
  const _FormatIllustration();

  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _Frame(label: '16:9', color: AppColors.surface),
          ),
          SizedBox(width: 8),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: _Frame(label: '9:16', color: AppColors.surfaceHigh),
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      child: Text(label, style: AppTheme.label(color: AppColors.textMuted)),
    );
  }
}

class _Access extends StatelessWidget {
  const _Access({
    required this.controller,
    required this.busy,
    required this.onPressed,
  });

  final SessionController controller;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final denied = controller.hasPermanentlyDeniedPermission;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: Column(
            children: [
              for (final p in AppPermission.values)
                _PermissionRow(
                  permission: p,
                  status: controller.permissionStatus(p),
                ),
            ],
          ),
        ),
        const Spacer(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(denied ? 'ABRIR AJUSTES' : 'PERMITIR ACESSOS'),
        ),
        const SizedBox(height: 8),
        Text(
          'Sem microfone o app grava mudo.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.permission, required this.status});

  final AppPermission permission;
  final AppPermissionStatus status;

  (String, String) get _copy => switch (permission) {
    AppPermission.camera => ('Câmera', 'Preview e gravação'),
    AppPermission.microphone => ('Microfone', 'Áudio nos dois arquivos'),
    AppPermission.photos => ('Galeria', 'Salvar os vídeos prontos'),
  };

  (String, Color) get _status => switch (status) {
    AppPermissionStatus.granted => ('OK', AppColors.safe),
    AppPermissionStatus.pending => ('PENDENTE', AppColors.textMuted),
    AppPermissionStatus.permanentlyDenied => ('NEGADO', AppColors.live),
  };

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _copy;
    final (label, color) = _status;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          CustomPaint(
            size: const Size.square(20),
            painter: _StrokeIconPainter(permission),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: AppTheme.label(color: color)),
        ],
      ),
    );
  }
}

class _StrokeIconPainter extends CustomPainter {
  const _StrokeIconPainter(this.permission);

  final AppPermission permission;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = AppColors.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    switch (permission) {
      case AppPermission.camera:
        canvas.drawPath(
          Path()..addPolygon(const [
            Offset(4, 7),
            Offset(7, 7),
            Offset(9, 4),
            Offset(15, 4),
            Offset(17, 7),
            Offset(20, 7),
            Offset(20, 20),
            Offset(4, 20),
          ], true),
          paint,
        );
        canvas.drawCircle(const Offset(12, 13), 4, paint);
      case AppPermission.microphone:
        canvas.drawRect(const Rect.fromLTWH(9, 3, 6, 11), paint);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 11), radius: 7),
          math.pi,
          -math.pi,
          false,
          paint,
        );
        canvas.drawLine(const Offset(12, 18), const Offset(12, 21), paint);
      case AppPermission.photos:
        canvas.drawRect(const Rect.fromLTWH(3, 4, 18, 16), paint);
        canvas.drawPath(
          Path()..addPolygon(const [
            Offset(3, 16),
            Offset(8, 11),
            Offset(12, 15),
            Offset(15, 12),
            Offset(21, 18),
          ], false),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_StrokeIconPainter oldDelegate) =>
      oldDelegate.permission != permission;
}
