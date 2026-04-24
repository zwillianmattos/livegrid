import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/controllers/session_controller.dart';
import 'app/pages/live_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LivePage(controller: _controller),
    );
  }
}
