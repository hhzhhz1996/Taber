import AppKit
import SwiftUI

final class SwitcherPanel: NSPanel {
    init(model: SwitcherModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: SwitcherMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .none
        worksWhenModal = true

        let host = NSHostingView(rootView: SwitcherStripView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(host)
        contentView = container
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(on screen: NSScreen?, size: NSSize) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width - 32)
        let height = min(size.height, visible.height - 32)
        let frame = CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

struct SwitcherStripView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.hint)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 8)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            SwitcherCell(
                                item: item,
                                thumbnail: item.windowID.flatMap { model.thumbnails[$0] },
                                selected: index == model.selectedIndex
                            )
                            .id(item.id)
                            .onHover { hovering in
                                if hovering { model.select(index) }
                            }
                            .onTapGesture { model.onActivate?(index) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
                .onChange(of: model.selectedIndex) { _, index in
                    guard model.items.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo(model.items[index].id, anchor: .center)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

private struct SwitcherCell: View {
    let item: SwitchItem
    let thumbnail: NSImage?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                preview
                VStack {
                    HStack {
                        Text(item.badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 208, height: 128)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: selected ? 3 : 1)
            }

            HStack(spacing: 6) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(item.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: 208, alignment: .leading)

            if item.title != item.appName {
                Text(item.appName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(width: 208, alignment: .leading)
            } else {
                Text(" ")
                    .font(.caption)
                    .frame(width: 208, alignment: .leading)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
        .scaleEffect(selected ? 1.03 : 1)
        .animation(.easeOut(duration: 0.08), value: selected)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 208, maxHeight: 128)
                .frame(width: 208, height: 128)
        } else if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 56, height: 56)
        }
    }
}
