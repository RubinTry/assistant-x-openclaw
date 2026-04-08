import 'dart:io';
import 'package:flutter/material.dart';
import 'jarvis_overlay.dart';

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

    if (Platform.isWindows) {
      screenWidth = double.infinity;
      screenHeight = double.infinity;
    } else {
      final mediaQuery = MediaQuery.of(context);
      screenHeight =
          mediaQuery.size.height -
          mediaQuery.padding.top -
          mediaQuery.padding.bottom;
      screenWidth = mediaQuery.size.width;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SizedBox(
          width: screenWidth,
          height: screenHeight,
          child: JarvisOverlay(screenHeight: screenHeight),
        ),
      ),
    );
  }
}
