import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static var allGranted: Bool { accessibilityGranted && screenRecordingGranted }

    static func promptAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")
    }

    private static func open(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

final class PermissionModel: ObservableObject {
    @Published var accessibility = Permissions.accessibilityGranted
    @Published var screenRecording = Permissions.screenRecordingGranted

    func refresh() {
        accessibility = Permissions.accessibilityGranted
        screenRecording = Permissions.screenRecordingGranted
    }
}

struct PermissionsView: View {
    @ObservedObject var model: PermissionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Taber 需要两项权限")
                .font(.title2.weight(.semibold))
            Text("没有辅助功能时，Command+Tab 不会生效，也无法把选中的窗口提到前面。没有屏幕录制时，列表仍然可用，但缩略图会退回应用图标。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                title: "辅助功能",
                granted: model.accessibility,
                detail: "监听快捷键，读取窗口，取消最小化并聚焦。"
            ) {
                Permissions.promptAccessibility()
            }

            permissionRow(
                title: "屏幕录制",
                granted: model.screenRecording,
                detail: "抓取每个窗口的缩略图。允许之后如果仍显示未授权，退出再打开一次 Taber。"
            ) {
                Permissions.requestScreenRecording()
            }

            Text(Bundle.main.bundlePath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(2)

            HStack {
                Spacer()
                Button("重新检查") { model.refresh() }
            }
        }
        .padding(24)
        .frame(width: 520, alignment: .topLeading)
    }

    private func permissionRow(title: String, granted: Bool, detail: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(granted ? "已授权" : "未授权")
                    .foregroundStyle(granted ? .green : .orange)
                Button(granted ? "打开设置" : "授权") { action() }
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
