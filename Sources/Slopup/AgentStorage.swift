import Foundation

enum RetentionStrategy: Hashable, Sendable {
    case files
    case topLevelEntries
}

struct StorageLocation: Identifiable, Hashable, Sendable {
    var id: String { relativePath }

    let label: String
    let relativePath: String
    let retentionStrategy: RetentionStrategy
}

struct AgentTool: Identifiable, Hashable, Sendable {
    enum ID: String, Codable, CaseIterable, Sendable {
        case codex
        case claude
        case cursor
        case windsurf
        case cline
        case continueDev
        case aider
    }

    let id: ID
    let name: String
    let subtitle: String
    let symbol: String
    let color: UInt32
    let locations: [StorageLocation]
}

enum AgentCatalog {
    static let tools: [AgentTool] = [
        AgentTool(
            id: .codex,
            name: "Codex",
            subtitle: "Sessions and shell snapshots",
            symbol: "terminal",
            color: 0x10A37F,
            locations: [
                StorageLocation(label: "Sessions", relativePath: ".codex/sessions", retentionStrategy: .files),
                StorageLocation(label: "Archived sessions", relativePath: ".codex/archived_sessions", retentionStrategy: .files),
                StorageLocation(label: "Shell snapshots", relativePath: ".codex/shell_snapshots", retentionStrategy: .files),
                StorageLocation(label: "Logs", relativePath: ".codex/log", retentionStrategy: .files)
            ]
        ),
        AgentTool(
            id: .claude,
            name: "Claude Code",
            subtitle: "Projects, history, snapshots, and logs",
            symbol: "sparkles",
            color: 0xD97757,
            locations: [
                StorageLocation(label: "Project sessions", relativePath: ".claude/projects", retentionStrategy: .files),
                StorageLocation(label: "File history", relativePath: ".claude/file-history", retentionStrategy: .topLevelEntries),
                StorageLocation(label: "Session environments", relativePath: ".claude/session-env", retentionStrategy: .files),
                StorageLocation(label: "Shell snapshots", relativePath: ".claude/shell-snapshots", retentionStrategy: .files),
                StorageLocation(label: "Debug logs", relativePath: ".claude/debug", retentionStrategy: .files),
                StorageLocation(label: "Prompt history", relativePath: ".claude/history.jsonl", retentionStrategy: .files)
            ]
        ),
        AgentTool(
            id: .cursor,
            name: "Cursor",
            subtitle: "Agent projects and workspace state",
            symbol: "cursorarrow.rays",
            color: 0x7C6CF2,
            locations: [
                StorageLocation(label: "Agent projects", relativePath: ".cursor/projects", retentionStrategy: .files),
                StorageLocation(label: "Workspace state", relativePath: "Library/Application Support/Cursor/User/workspaceStorage", retentionStrategy: .topLevelEntries),
                StorageLocation(label: "Logs", relativePath: "Library/Application Support/Cursor/logs", retentionStrategy: .files)
            ]
        ),
        AgentTool(
            id: .windsurf,
            name: "Windsurf",
            subtitle: "Cascade sessions and workspace state",
            symbol: "wind",
            color: 0x00A9A5,
            locations: [
                StorageLocation(label: "Cascade sessions", relativePath: ".codeium/windsurf/cascade", retentionStrategy: .files),
                StorageLocation(label: "Workspace state", relativePath: "Library/Application Support/Windsurf/User/workspaceStorage", retentionStrategy: .topLevelEntries),
                StorageLocation(label: "Logs", relativePath: "Library/Application Support/Windsurf/logs", retentionStrategy: .files)
            ]
        ),
        AgentTool(
            id: .cline,
            name: "Cline",
            subtitle: "Task history from supported editors",
            symbol: "chevron.left.forwardslash.chevron.right",
            color: 0xEF4444,
            locations: [
                StorageLocation(label: "VS Code tasks", relativePath: "Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks", retentionStrategy: .topLevelEntries),
                StorageLocation(label: "Cursor tasks", relativePath: "Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks", retentionStrategy: .topLevelEntries),
                StorageLocation(label: "Windsurf tasks", relativePath: "Library/Application Support/Windsurf/User/globalStorage/saoudrizwan.claude-dev/tasks", retentionStrategy: .topLevelEntries),
                StorageLocation(label: "CLI tasks", relativePath: ".cline/data/tasks", retentionStrategy: .topLevelEntries)
            ]
        ),
        AgentTool(
            id: .continueDev,
            name: "Continue",
            subtitle: "Local chat sessions",
            symbol: "arrow.forward.square",
            color: 0x2563EB,
            locations: [
                StorageLocation(label: "Sessions", relativePath: ".continue/sessions", retentionStrategy: .files)
            ]
        ),
        AgentTool(
            id: .aider,
            name: "Aider",
            subtitle: "Home-directory chat history",
            symbol: "wand.and.stars",
            color: 0xA855F7,
            locations: [
                StorageLocation(label: "Chat history", relativePath: ".aider.chat.history.md", retentionStrategy: .files),
                StorageLocation(label: "Input history", relativePath: ".aider.input.history", retentionStrategy: .files)
            ]
        )
    ]
}

