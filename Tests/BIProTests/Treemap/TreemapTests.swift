import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct TreemapTests {

    // MARK: - 5. Squarify: diện tích, tỉ lệ, không chồng, thứ tự, 40 giá trị seed
    @Test func squarifyProperties() {
        let frame = CGRect(x: 0, y: 0, width: 640, height: 380)
        let totalArea = Double(frame.width * frame.height)

        // 1. Kiểm tra cơ bản với mảng có số 0 và âm
        let values: [Double] = [100.0, 0.0, 50.0, -10.0, 25.0, 25.0]
        let rects = TreemapLayout.squarify(values: values, in: frame)

        #expect(rects.count == values.count)
        // Ô số 0 và âm phải là .zero
        #expect(rects[1] == .zero)
        #expect(rects[3] == .zero)

        // Tổng diện tích các ô dương = diện tích khung (sai số 1e-6)
        let sumArea = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(sumArea - totalArea) < 1e-6)

        // Diện tích tỉ lệ với giá trị (100: 50%, 50: 25%, 25: 12.5%, 25: 12.5%)
        let totalVal = 100.0 + 50.0 + 25.0 + 25.0
        #expect(abs(Double(rects[0].width * rects[0].height) - totalArea * (100.0 / totalVal)) < 1e-6)
        #expect(abs(Double(rects[2].width * rects[2].height) - totalArea * (50.0 / totalVal)) < 1e-6)
        #expect(abs(Double(rects[4].width * rects[4].height) - totalArea * (25.0 / totalVal)) < 1e-6)
        #expect(abs(Double(rects[5].width * rects[5].height) - totalArea * (25.0 / totalVal)) < 1e-6)

        // Mọi ô nằm trong khung
        for (i, r) in rects.enumerated() {
            if values[i] > 0 {
                #expect(r.minX >= frame.minX - 1e-6)
                #expect(r.minY >= frame.minY - 1e-6)
                #expect(r.maxX <= frame.maxX + 1e-6)
                #expect(r.maxY <= frame.maxY + 1e-6)
            }
        }

        // Không có 2 ô nào chồng nhau (giao nhau diện tích ≈ 0)
        for i in 0..<rects.count {
            guard values[i] > 0 else { continue }
            for j in (i + 1)..<rects.count {
                guard values[j] > 0 else { continue }
                let inter = rects[i].intersection(rects[j])
                let interArea = inter.isNull ? 0.0 : inter.width * inter.height
                #expect(interArea < 1e-5)
            }
        }

        // 2. 40 giá trị ngẫu nhiên cố định (seed)
        // Tạo 40 giá trị từ bộ sinh số giả ngẫu nhiên LCG với seed cố định
        var seed: UInt64 = 123456789
        func nextRand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let val = Double((seed >> 32) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
            return 10.0 + val * 990.0 // Giá trị từ 10 đến 1000
        }

        let random40 = (0..<40).map { _ in nextRand() }
        let squarifyRects = TreemapLayout.squarify(values: random40, in: frame)

        // Tỉ lệ cạnh tệ nhất của squarify
        func aspect(_ r: CGRect) -> Double {
            guard r.width > 0, r.height > 0 else { return 1.0 }
            return max(Double(r.width / r.height), Double(r.height / r.width))
        }

        let squarifyWorst = squarifyRects.map(aspect).max() ?? 1.0

        // Slice-and-dice (chia dọc theo dải thanh)
        let total40 = random40.reduce(0.0, +)
        var sliceAndDiceWorst = 0.0
        for v in random40 {
            let w = Double(frame.width) * (v / total40)
            let h = Double(frame.height)
            let asp = max(w / h, h / w)
            sliceAndDiceWorst = max(sliceAndDiceWorst, asp)
        }

        // Tỉ lệ cạnh tệ nhất của squarify không lớn hơn slice-and-dice
        #expect(squarifyWorst <= sliceAndDiceWorst)
    }

    // MARK: - 6. Tiles: 2 cấp từ treemapProducts và 1 cấp
    @Test func treemapTilesHierarchy() {
        let frame = CGRect(x: 0, y: 0, width: 640, height: 380)

        // 1. Mẫu 2 cấp: treemapProducts
        guard case .categorical(let data2) = DataViewSamples.treemapProducts else {
            Issue.record("treemapProducts không phải categorical")
            return
        }

        let tiles2 = TreemapLayout.tiles(data: data2, in: frame)
        #expect(!tiles2.isEmpty)

        let parents = tiles2.filter { $0.isGroupHeader }
        let children = tiles2.filter { !$0.isGroupHeader }

        #expect(!parents.isEmpty)
        #expect(!children.isEmpty)

        // Ô con nằm trong ô cha; diện tích ô cha = tổng ô con (trừ phần dải tên nhóm)
        for p in parents {
            let pChildren = children.filter { $0.parentLabel == p.label }
            if !pChildren.isEmpty {
                for c in pChildren {
                    #expect(c.rect.minX >= p.rect.minX - 1e-5)
                    #expect(c.rect.maxX <= p.rect.maxX + 1e-5)
                    #expect(c.rect.minY >= p.rect.minY - 1e-5)
                    #expect(c.rect.maxY <= p.rect.maxY + 1e-5)
                }

                let headerH = p.headerRect?.height ?? 0.0
                let expectedChildArea = Double(p.rect.width * (p.rect.height - headerH))
                let actualChildArea = pChildren.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
                #expect(abs(actualChildArea - expectedChildArea) < 1e-4)
            }
        }

        // 2. Dữ liệu 1 cấp gồm hai nhóm (như page-D3.png)
        let catLevels = [FieldInfo(queryRef: "Product", displayName: "Sản phẩm", role: "Group", isMeasure: false)]
        let categories = ["Bank account or service", "Credit card"].map { CategoryKey(values: [.string($0)]) }
        let measures = [FieldInfo(queryRef: "Complaints", displayName: "Số khiếu nại", role: "Values", isMeasure: true)]
        let values: [[[DataCell]]] = [[[DataCell(.double(14_091)), DataCell(.double(9_328))]]]

        let data1 = CategoricalData(
            categoryLevels: catLevels,
            categories: categories,
            seriesField: nil,
            series: [],
            measures: measures,
            values: values,
            highlights: nil,
            isReduced: false
        )

        let tiles1 = TreemapLayout.tiles(data: data1, in: frame)
        #expect(tiles1.count == 2)
        #expect(tiles1[0].label == "Bank account or service")
        #expect(tiles1[1].label == "Credit card")

        let sumArea1 = tiles1.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(sumArea1 - Double(frame.width * frame.height)) < 1e-5)
    }
}
