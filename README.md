# Taber

macOS 上的窗口切换器。按住 Command+Tab 循环窗口，松开 Command 确认，Esc 取消。每个窗口单独一项，面板出现在光标所在的屏幕中央。

需要 macOS 14 或更高版本，以及 Apple 芯片。

## 运行

安装 Xcode Command Line Tools（如果 `xcrun` 不可用）：

```bash
xcode-select --install
```

克隆后在仓库根目录执行：

```bash
./build.sh
open build/Taber.app
```

`build.sh` 会先跑逻辑测试，再编译出 `build/Taber.app`。这是菜单栏应用，Dock 里没有图标。

第一次使用时，在系统设置里允许辅助功能和屏幕录制。没有辅助功能时快捷键不会生效；没有屏幕录制时列表仍可用，缩略图会退回应用图标。

默认快捷键是 Command+Tab，会盖过系统的应用切换。可以在菜单栏图标的设置里改掉。