struct LocationStats: Identifiable, Sendable {
    var id: String { location.id }

    let location: StorageLocation
    let url: URL
    let exists: Bool
    let bytes: Int64
    let itemCount: Int
    let latestActivity: Date?
    let error: String?
}

struct ToolStats: Identifiable, Sendable {
    var id: AgentTool.ID { tool.id }
    var bytes: Int64 { locations.reduce(0) { $0 + $1.bytes } }
    var itemCount: Int { locations.reduce(0) { $0 + $1.itemCount } }
    var isFound: Bool { locations.contains(where: \.exists) }
    var latestActivity: Date? { locations.compactMap(\.latestActivity).max() }

    let tool: AgentTool
    let locations: [LocationStats]

    static func empty(for tool: AgentTool, homeDirectory: URL) -> ToolStats {
        ToolStats(
            tool: tool,
            locations: tool.locations.map {
                LocationStats(
                    location: $0,
                    url: homeDirectory.appendingPathComponent($0.relativePath),
                    exists: false,
                    bytes: 0,
                    itemCount: 0,
                    latestActivity: nil,
                    error: nil
                )
            }
        )
    }
}

struct CleanupResult: Sendable {
    var bytes: Int64 = 0
    var itemCount = 0
    var errors: [String] = []
}

enum StorageError: LocalizedError {
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            "Refused to access a path outside the cleanup allowlist: \(path)"
        }
    }
}

