import AppKit
import Foundation
import Observation
import ServiceManagement

struct AppNotice: Identifiable {
    enum Kind {
        case success
        case warning
        case error
    }

    let id = UUID()
    let kind: Kind
    let message: String
}

@Observable
@MainActor
final class CleanupStore {
    static let shared = CleanupStore()

    var snapshots: [ToolStats]
    var isScanning = false
    var cleaningTools: Set<AgentTool.ID> = []
    var lastScan: Date?
    var lastCleanupDate: Date?
    var lastCleanupMessage: String?
    var launchAtLogin: Bool
    var notice: AppNotice?

    @ObservationIgnored private let service: StorageService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?

    private init(
        service: StorageService = StorageService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        snapshots = AgentCatalog.tools.map { .empty(for: $0, homeDirectory: service.homeDirectory) }
        lastCleanupDate = defaults.object(forKey: "lastCleanupDate") as? Date
        lastCleanupMessage = defaults.string(forKey: "lastCleanupMessage")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    deinit {
        schedulerTask?.cancel()
    }

    var totalBytes: Int64 {
        snapshots.reduce(0) { $0 + $1.bytes }
    }

    var foundToolCount: Int {
        snapshots.filter(\.isFound).count
    }

    var isCleaningAll: Bool {
        !cleaningTools.isEmpty && cleaningTools.count == snapshots.filter(\.isFound).count
    }

    func start() {
        guard schedulerTask == nil else { return }
        schedulerTask = Task { [weak self] in
            guard let self else { return }
            await refresh()
            await runScheduledCleanup()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    return
                }
                await runScheduledCleanup()
            }
        }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let service = service
        let tools = AgentCatalog.tools
        snapshots = await Task.detached(priority: .utility) {
            tools.map { service.scan($0) }
        }.value
        lastScan = Date()
    }

    func retentionDays(for tool: AgentTool.ID) -> Int {
        defaults.integer(forKey: "retention.\(tool.rawValue)")
    }

    func setRetentionDays(_ days: Int, for tool: AgentTool.ID) {
        guard [0, 7, 14, 30, 90].contains(days) else { return }
        defaults.set(days, forKey: "retention.\(tool.rawValue)")
        notice = AppNotice(
            kind: days == 0 ? .warning : .success,
            message: days == 0 ? "Automatic cleanup disabled." : "\(toolName(tool)) will keep the latest \(days) days."
        )
    }

    func cleanNow(_ tool: AgentTool) async {
        guard !cleaningTools.contains(tool.id) else { return }
        cleaningTools.insert(tool.id)
        defer { cleaningTools.remove(tool.id) }

        let service = service
        do {
            let result = try await Task.detached(priority: .utility) {
                try service.trashAllData(for: tool)
            }.value
            record(result, action: "Moved", suffix: "to Trash. Empty Trash to reclaim the space.")
        } catch {
            notice = AppNotice(kind: .error, message: error.localizedDescription)
        }
        await refresh()
    }

    func cleanAllNow() async {
        let tools = snapshots.filter(\.isFound).map(\.tool)
        guard !tools.isEmpty, cleaningTools.isEmpty else { return }
        cleaningTools = Set(tools.map(\.id))
        defer { cleaningTools.removeAll() }

        let service = service
        do {
            let result = try await Task.detached(priority: .utility) {
                var combined = CleanupResult()
                for tool in tools {
                    let next = try service.trashAllData(for: tool)
                    combined.bytes += next.bytes
                    combined.itemCount += next.itemCount
                    combined.errors += next.errors
                }
                return combined
            }.value
            record(result, action: "Moved", suffix: "to Trash. Empty Trash to reclaim the space.")
        } catch {
            notice = AppNotice(kind: .error, message: error.localizedDescription)
        }
        await refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            notice = AppNotice(kind: .success, message: launchAtLogin ? "Slopup will launch when you log in." : "Launch at Login disabled.")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            notice = AppNotice(kind: .error, message: error.localizedDescription)
        }
    }

    func reveal(_ location: LocationStats) {
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func runScheduledCleanup() async {
        let jobs = AgentCatalog.tools.compactMap { tool -> (AgentTool, Int)? in
            let days = retentionDays(for: tool.id)
            return days > 0 ? (tool, days) : nil
        }
        guard !jobs.isEmpty, cleaningTools.isEmpty else { return }

        cleaningTools = Set(jobs.map { $0.0.id })
        defer { cleaningTools.removeAll() }
        let service = service
        let now = Date()

        do {
            let result = try await Task.detached(priority: .utility) {
                var combined = CleanupResult()
                for (tool, days) in jobs {
                    let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
                    let next = try service.deleteExpiredData(for: tool, before: cutoff)
                    combined.bytes += next.bytes
                    combined.itemCount += next.itemCount
                    combined.errors += next.errors
                }
                return combined
            }.value

            if result.itemCount > 0 || !result.errors.isEmpty {
                record(result, action: "Deleted", suffix: "with auto-clean.")
                await refresh()
            }
        } catch {
            notice = AppNotice(kind: .error, message: error.localizedDescription)
        }
    }

    private func record(_ result: CleanupResult, action: String, suffix: String) {
        let size = ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)
        let issueText = result.errors.isEmpty ? "" : " \(itemCount(result.errors.count)) could not be cleaned."
        let message = "\(action) \(size) across \(itemCount(result.itemCount)) \(suffix)\(issueText)"
        lastCleanupDate = Date()
        lastCleanupMessage = message
        defaults.set(lastCleanupDate, forKey: "lastCleanupDate")
        defaults.set(message, forKey: "lastCleanupMessage")
        notice = AppNotice(kind: result.errors.isEmpty ? .success : .warning, message: message)
    }

    private func itemCount(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    private func toolName(_ id: AgentTool.ID) -> String {
        AgentCatalog.tools.first(where: { $0.id == id })?.name ?? "This tool"
    }
}
