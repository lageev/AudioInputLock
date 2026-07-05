# FocusMic

[English](README.md) | [官网](https://focusmic.yayalu.top/) | [最新版本](https://github.com/lageev/FocusMic/releases/latest)

从菜单栏锁定 macOS 默认麦克风。

FocusMic 是一款开源的 macOS 小工具，用来把系统默认音频输入固定在你选定的麦克风上。如果 macOS、蓝牙耳机、USB 声卡或其他应用把输入设备切走，FocusMic 可以自动切回来。

![FocusMic 官网首屏截图](docs/assets/focusmic-first-screen-zh-cn.png)

## 安装

从 [GitHub Releases](https://github.com/lageev/FocusMic/releases/latest) 下载最新版本，或使用 Homebrew 安装：

```sh
brew install --cask lageev/tap/focusmic
```

运行要求：macOS 15.0 或更高版本。

## 使用

1. 打开 FocusMic。
2. 点击菜单栏图标。
3. 选择想要固定的输入设备。
4. 打开 **守护输入设备**。

只要选定设备在线，FocusMic 就会把它保持为系统默认输入。设备断开时，FocusMic 会等待它重新连接后再恢复。

## 功能

- 菜单栏选择设备、开关守护。
- 默认输入被切走后自动恢复。
- 可选锁定选定设备的输入音量。
- 可选实时输入电平，本地计算。
- 展示设备信息：传输类型、采样率、位深、通道数、音量、使用中状态。
- 支持 USB、蓝牙、内置等 Core Audio 输入设备的热插拔。
- 最近活动日志。
- 开机自启动。
- GitHub/Homebrew 直发版通过 Sparkle 更新；App Store 版由 App Store 更新。

## 隐私

FocusMic 完全在你的 Mac 本地运行。

- 不录制、不上传、不分析音频。
- 输入电平只在本地实时读取响度，不保存任何内容。
- 无账号、无统计、无广告、无追踪、无崩溃上报。
- GitHub/Homebrew 直发版仅在 Sparkle 检查更新时联网。
- 偏好设置只保存在本地 `UserDefaults`。

完整说明见 [隐私政策](https://focusmic.yayalu.top/privacy)。

## 开发

要求：

- macOS 15.0 或更高版本
- Xcode 16 或更高版本，并支持 macOS 15 SDK

从源码运行：

1. 克隆本仓库。
2. 用 Xcode 打开 `FocusMic.xcodeproj`。
3. 选择 `FocusMic` scheme。
4. 在 Xcode 中运行。

主要技术：SwiftUI、Core Audio、Observation、ServiceManagement、Sparkle。

## 项目结构

```text
.
├── FocusMic.xcodeproj/     # Xcode 工程
├── FocusMic/
│   ├── App/                # App 入口、生命周期、更新、品牌链接
│   ├── Audio/              # Core Audio 设备模型与守护逻辑
│   ├── Settings/           # 偏好设置与开机自启动
│   ├── UI/                 # SwiftUI 菜单栏、主窗口、设备行、日志
│   ├── Assets.xcassets/    # App 图标和颜色
│   └── IconSources/        # 图标源文件
├── docs/assets/            # README 图片
├── SupportFiles/           # Info.plist 与 entitlements
├── landing/                # 官网、法律页面、更新源
├── README.md
└── README.zh-CN.md
```

## 用户群

微信扫码加入 FocusMic 用户群。二维码 2026-07-12 前有效。

<img src="docs/assets/focusmic-wechat-group.png" alt="FocusMic 微信用户群二维码" width="260">

## 链接

- [官网](https://focusmic.yayalu.top/)
- [用户协议](https://focusmic.yayalu.top/terms)
- [隐私政策](https://focusmic.yayalu.top/privacy)
- [问题反馈](https://github.com/lageev/FocusMic/issues)

## 致谢

感谢 [linux.do](https://linux.do/) 社区的支持和反馈。

## 许可证

MIT
