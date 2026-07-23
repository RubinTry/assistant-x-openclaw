#include "include/macbear_3d/m3_video_bridge_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "m3_video_bridge_plugin.h"

void M3VideoBridgePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  macbear_3d::M3VideoBridgePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
