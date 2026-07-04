# FocusMic

[English](README.md) | [官网](https://focusmic.yayalu.top/) | [最新版本](https://github.com/lageev/FocusMic/releases/latest)

锁定你的麦克风，别再被 macOS 偷偷切换。

FocusMic 是一款轻量的 macOS 菜单栏应用，用来把系统默认音频输入锁定在你选定的麦克风上。如果 macOS、蓝牙耳机、USB 声卡或其他应用把默认输入切走，在开启守护后 FocusMic 会自动切回来。

## 为什么需要它

macOS 经常会在这些场景里改掉默认输入设备：插入新的 USB 麦克风、连接蓝牙耳机、接入扩展坞、从睡眠中唤醒。这个变化很容易被忽略，直到开会时才发现声音来自错误的麦克风。

FocusMic 会监听 Core Audio 的设备变化，记住你的首选输入设备，并在需要时自动恢复。它不会录音，也不会监听任何音频内容。

## 功能

- **菜单栏工作流**：在菜单栏中查看状态、开关守护、刷新设备、切换输入。
- **首选输入锁定**：选择一次麦克风，持续把它保持为系统默认输入。
- **输入音量锁定**：可选锁定锁定设备的输入增益，被其他应用改动后自动恢复。
- **更丰富的设备信息**：传输类型（USB/蓝牙/内置等）、采样率、位深、通道数、输入音量与使用中指示。
- **实时输入电平**：可选的本地电平表，确认麦克风正常收音（不录制、不保存）。
- **设备热插拔感知**：监听输入设备列表变化，设备重新连接后自动恢复偏好。
- **事件驱动监听**：直接监听 Core Audio 硬件事件，不在后台轮询。
- **防抖切换**：系统事件密集发生时短暂等待，避免反复切换。
- **活动日志**：记录最近的设备切换和守护动作。
- **开机自启动**：可选择登录 macOS 后自动启动 FocusMic。
- **应用内更新**：直发版通过 Sparkle 自更新；商店版由 App Store 负责更新。
- **隐私友好**：无账号、无统计、无录音。

## 运行要求

- macOS 15.0 或更高版本
- Xcode 16 或更高版本，并支持 macOS 15 SDK

项目使用 SwiftUI、Core Audio、Observation 和 ServiceManagement。

## 下载

从 [GitHub Releases](https://github.com/lageev/FocusMic/releases/latest) 下载最新版本。

也可以通过 Homebrew 安装：

```sh
brew install --cask lageev/tap/focusmic
```

从源码运行：

1. 克隆本仓库。
2. 用 Xcode 打开 `FocusMic.xcodeproj`。
3. 选择 `FocusMic` scheme 后在 Xcode 中运行。

## 使用方式

1. 启动 FocusMic。
2. 点击菜单栏图标。
3. 选择想要锁定的输入设备。
4. 打开 **守护输入设备**。
5. 可选：打开主窗口，设置开机自启动或查看最近活动。

守护开启且首选设备在线时，FocusMic 会持续把该设备保持为系统默认输入。首选设备离线时，FocusMic 会等待它重新连接。

## 状态说明

FocusMic 会根据已选择设备、当前系统默认输入和守护开关推导状态：

| 状态 | 含义 |
| --- | --- |
| 未选择锁定设备 | 点选一个输入设备即可开始。 |
| 已锁定，守护中 | 首选设备是当前系统输入，且守护已开启。 |
| 已选择，未守护 | 已选择首选设备，但自动切回未开启。 |
| 即将切回 | 其他设备成为默认输入，守护会尝试切回首选设备。 |
| 设备离线 | 首选设备当前不可用，重新接入后会恢复。 |

## 工作原理

FocusMic 使用 [Core Audio](https://developer.apple.com/documentation/coreaudio) 完成这些操作：

- 通过 `kAudioHardwarePropertyDevices` 枚举输入设备；
- 读取和写入 `kAudioHardwarePropertyDefaultInputDevice`；
- 使用 `AudioObjectAddPropertyListenerBlock` 监听设备列表和默认输入变化。

当检测到变化时，FocusMic 会刷新输入设备列表，经过短暂防抖后，在守护开启且首选设备可用的情况下，把系统默认输入重新写回首选设备。

## 隐私

FocusMic 完全在你的 Mac 本地运行。

- 不录制、不上传、不分析任何音频。可选的电平表只在本地实时计算响度，不保留任何内容。
- 唯一的网络请求是直发版的 Sparkle 更新检查（访问官网托管的更新源）；商店版不发起任何网络请求。
- 不包含统计、广告、追踪或崩溃上报。
- 仅在本地 `UserDefaults` 保存必要偏好：首选设备 UID/名称、守护开关状态、音量锁定、电平表开关和最近活动日志。

完整说明见 [隐私政策](https://focusmic.yayalu.top/privacy)。

## 项目结构

```text
.
├── FocusMic.xcodeproj/     # Xcode 工程
├── FocusMic/
│   ├── App/                # App 入口、delegate 和品牌常量
│   ├── Audio/              # Core Audio 硬件层与守护协调器
│   ├── Settings/           # UserDefaults 与开机自启动
│   ├── UI/                 # SwiftUI 菜单栏、设置、设备行和日志视图
│   ├── Assets.xcassets/    # App 图标和颜色
│   └── IconSources/        # SVG/icon 源文件
├── SupportFiles/           # 两个 target 的 entitlements 与 Sparkle Info.plist
├── landing/                # 静态官网、用户协议、隐私政策、更新源和多语言文案
├── README.md
└── README.zh-CN.md
```

## 链接

- [官网](https://focusmic.yayalu.top/)
- [用户协议](https://focusmic.yayalu.top/terms)
- [隐私政策](https://focusmic.yayalu.top/privacy)
- [问题反馈](https://github.com/lageev/FocusMic/issues)

## 许可证

MIT