struct StorageService: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    func scan(_ tool: AgentTool) -> ToolStats {
        ToolStats(tool: tool, locations: tool.locations.map { scan($0, in: tool) })
    }

    func trashAllData(for tool: AgentTool) throws -> CleanupResult {
        let manager = FileManager.default
        let roots = try tool.locations.map { ($0, try validatedURL(for: $0, in: tool)) }
        var result = CleanupResult()

        for (location, root) in roots where manager.fileExists(atPath: root.path) {
            do {
                let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else {
                    result.errors.append("\(location.label) is a symbolic link")
                    continue
                }

                let before = scan(location, in: tool)
                if values.isDirectory == true {
                    for child in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                        guard isDescendant(child, of: root) else { continue }
                        do {
                            try manager.trashItem(at: child, resultingItemURL: nil)
                            result.itemCount += 1
                        } catch {
                            result.errors.append("\(child.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                } else {
                    try manager.trashItem(at: root, resultingItemURL: nil)
                    result.itemCount += 1
                }
                result.bytes += before.bytes
            } catch {
                result.errors.append("\(location.label): \(error.localizedDescription)")
            }
        }

        return result
    }

    func deleteExpiredData(for tool: AgentTool, before cutoff: Date) throws -> CleanupResult {
        let manager = FileManager.default
        let roots = try tool.locations.map { ($0, try validatedURL(for: $0, in: tool)) }
        var result = CleanupResult()

        for (location, root) in roots where manager.fileExists(atPath: root.path) {
            do {
                let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard rootValues.isSymbolicLink != true else {
                    result.errors.append("\(location.label) is a symbolic link")
                    continue
                }

                if rootValues.isDirectory != true {
                    if (rootValues.contentModificationDate ?? .distantFuture) < cutoff {
                        result.bytes += allocatedBytes(at: root)
                        try manager.removeItem(at: root)
                        result.itemCount += 1
                    }
                    continue
                }

                switch location.retentionStrategy {
                case .files:
                    let expired = files(under: root, modifiedBefore: cutoff)
                    for file in expired {
                        do {
                            result.bytes += allocatedBytes(at: file)
                            try manager.removeItem(at: file)
                            result.itemCount += 1
                        } catch {
                            result.errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                    pruneEmptyDirectories(under: root)

                case .topLevelEntries:
                    for child in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                        guard isDescendant(child, of: root) else { continue }
                        let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey])
                        guard values.isSymbolicLink != true else { continue }
                        let stats = scanTree(at: child)
                        guard (stats.latestActivity ?? .distantFuture) < cutoff else { continue }
                        do {
                            result.bytes += stats.bytes
                            try manager.removeItem(at: child)
                            result.itemCount += 1
                        } catch {
                            result.errors.append("\(child.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                result.errors.append("\(location.label): \(error.localizedDescription)")
            }
        }

        return result
    }

    func validatedURL(for location: StorageLocation, in tool: AgentTool) throws -> URL {
        guard tool.locations.contains(location), !location.relativePath.hasPrefix("/") else {
            throw StorageError.unsafePath(location.relativePath)
        }

        let candidate = homeDirectory.appendingPathComponent(location.relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(homeDirectory.path + "/") else {
            throw StorageError.unsafePath(candidate.path)
        }
        return candidate
    }

    private func scan(_ location: StorageLocation, in tool: AgentTool) -> LocationStats {
        let url: URL
        do {
            url = try validatedURL(for: location, in: tool)
        } catch {
            return LocationStats(location: location, url: homeDirectory, exists: false, bytes: 0, itemCount: 0, latestActivity: nil, error: error.localizedDescription)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return LocationStats(location: location, url: url, exists: false, bytes: 0, itemCount: 0, latestActivity: nil, error: nil)
        }

        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                return LocationStats(location: location, url: url, exists: true, bytes: 0, itemCount: 0, latestActivity: nil, error: "Symbolic links are skipped")
            }
            let stats = scanTree(at: url)
            return LocationStats(location: location, url: url, exists: true, bytes: stats.bytes, itemCount: stats.itemCount, latestActivity: stats.latestActivity, error: stats.error)
        } catch {
            return LocationStats(location: location, url: url, exists: true, bytes: 0, itemCount: 0, latestActivity: nil, error: error.localizedDescription)
        }
    }

    private func scanTree(at root: URL) -> (bytes: Int64, itemCount: Int, latestActivity: Date?, error: String?) {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        var bytes: Int64 = 0
        var itemCount = 0
        var latestActivity: Date?
        var firstError: String?

        guard let rootValues = try? root.resourceValues(forKeys: keys) else {
            return (0, 0, nil, "Unable to read this location")
        }
        guard rootValues.isSymbolicLink != true else { return (0, 0, nil, "Symbolic links are skipped") }

        if rootValues.isRegularFile == true {
            return (
                Int64(rootValues.fileAllocatedSize ?? rootValues.fileSize ?? 0),
                1,
                rootValues.contentModificationDate,
                nil
            )
        }
        let rootModificationDate = rootValues.contentModificationDate

        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                firstError = firstError ?? "\(url.lastPathComponent): \(error.localizedDescription)"
                return true
            }
        ) else {
            return (0, 0, latestActivity, "Unable to enumerate this location")
        }

        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                if values.isRegularFile == true {
                    bytes += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
                    itemCount += 1
                    if let date = values.contentModificationDate {
                        latestActivity = max(latestActivity ?? date, date)
                    }
                }
            } catch {
                firstError = firstError ?? "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        return (bytes, itemCount, latestActivity ?? rootModificationDate, firstError)
    }

    private func files(under root: URL, modifiedBefore cutoff: Date) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isRegularFile == true, (values.contentModificationDate ?? .distantFuture) < cutoff {
                matches.append(url)
            }
        }
        return matches
    }

    private func pruneEmptyDirectories(under root: URL) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        var directories: [URL] = []

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory == true else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
            } else {
                directories.append(url)
            }
        }

        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            guard (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func allocatedBytes(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
        return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func isDescendant(_ url: URL, of root: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }
}
