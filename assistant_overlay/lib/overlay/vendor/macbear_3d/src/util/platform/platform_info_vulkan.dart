// ignore_for_file: constant_identifier_names

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../log.dart';

// --- Vulkan 結構體與常數定義 ---
const int VK_SUCCESS = 0;
const int VK_STRUCTURE_TYPE_APPLICATION_INFO = 0;
const int VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1;

final class VkApplicationInfo extends Struct {
  @Int32()
  external int sType;
  external Pointer<Void> pNext;
  external Pointer<Utf8> pApplicationName;
  @Uint32()
  external int applicationVersion;
  external Pointer<Utf8> pEngineName;
  @Uint32()
  external int engineVersion;
  @Uint32()
  external int apiVersion;
}

final class VkInstanceCreateInfo extends Struct {
  @Int32()
  external int sType;
  external Pointer<Void> pNext;
  @Uint32()
  external int flags;
  external Pointer<VkApplicationInfo> pApplicationInfo;
  @Uint32()
  external int enabledLayerCount;
  external Pointer<Pointer<Utf8>> ppEnabledLayerNames;
  @Uint32()
  external int enabledExtensionCount;
  external Pointer<Pointer<Utf8>> ppEnabledExtensionNames;
}

final class VkPhysicalDeviceProperties extends Struct {
  @Uint32()
  external int apiVersion;
  @Uint32()
  external int driverVersion;
  @Uint32()
  external int vendorID;
  @Uint32()
  external int deviceID;
  @Int32()
  external int deviceType;
  @Array(256)
  external Array<Uint8> deviceName;
}

