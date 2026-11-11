#!/bin/bash
# 在 Linux 上用 Android SDK 命令行工具直接打 APK（不需要 Android Studio）
# 依赖：JDK 17、Android SDK（build-tools 34.0.0 + platforms android-34）
set -e
cd "$(dirname "$0")"

SDK="${ANDROID_HOME:-$HOME/android-sdk}"
BT="$SDK/build-tools/34.0.0"
AJ="$SDK/platforms/android-34/android.jar"

# 1. 准备素材：网页版拷贝到 assets，jszip 一起放进去（断网也能导出存档）
mkdir -p assets
cp ../网页版/index.html assets/index.html
sed -i 's#https://fastly.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js#jszip.min.js#' assets/index.html
[ -f assets/jszip.min.js ] || curl -sL -o assets/jszip.min.js https://fastly.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js

# 2. 资源编译 + 链接（assets 会被打进 APK）
rm -rf build && mkdir -p build/res build/classes build/dex
"$BT/aapt2" compile --dir res -o build/res/res.zip
"$BT/aapt2" link -o build/base.apk -I "$AJ" \
  --manifest AndroidManifest.xml -A assets --java gen \
  --min-sdk-version 21 --target-sdk-version 34 build/res/res.zip

# 3. Java 编译 + 转 dex
javac -source 11 -target 11 -classpath "$AJ" -d build/classes \
  gen/com/ehgame/escape/R.java src/com/ehgame/escape/MainActivity.java
"$BT/d8" --release --lib "$AJ" --min-api 21 --output build/dex $(find build/classes -name '*.class')
cp build/dex/classes.dex build/ && (cd build && zip -q base.apk classes.dex)

# 4. 对齐 + 签名（keystore 必须保存好，覆盖安装要用同一个）
[ -f escape.keystore ] || keytool -genkeypair -keystore escape.keystore -alias escape \
  -keyalg RSA -keysize 2048 -validity 10000 -storepass escape2026 -keypass escape2026 \
  -dname "CN=Escape from Home, O=Sobsh562u, C=CN"
"$BT/zipalign" -f -p 4 build/base.apk build/aligned.apk
"$BT/apksigner" sign --ks escape.keystore --ks-pass pass:escape2026 --key-pass pass:escape2026 \
  --out 逃家游戏_安卓.apk build/aligned.apk

echo "OK: 逃家游戏_安卓.apk"
"$BT/apksigner" verify 逃家游戏_安卓.apk && echo "签名校验通过"
