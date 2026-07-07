import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'agent_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
  }

  if (Platform.isWindows) {
    await acrylic.Window.initialize();
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    windowManager.waitUntilReadyToShow(
      WindowOptions(fullScreen: true, skipTaskbar: true),
      () async {
        await windowManager.setIgnoreMouseEvents(true);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
      },
    );
  }

  runApp(const JarvisApp());
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp>
    with WidgetsBindingObserver, ScreenListener {
  Timer? _displayPollTimer;
  String? _primaryDisplaySignature;
  bool _pinningToPrimaryDisplay = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      WidgetsBinding.instance.addObserver(this);
      screenRetriever.addListener(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pinToPrimaryDisplay(reason: 'startup', force: true);
      });
      _displayPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _pinToPrimaryDisplay(reason: 'poll');
      });
    }
  }

  @override
  void dispose() {
    _displayPollTimer?.cancel();
    if (_isDesktop) {
      screenRetriever.removeListener(this);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _pinToPrimaryDisplay(reason: 'metrics', force: true);
  }

  @override
  void onScreenEvent(String eventName) {
    _pinToPrimaryDisplay(reason: eventName, force: true);
  }

  Future<void> _pinToPrimaryDisplay({
    required String reason,
    bool force = false,
  }) async {
    if (!_isDesktop || _pinningToPrimaryDisplay) {
      return;
    }

    _pinningToPrimaryDisplay = true;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final signature = _displaySignature(display);
      if (!force && signature == _primaryDisplaySignature) {
        return;
      }

      _primaryDisplaySignature = signature;
      final position = display.visiblePosition ?? Offset.zero;
      final size = display.size;
      await windowManager.setBounds(
        Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
      );
      await windowManager.setIgnoreMouseEvents(true);
      await windowManager.setAlwaysOnTop(true);
      debugPrint('[Overlay] pinned to primary display ($reason): $signature');
    } catch (error) {
      debugPrint('[Overlay] failed to pin primary display ($reason): $error');
    } finally {
      _pinningToPrimaryDisplay = false;
    }
  }

  String _displaySignature(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    return [
      display.id,
      display.name ?? '',
      position.dx.toStringAsFixed(1),
      position.dy.toStringAsFixed(1),
      display.size.width.toStringAsFixed(1),
      display.size.height.toStringAsFixed(1),
      display.scaleFactor?.toStringAsFixed(2) ?? '',
    ].join('|');
  }

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
