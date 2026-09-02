import AppKit
import SwiftUI

struct DashboardView: View {
    @Bindable var store: CleanupStore
    @State private var isConfirmingCleanAll = false
    @State private var listHeight: CGFloat = 180

    private let width: CGFloat = 360
    private let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            toolList
        }
        .frame(width: width)
        .modifier(TopAnchoredResize())
    }

    private var foundTools: [ToolStats] {
        store.snapshots.filter(\.isFound)
    }

    private var missingToolNames: [String] {
        store.snapshots.filter { !$0.isFound }.map(\.tool.name)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            brandMark

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(byteCount(store.totalBytes))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("reclaimable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .animation(.default, value: store.totalBytes)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                refreshButton
                optionsMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var brandMark: some View {
        if let icon = MenuBarIcon.image {
            Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityLabel("Slopup")
        } else {
            Image(systemName: "externaldrive.badge.minus")
                .font(.system(size: 16, weight: .medium))
                .accessibilityLabel("Slopup")
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Group {
                if store.isScanning {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(HeaderIconButtonStyle())
        .disabled(store.isScanning)
        .help("Rescan")
    }

    private var optionsMenu: some View {
        Menu {
            Button("Clean All…", role: .destructive) {
                withAnimation(.snappy(duration: 0.22)) {
                    isConfirmingCleanAll = true
                }
            }
            .disabled(store.foundToolCount == 0 || !store.cleaningTools.isEmpty)
            Divider()
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                )
            )
            Divider()
            Button("Quit Slopup") { store.quit() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HeaderIconButtonStyle())
        .fixedSize()
        .help("More")
    }

    // MARK: List

    private var toolList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isConfirmingCleanAll {
                    ConfirmationPrompt(
                        title: "Move all detected data to Trash?",
                        message: "Quit agentic coding tools first to avoid removing active sessions.",
                        confirmTitle: "Move All to Trash",
                        onCancel: { dismissCleanAll() },
                        onConfirm: {
                            dismissCleanAll()
                            Task { await store.cleanAllNow() }
                        }
                    )
                    .padding(10)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }

                if let notice = store.notice {
                    NoticeView(notice: notice) { store.notice = nil }
                        .padding(.bottom, 6)
                }

                if foundTools.isEmpty {
                    if store.lastScan == nil {
                        scanningState
                    } else {
                        emptyState
                    }
                } else {
                    ForEach(foundTools) { stats in
                        ToolRow(
                            stats: stats,
                            retentionDays: store.retentionDays(for: stats.id),
                            isCleaning: store.cleaningTools.contains(stats.id),
                            onClean: { Task { await store.cleanNow(stats.tool) } },
                            onRetentionChange: { store.setRetentionDays($0, for: stats.id) },
                            onReveal: { store.reveal($0) }
                        )
                    }
                }

                if !missingToolNames.isEmpty, store.lastScan != nil {
                    Text("Not installed: \(missingToolNames.formatted(.list(type: .and)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.top, foundTools.isEmpty ? 0 : 8)
                        .padding(.bottom, 6)
                }
            }
            .padding(8)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                listHeight = height
            }
        }
        .frame(height: min(listHeight, maxListHeight))
    }

    private func dismissCleanAll() {
        withAnimation(.snappy(duration: 0.22)) {
            isConfirmingCleanAll = false
        }
    }

    private var scanningState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Scanning…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing to clean")
                .font(.subheadline.weight(.medium))
            Text("No supported agent data was found in your home folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

}

// MARK: - Inline confirmation

/// Confirmation UI that lives inside the popover. Modal alerts open a separate
/// window, and the MenuBarExtra panel treats a click there as "outside" and
/// closes before the alert button can fire.
private struct ConfirmationPrompt: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .modifier(GlassButton())
                Button(confirmTitle, action: onConfirm)
                    .modifier(ProminentGlassButton())
                    .tint(.red)
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Tool row

private struct ToolRow: View {
    let stats: ToolStats
    let retentionDays: Int
    let isCleaning: Bool
    let onClean: () -> Void
    let onRetentionChange: (Int) -> Void
    let onReveal: (LocationStats) -> Void

    private enum Confirmation: Equatable {
        case trash
        case retention(Int)
    }

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var confirmation: Confirmation?

    private static let retentionOptions = [7, 14, 30, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
            if isExpanded || confirmation != nil {
                details
            }
        }
    }

    private func requestTrash() {
        withAnimation(.snappy(duration: 0.22)) {
            confirmation = .trash
        }
    }

    private func resolveConfirmation(confirmed: Bool) {
        let pending = confirmation
        withAnimation(.snappy(duration: 0.22)) {
            confirmation = nil
        }
        guard confirmed, let pending else { return }
        switch pending {
        case .trash: onClean()
        case .retention(let days): onRetentionChange(days)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            ToolTile(tool: stats.tool)

            VStack(alignment: .leading, spacing: 1) {
                Text(stats.tool.name)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            Text(byteCount(stats.bytes))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)

            if isCleaning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Button(action: requestTrash) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.accessoryBar)
                .help("Move \(stats.tool.name) data to Trash")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.fill.quaternary)
                .opacity(isHovered ? 1 : 0)
        }
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) {
                isExpanded.toggle()
            }
        }
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Hides options" : "Shows options")
    }

    private var subtitle: String {
        let files = stats.itemCount == 1 ? "1 file" : "\(stats.itemCount.formatted()) files"
        return retentionDays == 0 ? files : "\(files) · Keeps \(retentionDays)d"
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        let existing = stats.locations.filter(\.exists)
        if !existing.isEmpty {
            Menu("Show in Finder") {
                ForEach(existing) { location in
                    Button(location.location.label) { onReveal(location) }
                }
            }
            Divider()
        }
        Button("Move to Trash…", role: .destructive, action: requestTrash)
            .disabled(isCleaning)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if confirmation == .trash {
                ConfirmationPrompt(
                    title: "Move \(stats.tool.name) data to Trash?",
                    message: "Quit \(stats.tool.name) first to avoid removing an active session.",
                    confirmTitle: "Move to Trash",
                    onCancel: { resolveConfirmation(confirmed: false) },
                    onConfirm: { resolveConfirmation(confirmed: true) }
                )
                .padding(10)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stats.tool.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(locationSummary)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 10)

                HStack {
                    Text("Auto-clean")
                        .font(.subheadline)
                    Spacer()
                    Picker("Auto-clean", selection: retentionSelection) {
                        Text("Off").tag(0)
                        ForEach(Self.retentionOptions, id: \.self) { days in
                            Text("Keep \(days) days").tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Permanently delete items older than the retention window. Runs hourly while Slopup is open.")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                if case .retention(let days) = confirmation {
                    Divider()
                        .padding(.horizontal, 10)
                    ConfirmationPrompt(
                        title: "Enable \(days)-day auto-clean?",
                        message: "\(stats.tool.name) data older than \(days) days will be permanently deleted every hour while Slopup runs. This does not use the Trash.",
                        confirmTitle: "Enable",
                        onCancel: { resolveConfirmation(confirmed: false) },
                        onConfirm: { resolveConfirmation(confirmed: true) }
                    )
                    .padding(10)
                }
            }
        }
        .padding(.vertical, 2)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, 44)
        .padding(.trailing, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private var locationSummary: String {
        let count = stats.locations.filter(\.exists).count
        return count == 1 ? "1 location" : "\(count) locations"
    }

    /// Shows the pending choice while confirming so the popup doesn't snap back
    /// (and re-fire its setter) before the user has answered.
    private var retentionSelection: Binding<Int> {
        Binding(
            get: {
                if case .retention(let days) = confirmation { days } else { retentionDays }
            },
            set: { days in
                let shown: Int
                if case .retention(let pending) = confirmation { shown = pending } else { shown = retentionDays }
                guard days != shown else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    if days == 0 {
                        confirmation = nil
                        if retentionDays != 0 { onRetentionChange(0) }
                    } else {
                        confirmation = .retention(days)
                    }
                }
            }
        )
    }
}

