#!/bin/bash
# =============================================================
# 琉璃助手 LiuLi · 一键构建未签名 IPA
# 用法：在 macOS（安装 Xcode 15+ 及其 Command Line Tools）上执行
#       ./build.sh
# 产物：build/LiuLi-unsigned.ipa（未签名，需自行签名后安装）
# =============================================================
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="LiuLi.xcodeproj"
SCHEME="LiuLi"
CONFIGURATION="Release"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
IPA="$BUILD_DIR/LiuLi-unsigned.ipa"

echo "==> 检查环境..."
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "错误：未找到 xcodebuild。请先安装 Xcode 15+ 并运行: xcode-select --install / sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi

echo "==> 清理旧产物..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 编译（未签名，arm64）..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    DEVELOPMENT_TEAM="" \
    | tail -20

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/LiuLi.app"
if [ ! -d "$APP_PATH" ]; then
    echo "错误：未找到编译产物 $APP_PATH"
    exit 1
fi

echo "==> 打包 IPA..."
PAYLOAD="$BUILD_DIR/Payload"
mkdir -p "$PAYLOAD"
cp -R "$APP_PATH" "$PAYLOAD/"
(cd "$BUILD_DIR" && zip -qry "$(basename "$IPA")" Payload)
rm -rf "$PAYLOAD"

SIZE=$(du -h "$IPA" | cut -f1)
echo ""
echo "============================================"
echo " 构建成功！"
echo " 产物：$IPA （$SIZE，未签名）"
echo ""
echo " 签名方式（任选其一）："
echo "  · esign / SideStore / AltStore 导入 IPA 签名"
echo "  · Sideloadly (PC) 使用 Apple ID 签名"
echo "  · 自有证书：codesign --force --sign <身份> --entitlements <ent> build/Payload/LiuLi.app"
echo "============================================"
