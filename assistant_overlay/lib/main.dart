import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';
import 'agent_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  windowManager.waitUntilReadyToShow(null, () async {
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    await windowManager.setIgnoreMouseEvents(true);
    await windowManager.setAlwaysOnTop(true);
  });

  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox(
          width: screenWidth,
          height: screenHeight,
          child: AgentOverlay(screenHeight: screenHeight),
        ),
      ),
    );
  }
}