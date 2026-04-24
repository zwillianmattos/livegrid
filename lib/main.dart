import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/controllers/session_controller.dart';
import 'app/pages/live_page.dart';
import 'app/theme/app_theme.dart';

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
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
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
      home: LivePage(controller: _controller),
    );
  }
}