// --- FFI 函式簽名 ---
typedef NativeCreateInstance = Int32 Function(Pointer<VkInstanceCreateInfo>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef DartCreateInstance = int Function(Pointer<VkInstanceCreateInfo>, Pointer<Void>, Pointer<Pointer<Void>>);

typedef NativeDestroyInstance = Void Function(Pointer<Void>, Pointer<Void>);
typedef DartDestroyInstance = void Function(Pointer<Void>, Pointer<Void>);

typedef NativeEnumeratePhysicalDevices = Int32 Function(Pointer<Void>, Pointer<Uint32>, Pointer<Pointer<Void>>);
typedef DartEnumeratePhysicalDevices = int Function(Pointer<Void>, Pointer<Uint32>, Pointer<Pointer<Void>>);

typedef NativeGetPhysicalDeviceProperties = Void Function(Pointer<Void>, Pointer<VkPhysicalDeviceProperties>);
typedef DartGetPhysicalDeviceProperties = void Function(Pointer<Void>, Pointer<VkPhysicalDeviceProperties>);

/// 專門負責探測平台 Vulkan 支援狀態的類別
class PlatformInfoVulkan {
  static bool? _isVulkanSupported;
  static String _gpuName = "Unknown";

  static String get gpuName => _gpuName;

  /// 核心判定方法：決定 macbear_3d 應該使用 Vulkan 還是 OpenGL
  static bool shouldInitVulkan() {
    if (_isVulkanSupported != null) return _isVulkanSupported!;

    if (!Platform.isAndroid) {
      _isVulkanSupported = false;
      return false;
    }

    _isVulkanSupported = _probeVulkanHardware();
    return _isVulkanSupported!;
  }

  static bool _probeVulkanHardware() {
    DynamicLibrary libVulkan;
    try {
      libVulkan = DynamicLibrary.open('libvulkan.so');
    } catch (e) {
      M3Log.e('PlatformInfo', 'libvulkan.so not found.');
      return false;
    }

    final vkCreateInstance = libVulkan.lookupFunction<NativeCreateInstance, DartCreateInstance>('vkCreateInstance');
    final vkDestroyInstance = libVulkan.lookupFunction<NativeDestroyInstance, DartDestroyInstance>('vkDestroyInstance');
    final vkEnumeratePhysicalDevices = libVulkan
        .lookupFunction<NativeEnumeratePhysicalDevices, DartEnumeratePhysicalDevices>('vkEnumeratePhysicalDevices');
    final vkGetPhysicalDeviceProperties = libVulkan
        .lookupFunction<NativeGetPhysicalDeviceProperties, DartGetPhysicalDeviceProperties>(
          'vkGetPhysicalDeviceProperties',
        );

    Pointer<Void> instance = nullptr;
    final Pointer<Pointer<Void>> instancePtr = calloc<Pointer<Void>>();
    final Pointer<VkInstanceCreateInfo> createInfo = calloc<VkInstanceCreateInfo>();
    final Pointer<VkApplicationInfo> appInfo = calloc<VkApplicationInfo>();

    try {
      // 1. 建立極簡 ApplicationInfo (Vulkan 1.0 以獲得最大相容性)
      appInfo.ref
        ..sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        ..pApplicationName = "VulkanProbe".toNativeUtf8()
        ..applicationVersion = 1
        ..pEngineName = "macbear_3d".toNativeUtf8()
        ..engineVersion = 1
        ..apiVersion = (1 << 22); // VK_API_VERSION_1_0

      // 2. 建立 InstanceCreateInfo
      createInfo.ref
        ..sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        ..pApplicationInfo = appInfo
        ..enabledLayerCount = 0
        ..enabledExtensionCount = 0;

      // 3. 嘗試建立 Instance
      int result = vkCreateInstance(createInfo, nullptr, instancePtr);
      if (result != VK_SUCCESS) return false;

      instance = instancePtr.value;

      // 4. 檢查是否有實體設備 (GPU)
      final Pointer<Uint32> deviceCountPtr = calloc<Uint32>();
      vkEnumeratePhysicalDevices(instance, deviceCountPtr, nullptr);

      if (deviceCountPtr.value == 0) {
        vkDestroyInstance(instance, nullptr);
        return false;
      }

      // 5. 獲取實體設備句柄
      final Pointer<Pointer<Void>> devicesPtr = calloc<Pointer<Void>>(deviceCountPtr.value);
      vkEnumeratePhysicalDevices(instance, deviceCountPtr, devicesPtr);

      bool compatibilityPassed = false;
      for (int i = 0; i < deviceCountPtr.value; i++) {
        final Pointer<Void> device = devicesPtr[i];

        // 為 VkPhysicalDeviceProperties 分配足夠空間 (Vulkan 規格中此結構體很大，約 800+ bytes)
        // 為了安全，我們分配 1024 bytes 並轉型
        final Pointer<VkPhysicalDeviceProperties> propsPtr = calloc<Uint8>(1024).cast();
        vkGetPhysicalDeviceProperties(device, propsPtr);

        final int apiVersion = propsPtr.ref.apiVersion;
        final int vendorID = propsPtr.ref.vendorID;
        final String name = _decodeDeviceName(propsPtr.ref.deviceName);
        M3Log.i(
          "PlatformInfo",
          "Found GPU: $name (Vendor: 0x${vendorID.toRadixString(16)}, API: ${apiVersion >> 22}.${(apiVersion >> 12) & 0x3FF}.${apiVersion & 0xFFF})",
        );

        if (_isDeviceCompatible(vendorID, name, apiVersion)) {
          _gpuName = name;
          compatibilityPassed = true;
          malloc.free(propsPtr);
          break; // 找到一個相容的即可
        }
        malloc.free(propsPtr);
      }

      malloc.free(devicesPtr);
      malloc.free(deviceCountPtr);

      if (!compatibilityPassed) {
        M3Log.e('PlatformInfo', 'No compatible Vulkan GPU found (filtered by denylist).');
        vkDestroyInstance(instance, nullptr);
        return false;
      }
      M3Log.i('PlatformInfo', 'Vulkan check passed. Using: $_gpuName');

      // 清理並回傳成功
      vkDestroyInstance(instance, nullptr);
      return true;
    } catch (e) {
      M3Log.e('PlatformInfo', 'Vulkan probe error: $e');
      return false;
    } finally {
      // 釋放記憶體
      malloc.free(appInfo.ref.pApplicationName);
      malloc.free(appInfo.ref.pEngineName);
      malloc.free(appInfo);
      malloc.free(createInfo);
      malloc.free(instancePtr);
    }
  }

  /// 判定裝置相容性 (黑名單)
  static bool _isDeviceCompatible(int vendorID, String name, int apiVersion) {
    // 1. 基本 API 版本要求: 建議至少 Vulkan 1.1 (除非是已知穩定的 1.0 裝置)
    // Vulkan 1.1 = (1 << 22) | (1 << 12)
    const int vk11 = (1 << 22) | (1 << 12);
    if (apiVersion < vk11) {
      // 如果是早期 Mali 或 PowerVR 且只有 1.0，通常不建議使用
      if (vendorID == 0x13B5 || vendorID == 0x1010) {
        M3Log.h('PlatformInfo', 'Filtering out legacy ARM/PowerVR with Vulkan 1.0');
        return false;
      }
    }

    // 2. 針對特定惡名昭彰的型號過濾 (例如 GE8320)
    final String upperName = name.toUpperCase();
    if (upperName.contains("GE8320")) {
      M3Log.h('PlatformInfo', 'Filtering out PowerVR GE8320 due to instability.');
      return false;
    }

    if (upperName.contains("MALI-T")) {
      M3Log.h('PlatformInfo', 'Filtering out legacy Mali-T series.');
      return false;
    }

    return true;
  }

  static String _decodeDeviceName(Array<Uint8> deviceName) {
    final List<int> units = [];
    for (int i = 0; i < 256; i++) {
      if (deviceName[i] == 0) break;
      units.add(deviceName[i]);
    }
    return String.fromCharCodes(units);
  }
}
