# 逃家游戏 · 安卓版

把 `网页版/index.html` 原封不动放进 `assets/`，用一个全屏 WebView 加载，游戏逻辑零改动。

## 结构

```
安卓/
├── AndroidManifest.xml              应用清单（包名 com.ehgame.escape，minSdk 21）
├── src/com/ehgame/escape/MainActivity.java   全屏 WebView + 返回键处理
├── res/values/strings.xml           应用名「逃家游戏」
└── make_apk.sh                      纯命令行打包脚本
```

## 打包

本机不需要 Android Studio，用 SDK 命令行工具即可：

```bash
bash make_apk.sh
```

脚本做的事：`aapt2 compile/link` → `javac` → `d8` 转 dex → 塞进 APK → `zipalign` → `apksigner` 签名。

依赖 JDK 17 和 Android SDK（`build-tools;34.0.0`、`platforms;android-34`）。

## 导出存档

网页里的导出按钮会调用 `MainActivity.SaveBridge.saveFile`，把存档文件直接写进系统「下载」目录（Android 10+ 走 MediaStore，更早走公共下载目录），不用经过 WebView 的下载机制。

## 要点

- **jszip 本地化**：网页版原来从 jsdelivr 拉 jszip，打包时改成读本地 `assets/jszip.min.js`，断网也能导出存档。
- **INTERNET 权限**：总榜走 Supabase，没这个权限拉不到。
- **localStorage**：存档靠 WebView 的 DOM Storage，`setDomStorageEnabled(true)` 已开。
- **签名**：自签名 keystore（`escape.keystore`，不进仓库）。**升级必须用同一个 keystore**，否则覆盖安装会冲突，只能卸载重装。
- 安装时手机要在设置里允许「未知来源 / 安装未知应用」。

## 当前状态

- 版本 1.17，包体约 61KB，未做应用图标（暂用系统默认）
