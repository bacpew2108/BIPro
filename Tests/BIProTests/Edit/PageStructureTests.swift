import Foundation
import Testing
@testable import BIPro

@Suite struct PageStructureTests {
    // MARK: (a) tên mặc định

    @Test func defaultNameIsTheLargestPageNumberPlusOne() {
        #expect(PageStructure.nextDefaultName(existing: ["D1", "D2"]) == "Page 1")
        #expect(PageStructure.nextDefaultName(existing: ["D1", "Page 1"]) == "Page 2")
        #expect(PageStructure.nextDefaultName(existing: ["Page 1", "Page 2", "Page 5"]) == "Page 6")
        // khoảng trống: số lớn nhất cộng một (không bao giờ trùng tên mặc định)
        #expect(PageStructure.nextDefaultName(existing: ["Page 2"]) == "Page 3")
        // không đúng dạng thì không tính
        #expect(PageStructure.nextDefaultName(existing: ["Page", "Page 1x", "page 4", "Page 3 (2)"]) == "Page 1")
    }

    // MARK: (e) tên hợp lệ

    @Test func namesAreTrimmedAndLengthChecked() {
        #expect(PageStructure.validatedName("  Doanh thu  ") == .success("Doanh thu"))
        guard case .failure(let empty) = PageStructure.validatedName("   \n") else { Issue.record("rỗng phải bị từ chối"); return }
        #expect(empty.contains("để trống"))
        let long = String(repeating: "a", count: 101)
        guard case .failure(let tooLong) = PageStructure.validatedName(long) else { Issue.record("quá dài phải bị từ chối"); return }
        #expect(tooLong.contains("100"))
        #expect(PageStructure.validatedName(String(repeating: "ê", count: 100)) == .success(String(repeating: "ê", count: 100)))
        #expect(PageStructure.validatedName("Tên \"lạ\" · Việt") == .success("Tên \"lạ\" · Việt"))
    }

    // MARK: (b) trang liền kề

    @Test func theNeighbourAfterRemovingIsTheRightOneThenTheLeftOne() {
        let order = ["a", "b", "c", "d"]
        #expect(PageStructure.neighbour(afterRemoving: "b", in: order) == "c")
        #expect(PageStructure.neighbour(afterRemoving: "a", in: order) == "b")
        #expect(PageStructure.neighbour(afterRemoving: "d", in: order) == "c")
        #expect(PageStructure.neighbour(afterRemoving: "a", in: ["a"]) == nil)
        #expect(PageStructure.neighbour(afterRemoving: "z", in: order) == nil)
    }

    // MARK: (c) từ chối xoá

    @Test func removalIsRefusedForTheLastPageAndForNavigationButtons() {
        #expect(PageStructure.removalRefusal(pageCount: 1, navigationButtons: [])?.contains("ít nhất một trang") == true)
        #expect(PageStructure.removalRefusal(pageCount: 3, navigationButtons: []) == nil)
        let reason = PageStructure.removalRefusal(pageCount: 3, navigationButtons: ["Về D2", "Sang chi nhánh"])
        #expect(reason?.contains("Về D2") == true && reason?.contains("Sang chi nhánh") == true && reason?.contains("chưa kiểm") == true)
    }

    // MARK: (d) tác động lên bookmark

    @Test func bookmarkImpactSplitsRemovedAndTrimmed() {
        let bookmarks = [
            BookmarkInfo(name: "onlyD1", activeSection: "d1", sections: ["d1"]),
            BookmarkInfo(name: "both", activeSection: "d2", sections: ["d1", "d2"]),
            BookmarkInfo(name: "activeGone", activeSection: "d1", sections: ["d1", "d2"]),
            BookmarkInfo(name: "unrelated", activeSection: "d3", sections: ["d3"]),
            BookmarkInfo(name: "noSections", activeSection: nil, sections: []),
        ]
        let impact = PageStructure.bookmarkImpact(removing: ["d1"], bookmarks: bookmarks)
        #expect(impact.removed == ["onlyD1", "activeGone"])
        #expect(impact.trimmed == ["both": ["d1"]])
        #expect(PageStructure.bookmarkImpact(removing: ["d9"], bookmarks: bookmarks) == BookmarkImpact())
        #expect(PageStructure.bookmarkImpact(removing: [], bookmarks: bookmarks) == BookmarkImpact())
        // trang xoá nhiều cái một lúc
        #expect(PageStructure.bookmarkImpact(removing: ["d1", "d2"], bookmarks: bookmarks).removed == ["onlyD1", "both", "activeGone"])
    }

    @Test func bookmarkInfoIsReadFromTheJSON() throws {
        let json = Data(#"{"name":"b1","displayName":"B","explorationState":{"activeSection":"d2","sections":{"d1":{},"d2":{}}}}"#.utf8)
        let info = try #require(BookmarkInfo(json: json))
        #expect(info == BookmarkInfo(name: "b1", activeSection: "d2", sections: ["d1", "d2"]))
        #expect(BookmarkInfo(json: Data("oops".utf8)) == nil)
        #expect(BookmarkInfo(json: Data(#"{"displayName":"x"}"#.utf8)) == nil)   // không có name
    }

    // MARK: (f) bất biến

    @Test func orderInvariantsHold() {
        let file: Set<String> = ["a", "b"]
        var structure = PageStructure(order: ["a", "b"])
        #expect(structure.isConsistent(fileIDs: file))
        structure.order = []
        #expect(!structure.isConsistent(fileIDs: file))
        structure.order = ["a", "a"]
        #expect(!structure.isConsistent(fileIDs: file))
        structure = PageStructure(order: ["a", "b"])
        structure.removed = ["a"]
        #expect(!structure.isConsistent(fileIDs: file))   // trang đã xoá vẫn nằm trong order
        structure.order = ["b"]
        #expect(structure.isConsistent(fileIDs: file))
        structure.order = ["b", "n"]
        #expect(!structure.isConsistent(fileIDs: file))   // "n" không của file, cũng không trong created
        structure.created["n"] = NewPage(id: "n", displayName: "Page 1", pageJSON: Data(), sourcePage: nil, width: 1920, height: 1080)
        #expect(structure.isConsistent(fileIDs: file))
        structure.order = ["n"]
        #expect(!structure.isConsistent(fileIDs: file))   // trang "b" của file vừa mất khỏi order mà không nằm trong removed
    }

    @Test func aFreshStructureIsClean() {
        let structure = PageStructure(order: ["a", "b"])
        #expect(!structure.changesStructure(comparedTo: ["a", "b"]))
        var moved = structure; moved.order = ["b", "a"]
        #expect(moved.changesStructure(comparedTo: ["a", "b"]))
        var renamed = structure; renamed.renamed["a"] = "A"
        #expect(renamed.changesStructure(comparedTo: ["a", "b"]))
        var removed = structure; removed.order = ["b"]; removed.removed = ["a"]
        #expect(removed.changesStructure(comparedTo: ["a", "b"]))
    }
}
