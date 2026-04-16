import 'dart:io';
import 'package:flutter/material.dart';
import 'agent_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    double screenWidth;
    double screenHeight;
    Color backgroundColor;

    if (Platform.isWindows) {
      final mediaQuery = MediaQuery.of(context);
      screenWidth = mediaQuery.size.width;
      screenHeight = mediaQuery.size.height;
      backgroundColor = const Color(0xFF00FFFF);
    } else {
      final mediaQuery = MediaQuery.of(context);
      screenHeight =
          mediaQuery.size.height -
          mediaQuery.padding.top -
          mediaQuery.padding.bottom;
      screenWidth = mediaQuery.size.width;
      backgroundColor = Colors.transparent;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Scaffold(
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: false,
        body: SizedBox(
          width: screenWidth,
          height: screenHeight,
          child: AgentOverlay(screenHeight: screenHeight),
        ),
      ),
    );
  }
}
