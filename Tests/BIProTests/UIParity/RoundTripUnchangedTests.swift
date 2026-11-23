import Foundation
import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — RoundTripUnchanged (SC-003, SC-007, T085)")
@MainActor
struct RoundTripUnchangedTests {
    private static func findNhom6URL() -> URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], !env.isEmpty, fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        for rel in ["bipro-golden/Nhom6_work.pbix", "Nhom6_Dashboard.pbix", "Nhom6_work.pbix"] {
            let candidate = downloads.appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @Test func openingAndBrowsingAllRibbonsAndViewsDoesNotDirtyOrAlterBytes() throws {
        let dir = SyntheticReport.temporaryDirectory("h6-roundtrip-synth")
        let url = try SyntheticReport.make(in: dir, withChart: true)
        let beforeBytes = try Data(contentsOf: url)

        let workspace = try Workspace(data: beforeBytes)
        let state = DocumentState(workspace: workspace, fileName: url.lastPathComponent, fileURL: url)

        // Duyệt qua đủ 5 chế độ và mọi tab Ribbon nhưng không sửa gì
        for mode in Rail.modes {
            state.mode = mode
            for tab in state.tabs where tab != .file {
                state.selectRibbonTab(tab)
            }
        }
        state.mode = .report
        state.showBackstage = true
        state.showBackstage = false

        #expect(state.layout.isDirty == false, "Chỉ duyệt UI Phase H không được đánh dấu tài liệu dirty")
        #expect(state.save() == true)

        let afterBytes = try Data(contentsOf: url)
        #expect(afterBytes == beforeBytes, "Nội dung byte .pbix phải giữ nguyên 100% khi không sửa")
    }

    @Test func nhom6RealFileRemainsByteIdenticalAfterOpeningAndBrowsingUI() throws {
        guard let sourceURL = Self.findNhom6URL() else {
            return
        }
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("bipro-h6-nhom6-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let copyURL = tempDir.appendingPathComponent("Nhom6_copy.pbix")
        try fm.copyItem(at: sourceURL, to: copyURL)
        let beforeBytes = try Data(contentsOf: copyURL)

        let workspace = try Workspace(data: beforeBytes)
        let state = DocumentState(workspace: workspace, fileName: copyURL.lastPathComponent, fileURL: copyURL)

        for mode in Rail.modes {
            state.mode = mode
            for tab in state.tabs where tab != .file {
                state.selectRibbonTab(tab)
            }
        }
        state.mode = .report

        #expect(state.layout.isDirty == false)
        #expect(state.save() == true)

        let afterBytes = try Data(contentsOf: copyURL)
        #expect(afterBytes == beforeBytes, "Nhom6 .pbix phải giữ nguyên từng byte sau khi duyệt UI v1.3.0")
    }
}
}
