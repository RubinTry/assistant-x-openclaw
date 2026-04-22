import 'dart:io';
import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/home_page.dart';

late TrayManager _trayManager;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final iconPath = Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png';

  // await windowManager.waitUntilReadyToShow(windowOptions, () async {
  //   await windowManager.hide();
  // });

  runApp(const ControlCenterApp());

  _trayManager = TrayManager();
  await _trayManager.init(iconPath);
}

class ControlCenterApp extends StatelessWidget {
  const ControlCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语音助手控制中心',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomePage(key: homePageKey),
    );
  }
}

class TrayManager {
  SystemTray? _systemTray;

  Future<void> init(String iconPath) async {
    _systemTray = SystemTray();

    await _systemTray!.initSystemTray(
      title: '',
      iconPath: iconPath,
      toolTip: '语音助手控制中心',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: '显示窗口',
        onClicked: (item) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '启动语音助手',
        onClicked: (item) => _broadcastAction('start'),
      ),
      MenuItemLabel(
        label: '停止语音助手',
        onClicked: (item) => _broadcastAction('stop'),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '关于',
        onClicked: (item) async {
          final context = navigatorKey.currentContext;
          if (context != null) {
            await showDialog(
              context: context,
              builder: (ctx) => const AboutDialog(
                applicationName: '语音助手控制中心',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2026',
              ),
            );
          }
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '退出',
        onClicked: (item) async {
          await windowManager.destroy();
        },
      ),
    ]);

    await _systemTray!.setContextMenu(menu);

    _systemTray!.registerSystemTrayEventHandler((eventName) async {
      if (eventName == kSystemTrayEventClick) {
        await windowManager.show();
        await windowManager.focus();
      } else if (eventName == kSystemTrayEventRightClick) {
        await _systemTray!.popUpContextMenu();
      }
    });
  }

  void dispose() {
    _systemTray?.destroy();
  }
}

void _broadcastAction(String action) {
  homePageKey.currentState?.handleTrayAction(action);
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<HomePageState> homePageKey = GlobalKey<HomePageState>();