# Pop · 苞米的第一粒 🌽

macOS 截图工具。**咔，一爆即得。**

> 苞米（baomi.app）家族的第一粒。家族里"苞米=一根、工具=一粒"。

## 功能

- 一个统一快捷键搞定 **区域 / 窗口 / 全屏**：按 `⌘⇧X` 出选择层
  - 鼠标悬停 → 高亮命中窗口；**单击** = 截窗口
  - **拖拽** = 截区域
  - **↩ Enter** = 截全屏（光标所在屏幕）
  - **⎋ Esc** = 取消
- 截完 **自动复制到剪贴板**，可选 **保存为 PNG**（默认关，可在偏好设置开并选目录）
- 全局快捷键 **可自定义**（用 Carbon RegisterEventHotKey，无需输入监控权限）
- 完成提示（"爆好了 🌽"）开关 + 文案可配
- **开机启动** 开关（`SMAppService`）
- 中英文 i18n（String Catalog，自动跟随系统）

## 下载使用

到 [Actions](../../actions) 页面找最近的 **Build** 任务，下面有 `Pop` artifact，下载得到 `Pop.zip`。

⚠️ **第一次打开会被 Gatekeeper 拦** —— 本仓库 CI 没有 Apple Developer 签名/公证。任选一种处理：

1. **右键 Open**：解压后右键 `Pop.app` → 「打开」→ 弹窗里再点「打开」（只需一次）
2. **去隔离属性**（最干净）：

   ```bash
   xattr -dr com.apple.quarantine /path/to/Pop.app
   ```

3. **系统设置** → 隐私与安全性 → 底部「仍然打开」按钮

打开后：
- 菜单栏右上角出现取景框图标
- 首次截图时系统会要求「屏幕录制」权限，授权后**退出 Pop 再打开**即可

## 开发

需要 macOS 14+ 和 Xcode 26+。工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，`.xcodeproj` 不进 git。

```bash
# 生成 Xcode 工程
xcodegen generate

# 在 Xcode 里开发
open Pop.xcodeproj

# 或：命令行构建 + 运行
scripts/make-app.sh Debug --run
```

## 技术栈

Swift + SwiftUI + AppKit + ScreenCaptureKit + Carbon + ServiceManagement，原生、无第三方依赖。

## 目录

```
Sources/Pop/                       源码
  PopApp.swift                       入口（MenuBarExtra 菜单栏 App）
  MenuContent.swift                  菜单内容
  Brand.swift                        品牌配色 + 微文案
  CaptureCoordinator.swift           流程编排
  ScreenCaptureService.swift         ScreenCaptureKit 截图
  RegionSelectionController.swift    统一选择层（悬停 / 拖拽 / 回车 / 取消）
  HotkeyConfig.swift                 全局设置存储（快捷键 / 保存 / 提示）
  CarbonHotkey.swift                 Carbon 全局热键封装
  HotkeyManager.swift                热键 + 设置变更监听
  SettingsView.swift                 偏好设置窗口（含按键录制器）
  ClipboardService.swift             剪贴板
  ImageSaver.swift                   PNG 保存
  HistoryStore.swift                 截图历史
  Toast.swift                        完成反馈
  Localizable.xcstrings              中英文翻译
  Assets.xcassets/                   AppIcon
App/                                 Info.plist + entitlements
project.yml                          XcodeGen 工程规格
scripts/make-app.sh                  构建脚本
.github/workflows/build.yml          CI 构建 + 打 zip
```
