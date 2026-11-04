import Foundation

// MARK: - TopoJSON Data Structures

struct GeoPoint: Hashable, Sendable {
    var longitude: Double
    var latitude: Double

    init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

struct TopoFeature: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var postal: String
    /// polygons: [đa giác][vòng][điểm kinh/vĩ độ]
    var polygons: [[[GeoPoint]]]

    init(id: String, name: String, postal: String, polygons: [[[GeoPoint]]]) {
        self.id = id
        self.name = name
        self.postal = postal
        self.polygons = polygons
    }
}

struct TopoMap: Sendable {
    var features: [TopoFeature]

    init(features: [TopoFeature]) {
        self.features = features
    }
}

// MARK: - TopoJSON Decoder

enum TopoJSONError: Error {
    case invalidJSON
    case missingObjects
    case missingArcs
}

enum TopoJSON {
    /// Giải mã TopoJSON Data thành TopoMap.
    /// - Giải mã `arcs` kiểu delta và áp dụng `transform` (scale, translate).
    /// - Arc đảo chiều có chỉ số âm `~i`.
    /// - Nối các arc thành vòng đóng (điểm đầu = điểm cuối).
    static func decode(_ data: Data) throws -> TopoMap {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TopoJSONError.invalidJSON
        }

        // 1. Transform
        var scaleX = 1.0
        var scaleY = 1.0
        var translateX = 0.0
        var translateY = 0.0

        if let transform = json["transform"] as? [String: Any] {
            if let scale = transform["scale"] as? [Double], scale.count >= 2 {
                scaleX = scale[0]
                scaleY = scale[1]
            } else if let scale = transform["scale"] as? [NSNumber], scale.count >= 2 {
                scaleX = scale[0].doubleValue
                scaleY = scale[1].doubleValue
            }

            if let translate = transform["translate"] as? [Double], translate.count >= 2 {
                translateX = translate[0]
                translateY = translate[1]
            } else if let translate = transform["translate"] as? [NSNumber], translate.count >= 2 {
                translateX = translate[0].doubleValue
                translateY = translate[1].doubleValue
            }
        }

        // 2. Arcs giải mã delta
        guard let rawArcs = json["arcs"] as? [[[Any]]] else {
            throw TopoJSONError.missingArcs
        }

        var decodedArcs: [[GeoPoint]] = []
        decodedArcs.reserveCapacity(rawArcs.count)

        for arc in rawArcs {
            var x = 0
            var y = 0
            var points: [GeoPoint] = []
            points.reserveCapacity(arc.count)

            for coord in arc {
                guard coord.count >= 2 else { continue }
                let dx: Int
                let dy: Int
                if let nx = coord[0] as? Int, let ny = coord[1] as? Int {
                    dx = nx
                    dy = ny
                } else if let nx = coord[0] as? NSNumber, let ny = coord[1] as? NSNumber {
                    dx = nx.intValue
                    dy = ny.intValue
                } else {
                    continue
                }

                x += dx
                y += dy

                let lon = Double(x) * scaleX + translateX
                let lat = Double(y) * scaleY + translateY
                points.append(GeoPoint(longitude: lon, latitude: lat))
            }
            decodedArcs.append(points)
        }

        // 3. Helper giải mã một vòng (ring) từ danh sách chỉ số arc
        func decodeRing(_ arcIndices: [Int]) -> [GeoPoint] {
            var ringPoints: [GeoPoint] = []
            for arcIndex in arcIndices {
                let isReversed = arcIndex < 0
                let arcIdx = isReversed ? ~arcIndex : arcIndex
                guard arcIdx < decodedArcs.count else { continue }

                let arcPts = decodedArcs[arcIdx]
                let points = isReversed ? Array(arcPts.reversed()) : arcPts

                if ringPoints.isEmpty {
                    ringPoints.append(contentsOf: points)
                } else {
                    // Tránh lặp điểm nối giữa các arc
                    if let last = ringPoints.last, let first = points.first,
                       abs(last.longitude - first.longitude) < 1e-9 && abs(last.latitude - first.latitude) < 1e-9 {
                        ringPoints.append(contentsOf: points.dropFirst())
                    } else {
                        ringPoints.append(contentsOf: points)
                    }
                }
            }

            // Đảm bảo vòng đóng (điểm đầu = điểm cuối)
            if let first = ringPoints.first, let last = ringPoints.last {
                if abs(first.longitude - last.longitude) > 1e-9 || abs(first.latitude - last.latitude) > 1e-9 {
                    ringPoints.append(first)
                }
            }

            return ringPoints
        }

        // 4. Objects
        guard let objects = json["objects"] as? [String: Any] else {
            throw TopoJSONError.missingObjects
        }

        // Lấy collection đầu tiên (thường là "states")
        var geometries: [[String: Any]] = []
        for (_, objVal) in objects {
            if let objDict = objVal as? [String: Any],
               let geomList = objDict["geometries"] as? [[String: Any]] {
                geometries = geomList
                break
            }
        }

        var features: [TopoFeature] = []
        features.reserveCapacity(geometries.count)

        for geom in geometries {
            let id = String(describing: geom["id"] ?? "")
            let props = geom["properties"] as? [String: Any] ?? [:]
            let name = props["name"] as? String ?? ""
            let postal = props["postal"] as? String ?? ""
            let type = geom["type"] as? String ?? ""

            var polygons: [[[GeoPoint]]] = []

            if type == "Polygon" {
                // arcs: [[Int]]
                if let rawRings = geom["arcs"] as? [[Int]] {
                    var rings: [[GeoPoint]] = []
                    for rawRing in rawRings {
                        let ring = decodeRing(rawRing)
                        if ring.count >= 4 {
                            rings.append(ring)
                        }
                    }
                    if !rings.isEmpty {
                        polygons.append(rings)
                    }
                }
            } else if type == "MultiPolygon" {
                // arcs: [[[Int]]]
                if let rawPolys = geom["arcs"] as? [[[Int]]] {
                    for rawPoly in rawPolys {
                        var rings: [[GeoPoint]] = []
                        for rawRing in rawPoly {
                            let ring = decodeRing(rawRing)
                            if ring.count >= 4 {
                                rings.append(ring)
                            }
                        }
                        if !rings.isEmpty {
                            polygons.append(rings)
                        }
                    }
                }
            }

            features.append(TopoFeature(
                id: id,
                name: name,
                postal: postal,
                polygons: polygons
            ))
        }

        return TopoMap(features: features)
    }
}
