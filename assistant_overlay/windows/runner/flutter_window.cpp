#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "m3_video_bridge/m3_video_bridge_plugin.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
        : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  HWND hwnd = GetHandle();
  if (hwnd) {
    LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE);
    style |= WS_POPUP | WS_CLIPCHILDREN;
    SetWindowLongPtr(hwnd, GWL_STYLE, style);

    LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    ex_style |= WS_EX_TOPMOST;
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

    HMONITOR primary = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi = {sizeof(mi)};
    GetMonitorInfo(primary, &mi);
    int w = mi.rcMonitor.right - mi.rcMonitor.left;
    int h = mi.rcMonitor.bottom - mi.rcMonitor.top;
    SetWindowPos(hwnd, nullptr,
                 mi.rcMonitor.left, mi.rcMonitor.top,
                 w, h,
                 SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOZORDER);
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
          frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  macbear_3d::M3VideoBridgePlugin::RegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin(
          "M3VideoBridgePlugin"));
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
// Give Flutter, including plugins, an opportunity to handle window messages.
if (flutter_controller_) {
std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
if (result) {
return *result;
}
}

switch (message) {
case WM_FONTCHANGE:
flutter_controller_->engine()->ReloadSystemFonts();
break;
}

return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
