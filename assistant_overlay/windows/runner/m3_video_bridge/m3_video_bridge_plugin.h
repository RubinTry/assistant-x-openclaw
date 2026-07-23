#ifndef FLUTTER_PLUGIN_M3_VIDEO_BRIDGE_PLUGIN_H_
#define FLUTTER_PLUGIN_M3_VIDEO_BRIDGE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace macbear_3d {

class M3VideoBridgePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  M3VideoBridgePlugin();

  virtual ~M3VideoBridgePlugin();

  // Disallow copy and assign.
  M3VideoBridgePlugin(const M3VideoBridgePlugin&) = delete;
  M3VideoBridgePlugin& operator=(const M3VideoBridgePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace macbear_3d

#endif  // FLUTTER_PLUGIN_M3_VIDEO_BRIDGE_PLUGIN_H_
