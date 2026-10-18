import Foundation
import Testing
@testable import BarnOwl

/// The map of the disk can take a hundred megabytes; it's let go once the
/// Barn has been closed a while, but never while the basket needs it.
@MainActor
struct BarnScanMemoryTests {
    private func scanned(_ barn: BarnModel) async throws -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: "barn-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "inside"), withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: folder.appending(path: "inside/big.bin"))
        barn.startScan(root: folder.path)
        for _ in 0..<100 {
            if case .done = barn.scan { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard case .done = barn.scan else { throw CancellationError() }
        return folder.path
    }

    @Test func forgetsTheMap() async throws {
        let barn = BarnModel()
        let folder = try await scanned(barn)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        barn.forgetScan()
        guard case .idle = barn.scan else { Issue.record("still holding the scan"); return }
    }

    @Test func keepsTheMapWhileTheBasketNeedsIt() async throws {
        let barn = BarnModel()
        let folder = try await scanned(barn)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        barn.basket = [BarnModel.Item(path: folder + "/inside/big.bin", name: "big.bin", size: 2_000_000, modified: nil)]
        barn.forgetScan()
        guard case .done = barn.scan else { Issue.record("let go of a scan the basket needs"); return }
    }
}
