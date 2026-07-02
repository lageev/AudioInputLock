# FocusMic

Never lose your mic while vibecoding

A lightweight macOS menu bar app that locks your system's default audio input to a preferred device. Whenever macOS or another app tries to switch the input, FocusMic switches it right back.

## Why

macOS tends to change the default input device when you plug in a new USB mic, connect a Bluetooth headset, or wake from sleep. If you rely on a specific microphone (e.g., a studio mic for calls), this is frustrating. FocusMic watches for these changes and immediately reverts to your chosen device.

## Features

- **Menu bar app** — sits in the menu bar, showing the current mic status at a glance
- **Preferred device locking** — pick an input device; the app keeps it as the system default
- **Hot-plug aware** — detects device list changes and re-applies your preference
- **Debounced enforcement** — avoids thrashing on rapid device events
- **Login item support** — optionally launch at login (macOS 13+)
- **Activity log** — view recent enforcement actions from the main window

## Requirements

- macOS 14.0 or later
- Xcode 16+

## Usage

1. Build and run the app
2. Click the menu bar icon (mic) to open the popover
3. Select your preferred input device from the list
4. Toggle the switch to enable/disable locking
5. (Optional) Open the main window for the activity log

### Menu bar icons

| Icon | Meaning |
|------|---------|
| `mic.fill` | Locking active, preferred device online |
| `mic.slash` | Locking disabled or preferred device unavailable |

## How It Works

The app uses [Core Audio](https://developer.apple.com/documentation/coreaudio) to:

- Enumerate input devices via `kAudioHardwarePropertyDevices`
- Read/write `kAudioHardwarePropertyDefaultInputDevice`
- Listen for changes with `AudioObjectAddPropertyListenerBlock` on device list and default input

When a change is detected, it waits a short debounce period (0.15–0.3s), then sets the default input back to your preferred device — but only if locking is enabled and the device is still available.

## Project Structure

```
AudioInputLock/
├── App/                    # App entry point & delegate
│   ├── AudioInputLockApp.swift
│   └── AppDelegate.swift
├── Audio/                  # Core Audio hardware layer
│   ├── AudioHardwareService.swift
│   ├── AudioHardwareError.swift
│   ├── AudioInputDevice.swift
│   └── PreferredInputDeviceKeeper.swift
├── Settings/               # Persistence & login item
│   ├── PreferredInputDeviceSettings.swift
│   └── LoginItemManager.swift
├── UI/                     # SwiftUI views
│   ├── MenuBarContentView.swift
│   ├── MainView.swift
│   └── DeviceRow.swift
└── Assets.xcassets/        # App icons & colors
```

## License

MIT
