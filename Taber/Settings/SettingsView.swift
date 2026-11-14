import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("快捷键")
                .font(.headline)
            HStack(spacing: 12) {
                Button(store.isRecordingShortcut ? "请按下快捷键…" : ShortcutText.describe(store.shortcut)) {
                    store.beginRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if store.isRecordingShortcut {
                    Button("取消") { store.endRecording() }
                }
            }
            Text("默认是 Command+Tab，会盖过系统的应用切换。按住修饰键再按主键开始循环。Shift 始终表示反向。松开修饰键确认，Esc 取消。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("窗口列表")
                .font(.headline)
            Toggle("只显示当前显示器的窗口", isOn: $store.currentDisplayOnly)
            Toggle("包含全屏窗口", isOn: $store.includeFullscreen)
            Toggle("包含其他空间的窗口", isOn: $store.includeOtherSpaces)
            Toggle("包含最小化窗口", isOn: $store.includeMinimized)
            Toggle("包含仪表盘项目", isOn: $store.includeDashboards)
            Toggle("包含已隐藏的应用", isOn: $store.includeHidden)
            Toggle("包含没有窗口的后台应用", isOn: $store.includeWindowless)

            Text("当前空间里打开的窗口始终列出。全屏和其他空间是已经打开、但在别的桌面里的窗口。仪表盘是只收在状态栏里的界面，例如 Clash Verge。后台和已隐藏是没有可切换窗口的应用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 480, height: 560, alignment: .topLeading)
        .onDisappear { store.endRecording() }
    }
}
