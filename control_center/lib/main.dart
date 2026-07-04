import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/home_page.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  if (Platform.isWindows) {
    windowManager.waitUntilReadyToShow(
      WindowOptions(skipTaskbar: true, title: "语音助手控制中心"),
    );
  }

  runApp(const ControlCenterApp());

  await TrayManager.instance.setIcon(
    Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png',
  );
  await TrayManager.instance.setToolTip('语音助手控制中心');

  final menu = Menu(
    items: [
      MenuItem(
        label: '显示窗口',
        onClick: (menuItem) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItem.separator(),
      MenuItem(
        label: '启动语音助手',
        onClick: (menuItem) => _broadcastAction('start'),
      ),
      MenuItem(
        label: '停止语音助手',
        onClick: (menuItem) => _broadcastAction('stop'),
      ),
      MenuItem.separator(),
      MenuItem(
        label: '关于',
        onClick: (menuItem) async {
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
      MenuItem.separator(),
      MenuItem(
        label: '退出',
        onClick: (menuItem) async {
          await windowManager.destroy();
        },
      ),
    ],
  );

  await TrayManager.instance.setContextMenu(menu);

  TrayManager.instance.addListener(_TrayListener());
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    TrayManager.instance.popUpContextMenu();
  }
}

void _broadcastAction(String action) {
  homePageKey.currentState?.handleTrayAction(action);
}

class ControlCenterApp extends StatelessWidget {
  const ControlCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语音助手控制中心',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomePage(key: homePageKey),
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<HomePageState> homePageKey = GlobalKey<HomePageState>();
