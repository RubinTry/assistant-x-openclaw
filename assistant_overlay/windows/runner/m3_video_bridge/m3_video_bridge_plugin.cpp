#include "m3_video_bridge_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <versionhelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace macbear_3d {

// static
void M3VideoBridgePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.macbear.angle_test/video",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<M3VideoBridgePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

M3VideoBridgePlugin::M3VideoBridgePlugin() {}

M3VideoBridgePlugin::~M3VideoBridgePlugin() {}

void M3VideoBridgePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("registerSurface") == 0) {
    // TODO: Implement Windows Media Foundation integration
    result->Success(flutter::EncodableValue(false)); 
  } else if (method_call.method_name().compare("updateSurface") == 0) {
    result->Success(flutter::EncodableValue(false));
  } else if (method_call.method_name().compare("release") == 0) {
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("play") == 0) {
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("pause") == 0) {
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("seekTo") == 0) {
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("getDuration") == 0) {
    result->Success(flutter::EncodableValue(0.0));
  } else if (method_call.method_name().compare("getPosition") == 0) {
    result->Success(flutter::EncodableValue(0.0));
  } else {
    result->NotImplemented();
  }
}

}  // namespace macbear_3d
