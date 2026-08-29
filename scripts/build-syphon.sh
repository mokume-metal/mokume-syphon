#!/bin/bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# Vendor/Syphon-Framework から Syphon.xcframework を焼き、Frameworks/ へ置く。
#
# Frameworks/ は gitignore 済みで、あれば Package.swift がそちらを優先する
# (無ければ Release の資産を binaryTarget で引く)。上流の変更を、版を出す前に
# 試せるようにするための二段構え。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Vendor/Syphon-Framework"
BUILD_DIR="$ROOT_DIR/.build/syphon"
OUTPUT_DIR="$ROOT_DIR/Frameworks"

# Command Line Tools だけでは archive できない (xcodebuild が scheme を解決できない)
XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
if [ -z "$XCODE_PATH" ] || [[ "$XCODE_PATH" == *CommandLineTools* ]]; then
  echo "Xcode.app が要る (いまは ${XCODE_PATH:-未設定})。" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [ ! -d "$SOURCE_DIR/Syphon.xcodeproj" ]; then
  echo "Vendor/Syphon-Framework が空。次を打つ:" >&2
  echo "  git submodule update --init --recursive" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

echo "Syphon.framework を archive する..."
xcodebuild archive \
  -project "$SOURCE_DIR/Syphon.xcodeproj" \
  -scheme Syphon \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$BUILD_DIR/Syphon-macOS.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ONLY_ACTIVE_ARCH=NO

FRAMEWORK_PATH="$(find "$BUILD_DIR/Syphon-macOS.xcarchive" -name Syphon.framework -type d | head -1)"
if [ -z "$FRAMEWORK_PATH" ]; then
  echo "archive の中に Syphon.framework が無い" >&2
  exit 1
fi

echo "Syphon.xcframework を作る..."
rm -rf "$OUTPUT_DIR/Syphon.xcframework"
xcodebuild -create-xcframework \
  -framework "$FRAMEWORK_PATH" \
  -output "$OUTPUT_DIR/Syphon.xcframework"

rm -rf "$BUILD_DIR"

# どのコミットから焼いたかを残す。中身は gitignore の下なので、
# 手元で「いつのを見ているのか」を答えられるのはこの 1 行だけになる
git -C "$ROOT_DIR" submodule status Vendor/Syphon-Framework 2>/dev/null | awk '{print $1}' \
  > "$OUTPUT_DIR/.syphon-build-stamp" || true

echo "できた: $OUTPUT_DIR/Syphon.xcframework"
