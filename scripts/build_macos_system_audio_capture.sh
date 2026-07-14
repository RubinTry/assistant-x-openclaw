#!/bin/zsh
set -e

ROOT=${0:A:h:h}
SOURCE="${ROOT}/native/macos_system_audio_capture.swift"
OUTPUT="${ROOT}/native/macos_system_audio_capture"
MODULE_CACHE="${TMPDIR:-/tmp}/assistant-x-swift-module-cache"

mkdir -p "${MODULE_CACHE}"
env CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE}" \
  swiftc -O -parse-as-library "${SOURCE}" \
  -framework ScreenCaptureKit \
  -framework CoreMedia \
  -o "${OUTPUT}"

echo "built=${OUTPUT}"
