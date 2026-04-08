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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Builder(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          final screenHeight =
              mediaQuery.size.height -
              mediaQuery.padding.top -
              mediaQuery.padding.bottom;
          return Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: SizedBox(
              height: screenHeight,
              width: mediaQuery.size.width,
              child: JarvisOverlay(screenHeight: screenHeight),
            ),
          );
        },
      ),
    );
  }
}
