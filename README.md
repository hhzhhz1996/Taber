# Taber

macOS 上的窗口切换器。点一下 Command+Tab 切到上一个窗口；按住再按 Tab 才打开面板。面板里可以打字筛选，⌘W 关闭，⌘M 最小化。松开 Command 确认，Esc 取消。每个窗口单独一项，面板出现在光标所在的屏幕中央。

需要 macOS 14 或更高版本，以及 Apple 芯片。

## 运行

安装 Xcode Command Line Tools（如果 `xcrun` 不可用）：

```bash
xcode-select --install
```

然后：

```bash
git clone https://github.com/hhzhhz1996/Taber.git
cd Taber
./build.sh
open build/Taber.app
```

`build.sh` 会先跑逻辑测试，再编译出 `build/Taber.app`。这是菜单栏应用，Dock 里没有图标。

第一次使用时，在系统设置里允许辅助功能和屏幕录制。没有辅助功能时快捷键不会生效；没有屏幕录制时列表仍可用，缩略图会退回应用图标。

默认快捷键是 Command+Tab，会盖过系统的应用切换。可以在菜单栏图标的设置里改掉。
