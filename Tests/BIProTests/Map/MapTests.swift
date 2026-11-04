import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct MapTests {

    private func loadTopoMap() throws -> (TopoMap, [String: Any]) {
        let fileURL = URL(fileURLWithPath: #filePath)
        let fixtureURL = fileURL.deletingLastPathComponent().appendingPathComponent("Fixtures/usa.states.topo.json")
        let data = try Data(contentsOf: fixtureURL)
        let map = try TopoJSON.decode(data)
        let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (map, rawJSON)
    }

    // MARK: - 7. TopoJSON.decode trên Fixtures/usa.states.topo.json
    @Test func topoJSONDecode() throws {
        let (map, rawJSON) = try loadTopoMap()

        // Đúng 51 feature (50 bang + DC)
        #expect(map.features.count == 51)

        // Có "New Mexico"
        let hasNewMexico = map.features.contains { $0.name == "New Mexico" }
        #expect(hasNewMexico)

        // Có postal == "MI" cho "Michigan"
        let michigan = map.features.first { $0.name == "Michigan" }
        #expect(michigan != nil)
        #expect(michigan?.postal == "MI")

        // Mọi vòng đóng (điểm đầu = điểm cuối) và có ít nhất 4 điểm
        for feature in map.features {
            for poly in feature.polygons {
                for ring in poly {
                    #expect(ring.count >= 4)
                    guard let first = ring.first, let last = ring.last else {
                        Issue.record("Ring rỗng trong feature \(feature.name)")
                        continue
                    }
                    #expect(abs(first.longitude - last.longitude) < 1e-6)
                    #expect(abs(first.latitude - last.latitude) < 1e-6)

                    // Kinh độ trong [-180, -60], vĩ độ trong [17, 72]
                    for pt in ring {
                        #expect(pt.longitude >= -180.0 && pt.longitude <= -60.0)
                        #expect(pt.latitude >= 17.0 && pt.latitude <= 72.0)
                    }
                }
            }
        }

        // Điểm đầu của arc 0 sau giải mã = (8515 * scale.x + translate.x, 4349 * scale.y + translate.y) lấy trực tiếp từ JSON thô
        let transform = rawJSON["transform"] as? [String: Any]
        let scale = transform?["scale"] as? [Double] ?? (transform?["scale"] as? [NSNumber])?.map(\.doubleValue) ?? []
        let translate = transform?["translate"] as? [Double] ?? (transform?["translate"] as? [NSNumber])?.map(\.doubleValue) ?? []

        #expect(scale.count >= 2)
        #expect(translate.count >= 2)

        let expectedLon = 8515.0 * scale[0] + translate[0]
        let expectedLat = 4349.0 * scale[1] + translate[1]

        // Tìm điểm đầu của Michigan (hoặc feature chứa arc 0)
        let firstPtOfMichigan = michigan?.polygons.first?.first?.first
        #expect(firstPtOfMichigan != nil)
        if let pt = firstPtOfMichigan {
            #expect(abs(pt.longitude - expectedLon) < 1e-6)
            #expect(abs(pt.latitude - expectedLat) < 1e-6)
        }
    }

    // MARK: - 8. AlbersUSA: toạ độ tương đối, Alaska, Hawaii, điểm ngoài US
    @Test func albersUSAProperties() throws {
        let (map, _) = try loadTopoMap()

        // 1. California (Tây) bên trái New York (Đông): x_CA < x_NY
        let califPt = AlbersUSA.project(longitude: -119.4179, latitude: 36.7783) // Trung tâm CA
        let nyPt = AlbersUSA.project(longitude: -74.0060, latitude: 40.7128)     // Trung tâm NY
        #expect(califPt != nil && nyPt != nil)
        if let c = califPt, let ny = nyPt {
            #expect(c.x < ny.x)
        }

        // 2. Washington (Bắc) ở trên Texas (Nam): y_WA < y_TX (toạ độ màn hình y hướng xuống)
        let waPt = AlbersUSA.project(longitude: -120.7401, latitude: 47.7511)    // WA
        let txPt = AlbersUSA.project(longitude: -99.9018, latitude: 31.9686)     // TX
        #expect(waPt != nil && txPt != nil)
        if let wa = waPt, let tx = txPt {
            #expect(wa.y < tx.y)
        }

        // 3. Khung đã vừa 616x380
        let targetSize = CGSize(width: 616, height: 380)
        let fitted = ShapeMapLayout.fitMap(map, in: targetSize)
        #expect(!fitted.featurePaths.isEmpty)

        // Mọi điểm của 51 feature nằm trong khung sau khi vừa
        for fp in fitted.featurePaths {
            #expect(fp.bounds.minX >= -1.0)
            #expect(fp.bounds.minY >= -1.0)
            #expect(fp.bounds.maxX <= targetSize.width + 1.0)
            #expect(fp.bounds.maxY <= targetSize.height + 1.0)
        }

        // Tâm của Alaska và Hawaii rơi vào vùng góc dưới trái:
        // x < 40% chiều rộng (246.4), y > 70% chiều cao (266.0); Alaska nằm bên trái Hawaii
        let akPath = fitted.featurePaths.first { $0.postal == "AK" }
        let hiPath = fitted.featurePaths.first { $0.postal == "HI" }

        #expect(akPath != nil && hiPath != nil)
        if let ak = akPath, let hi = hiPath {
            let akCenter = CGPoint(x: ak.bounds.midX, y: ak.bounds.midY)
            let hiCenter = CGPoint(x: hi.bounds.midX, y: hi.bounds.midY)

            // x < 40%
            #expect(akCenter.x < targetSize.width * 0.40)
            #expect(hiCenter.x < targetSize.width * 0.40)

            // y > 70%
            #expect(akCenter.y > targetSize.height * 0.70)
            #expect(hiCenter.y > targetSize.height * 0.70)

            // Alaska nằm bên trái Hawaii
            #expect(akCenter.x < hiCenter.x)
        }

        // 4. Điểm ngoài nước Mỹ (Việt Nam, London...) vẫn trả về toạ độ hữu hạn hoặc nil, không crash
        let vnPt = AlbersUSA.project(longitude: 105.8544, latitude: 21.0285)
        if let pt = vnPt {
            #expect(pt.x.isFinite && pt.y.isFinite)
        }

        let nullIsland = AlbersUSA.project(longitude: 0.0, latitude: 0.0)
        if let pt = nullIsland {
            #expect(pt.x.isFinite && pt.y.isFinite)
        }
    }

    // MARK: - 9. ShapeMapLayout.feature: tên đầy đủ, postal, nil, unmatchedCount
    @Test func shapeMapMatchingAndUnmatched() throws {
        let (map, _) = try loadTopoMap()

        // Khớp tên đầy đủ "new mexico" (khác hoa thường, khoảng trắng)
        let fNM1 = ShapeMapLayout.feature(for: .string("new mexico"), in: map)
        #expect(fNM1 != nil)
        #expect(fNM1?.name == "New Mexico")

        let fNM2 = ShapeMapLayout.feature(for: .string("  NEW MEXICO  "), in: map)
        #expect(fNM2 != nil)
        #expect(fNM2?.name == "New Mexico")

        // Khớp mã bang "CA" và "ca"
        let fCA = ShapeMapLayout.feature(for: .string("CA"), in: map)
        #expect(fCA != nil)
        #expect(fCA?.name == "California")

        let fca = ShapeMapLayout.feature(for: .string("ca"), in: map)
        #expect(fca != nil)
        #expect(fca?.name == "California")

        // Chuỗi lạ -> nil
        let fUnknown = ShapeMapLayout.feature(for: .string("Atlantis"), in: map)
        #expect(fUnknown == nil)

        // unmatchedCount
        let catLevels = [FieldInfo(queryRef: "State", displayName: "Bang", role: "Category", isMeasure: false)]
        let categories = ["CA", "New Mexico", "InvalidState1", "TX", "InvalidState2"].map { CategoryKey(values: [.string($0)]) }
        let measures = [FieldInfo(queryRef: "Amount", displayName: "Tiền", role: "Values", isMeasure: true)]
        let dummyData = CategoricalData(
            categoryLevels: catLevels,
            categories: categories,
            seriesField: nil,
            series: [],
            measures: measures,
            values: [[[DataCell(.double(1)), DataCell(.double(2)), DataCell(.double(3)), DataCell(.double(4)), DataCell(.double(5))]]],
            highlights: nil,
            isReduced: false
        )

        let unmatched = ShapeMapLayout.unmatchedCount(data: dummyData, in: map)
        #expect(unmatched == 2) // "InvalidState1" và "InvalidState2"
    }
}
