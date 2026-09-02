import AppKit
import Foundation
import XCTest
@testable import Slopup

final class StorageServiceTests: XCTestCase {
    func testEveryProviderLogoIsBundledAndReadable() {
        for tool in AgentCatalog.tools {
            let url = Bundle.module.url(forResource: tool.id.rawValue, withExtension: "svg")
            XCTAssertNotNil(url, "Missing logo for \(tool.name)")
            XCTAssertNotNil(url.flatMap(NSImage.init(contentsOf:)), "Unreadable logo for \(tool.name)")
        }
    }

    func testScanAndTTLDeletionStayInsideTheAllowlist() throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("SlopupTests-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: home) }

        let location = StorageLocation(label: "Sessions", relativePath: ".agent/sessions", retentionStrategy: .files)
        let tool = AgentTool(id: .codex, name: "Test Agent", subtitle: "", symbol: "terminal", color: 0, locations: [location])
        let root = home.appendingPathComponent(location.relativePath, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        let expired = root.appendingPathComponent("expired.jsonl")
        let current = root.appendingPathComponent("current.jsonl")
        try Data(repeating: 1, count: 2_048).write(to: expired)
        try Data(repeating: 2, count: 1_024).write(to: current)
        try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)], ofItemAtPath: expired.path)

        let service = StorageService(homeDirectory: home)
        let scan = service.scan(tool)
        XCTAssertTrue(scan.isFound)
        XCTAssertEqual(scan.itemCount, 2)
        XCTAssertGreaterThan(scan.bytes, 0)

        let result = try service.deleteExpiredData(for: tool, before: Date(timeIntervalSinceNow: -14 * 86_400))
        XCTAssertEqual(result.itemCount, 1)
        XCTAssertFalse(manager.fileExists(atPath: expired.path))
        XCTAssertTrue(manager.fileExists(atPath: current.path))

        let unsafeLocation = StorageLocation(label: "Outside", relativePath: "../outside", retentionStrategy: .files)
        let unsafeTool = AgentTool(id: .claude, name: "Unsafe", subtitle: "", symbol: "xmark", color: 0, locations: [unsafeLocation])
        XCTAssertThrowsError(try service.validatedURL(for: unsafeLocation, in: unsafeTool))
    }
}
