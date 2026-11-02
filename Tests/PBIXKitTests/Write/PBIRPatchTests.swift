import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRPatchTests {
    static let sample = #"{"name":"v1","visual":{"visualType":"card","visualContainerObjects":{"title":[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"text":{"expr":{"Literal":{"Value":"'Tiêu đề cũ'"}}}}}]},"drillFilterOtherVisuals":true}}"#

    static let untitled = #"{"name":"v2","visual":{"visualType":"card","visualContainerObjects":{"title":[{"properties":{"show":{"expr":{"Literal":{"Value":"false"}}}}}]}}}"#

    @Test func setThenReadReturnsNewTitle() throws {
        let patched = try PBIRPatch.setVisualTitle(in: Data(Self.sample.utf8), title: "Doanh thu theo tháng (triệu $)")
        #expect(try PBIRPatch.visualTitle(in: patched) == "Doanh thu theo tháng (triệu $)")
    }

    @Test func onlyTheTitleLiteralChangesBytes() throws {
        let patched = try PBIRPatch.setVisualTitle(in: Data(Self.sample.utf8), title: "Mới")
        let expected = Self.sample.replacingOccurrences(of: "'Tiêu đề cũ'", with: "'Mới'")
        #expect(String(decoding: patched, as: UTF8.self) == expected)
    }

    @Test func titleWithQuotesAndControlCharactersRoundTrips() throws {
        let title = "It's \"quoted\" \\ back\tslash\nnewline"
        let patched = try PBIRPatch.setVisualTitle(in: Data(Self.sample.utf8), title: title)
        #expect(try PBIRPatch.visualTitle(in: patched) == title)
        // The document still parses and the sibling keys are untouched.
        let root = try JSONSerialization.jsonObject(with: patched) as? [String: Any]
        let visual = root?["visual"] as? [String: Any]
        #expect(visual?["visualType"] as? String == "card")
        #expect(visual?["drillFilterOtherVisuals"] as? Bool == true)
        #expect(root?["name"] as? String == "v1")
    }

    @Test func visualWithoutTitleReadsNilAndSetThrowsInvalid() throws {
        let json = Data(Self.untitled.utf8)
        #expect(try PBIRPatch.visualTitle(in: json) == nil)
        expectInvalid { try PBIRPatch.setVisualTitle(in: json, title: "x") }
    }

    @Test func nonObjectJSONThrowsInvalid() {
        expectInvalid { try PBIRPatch.setVisualTitle(in: Data("[1,2]".utf8), title: "x") }
    }

    private func expectInvalid(_ body: () throws -> Data) {
        do {
            _ = try body()
            Issue.record("expected WriteError.invalid, but the call succeeded")
        } catch let error as WriteError {
            if case .invalid = error { return }
            Issue.record("expected WriteError.invalid, got \(error)")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

@Suite(.enabled(if: WP2Fixture.exists(WP2Fixture.nhom6))) struct PBIRNhom6Tests {
    /// The first visual of Nhom6 that has title text, with its path inside the archive.
    static func titledVisual(in archive: ZipArchive) throws -> (path: String, json: Data, title: String)? {
        for entry in archive.entries where entry.path.hasSuffix("/visual.json") {
            let json = try archive.read(entry)
            if let title = try PBIRPatch.visualTitle(in: json) {
                return (entry.path, json, title)
            }
        }
        return nil
    }

    @Test func readsAndPatchesARealVisualTitle() throws {
        let archive = try ZipArchive(url: WP2Fixture.nhom6)
        let foundTarget = try Self.titledVisual(in: archive)
        let target = try #require(foundTarget)
        let newTitle = "WP2 thử nghiệm: " + target.title
        let patched = try PBIRPatch.setVisualTitle(in: target.json, title: newTitle)
        #expect(try PBIRPatch.visualTitle(in: patched) == newTitle)

        // Only the title literal changes. Skip the byte check if the old title needs JSON escaping.
        let plainTitle = !target.title.contains("\"") && !target.title.contains("\\") && !target.title.contains("'")
        if plainTitle {
            let expected = String(decoding: target.json, as: UTF8.self)
                .replacingOccurrences(of: "\"'\(target.title)'\"", with: "\"'\(newTitle)'\"")
            #expect(String(decoding: patched, as: UTF8.self) == expected)
        }
    }

    @Test func untitledVisualInNhom6ThrowsInvalid() throws {
        let archive = try ZipArchive(url: WP2Fixture.nhom6)
        for entry in archive.entries where entry.path.hasSuffix("/visual.json") {
            let json = try archive.read(entry)
            if try PBIRPatch.visualTitle(in: json) == nil {
                do {
                    _ = try PBIRPatch.setVisualTitle(in: json, title: "x")
                    Issue.record("expected WriteError.invalid for \(entry.path)")
                } catch let error as WriteError {
                    if case .invalid = error { return }
                    Issue.record("expected .invalid, got \(error)")
                }
                return
            }
        }
        // Nhom6 has 112 visuals without a title; reaching here means none were found.
        Issue.record("no untitled visual found in Nhom6")
    }

    /// T1 end to end: one visual patched, every other member copied raw, then reopened as a PBIX.
    @Test func patchedReportOpensAsPBIX() throws {
        let archive = try ZipArchive(url: WP2Fixture.nhom6)
        let foundTarget = try Self.titledVisual(in: archive)
        let target = try #require(foundTarget)
        let newTitle = "WP2 thử nghiệm: " + target.title
        let patched = try PBIRPatch.setVisualTitle(in: target.json, title: newTitle)

        let members: [(path: String, source: ZipWriter.Source)] = archive.entries.map { entry in
            entry.path == target.path
                ? (path: entry.path, source: .bytes(patched, method: 8))
                : (path: entry.path, source: .rawCopy(archive, entry))
        }
        let data = try ZipWriter.write(members)
        let url = try WP2Fixture.writeOutput(data, name: "nhom6.title.pbix")
        print("WP2 wrote \(url.path) (\(data.count) bytes)")

        let pbix = try PBIXFile(data: data)
        #expect(pbix.reportFormat == .pbir)
        #expect(pbix.archive.entries.map(\.path) == archive.entries.map(\.path))
        #expect(pbix.hasDataModel)

        let readBack = try pbix.archive.read(target.path)
        #expect(try PBIRPatch.visualTitle(in: readBack) == newTitle)

        let dataModel = try #require(pbix.archive.entry("DataModel"))
        #expect(dataModel.method == 0)
        let entryOriginalmodel = try #require(archive.entry("DataModel"))
        let originalModelOptional = try archive.storedSlice(entryOriginalmodel)
        let originalModel = try #require(originalModelOptional)
        #expect(try pbix.archive.storedSlice(dataModel) == originalModel)
    }
}
