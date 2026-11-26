import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/controllers/session_controller.dart';
import 'app/pages/live_page.dart';
import 'app/pages/permission_page.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/page_routes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LiveGridApp());
}

class LiveGridApp extends StatefulWidget {
  const LiveGridApp({super.key});

  @override
  State<LiveGridApp> createState() => _LiveGridAppState();
}

class _LiveGridAppState extends State<LiveGridApp> {
  final SessionController _controller = SessionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveGrid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: LaunchGate(controller: _controller),
    );
  }
}

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key, required this.controller});

  final SessionController controller;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      await widget.controller.checkPermissions();
    } catch (_) {}
    if (widget.controller.permissionsReady) {
      unawaited(widget.controller.initialize());
    }
    if (!mounted) return;
    setState(() => _checked = true);
  }

  void _openLive() {
    Navigator.of(context).pushReplacement(
      fadeRoute<void>((_) => LivePage(controller: widget.controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const ColoredBox(color: Color(0xFF000000));
    if (widget.controller.permissionsReady) {
      return LivePage(controller: widget.controller);
    }
    return PermissionPage(controller: widget.controller, onReady: _openLive);
  }
}
