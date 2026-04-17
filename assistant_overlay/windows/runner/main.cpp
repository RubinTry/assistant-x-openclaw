#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  HMONITOR primary = ::MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {sizeof(mi)};
  ::GetMonitorInfo(primary, &mi);

  UINT dpiX, dpiY;
  HDC hdc = ::GetDC(nullptr);
  if (hdc) {
    dpiX = ::GetDeviceCaps(hdc, LOGPIXELSX);
    dpiY = ::GetDeviceCaps(hdc, LOGPIXELSY);
    ::ReleaseDC(nullptr, hdc);
  } else {
    dpiX = 96;
    dpiY = 96;
  }
  double scaleFactor = dpiX / 96.0;

  int physWidth = mi.rcMonitor.right - mi.rcMonitor.left;
  int physHeight = mi.rcMonitor.bottom - mi.rcMonitor.top;
  int logicalWidth = static_cast<int>(physWidth / scaleFactor);
  int logicalHeight = static_cast<int>(physHeight / scaleFactor);

  Win32Window::Point origin(0, 0);
  Win32Window::Size size(logicalWidth, logicalHeight);

  if (!window.Create(L"assistant_overlay", origin, size)) {
    return EXIT_FAILURE;
  }

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}