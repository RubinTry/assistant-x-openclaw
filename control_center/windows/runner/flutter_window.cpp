#include "flutter_window.h"

#include <optional>
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>

#include "flutter/generated_plugin_registrant.h"

#define RETURN_ON_BAD_HR(hr) \
  if (FAILED(hr)) { \
    result->Error("audio_error", "Failed to initialize audio device"); \
    return; \
  }

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  auto messenger = flutter_controller_->engine()->binary_messenger();
  auto channel = std::make_unique<flutter::MethodChannel>(
      messenger, "com.assistant/permission");

  channel->SetMethodCallHandler(
      [&](const flutter::MethodCall& call,
          std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method() == "requestMicrophonePermission") {
          requestMicrophonePermission(std::move(result));
        } else if (call.method() == "checkMicrophonePermission") {
          checkMicrophonePermission(std::move(result));
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::requestMicrophonePermission(
    std::unique_ptr<flutter::MethodResult<>> result) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    result->Error("com_error", "Failed to initialize COM");
    return;
  }

  IMMDeviceEnumerator* pEnumerator = nullptr;
  hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                        IID_PPV_ARGS(&pEnumerator));
  if (FAILED(hr)) {
    result->Error("com_error", "Failed to create device enumerator");
    CoUninitialize();
    return;
  }

  IMMDevice* pDevice = nullptr;
  hr = pEnumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &pDevice);
  if (hr == E_NOTFOUND) {
    result->Success(false);
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  if (FAILED(hr)) {
    result->Error("audio_error", "Failed to get default audio endpoint");
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  IAudioClient* pAudioClient = nullptr;
  hr = pDevice->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                         reinterpret_cast<void**>(&pAudioClient));
  if (hr == E_ACCESSDENIED) {
    result->Success(false);
    pDevice->Release();
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  if (FAILED(hr)) {
    result->Error("audio_error", "Failed to activate audio client");
    pDevice->Release();
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  result->Success(true);
  pAudioClient->Release();
  pDevice->Release();
  pEnumerator->Release();
}

void FlutterWindow::checkMicrophonePermission(
    std::unique_ptr<flutter::MethodResult<>> result) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    result->Error("com_error", "Failed to initialize COM");
    return;
  }

  IMMDeviceEnumerator* pEnumerator = nullptr;
  hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                        IID_PPV_ARGS(&pEnumerator));
  if (FAILED(hr)) {
    result->Error("com_error", "Failed to create device enumerator");
    CoUninitialize();
    return;
  }

  IMMDevice* pDevice = nullptr;
  hr = pEnumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &pDevice);
  if (hr == E_NOTFOUND) {
    result->Success(std::string("undetermined"));
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  if (hr == E_ACCESSDENIED) {
    result->Success(std::string("denied"));
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  if (FAILED(hr)) {
    result->Success(std::string("unknown"));
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  IAudioClient* pAudioClient = nullptr;
  hr = pDevice->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                         reinterpret_cast<void**>(&pAudioClient));
  if (hr == E_ACCESSDENIED) {
    result->Success(std::string("denied"));
    pDevice->Release();
    pEnumerator->Release();
    CoUninitialize();
    return;
  }

  if (SUCCEEDED(hr)) {
    result->Success(std::string("granted"));
    pAudioClient->Release();
  } else {
    result->Success(std::string("unknown"));
  }

  pDevice->Release();
  pEnumerator->Release();
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