// MARK: - Tile & logo

private struct ToolTile: View {
    let tool: AgentTool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6.5, style: .continuous)
        ZStack {
            shape.fill(Color(hex: tool.color).gradient)
            shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            ProviderLogo(tool: tool)
                .frame(width: 14, height: 14)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private struct ProviderLogo: View {
    let tool: AgentTool

    var body: some View {
        if let image = LogoCache.image(for: tool) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
        } else {
            Image(systemName: tool.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

@MainActor
private enum LogoCache {
    private static var images: [AgentTool.ID: NSImage] = [:]

    static func image(for tool: AgentTool) -> NSImage? {
        if let cached = images[tool.id] {
            return cached
        }
        let appURL = Bundle.main.url(
            forResource: tool.id.rawValue,
            withExtension: "svg",
            subdirectory: "ProviderLogos"
        )
        guard let url = appURL ?? Bundle.module.url(forResource: tool.id.rawValue, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        images[tool.id] = image
        return image
    }
}

// MARK: - Notice

private struct NoticeView: View {
    let notice: AppNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)

            Text(notice.message)
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help("Dismiss")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch notice.kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch notice.kind {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

// MARK: - Styles

/// Borderless header icon: secondary at rest, brightens on hover, dims while pressed. No background.
private struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    private struct HoverLabel: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .opacity(configuration.isPressed ? 0.5 : 1)
                .onHover { isHovered = $0 }
        }
    }
}

private struct GlassButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct ProminentGlassButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

/// Keeps the popover pinned under the status item while its height changes.
private struct TopAnchoredResize: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.windowResizeAnchor(.top)
        } else {
            content
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private func byteCount(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}
