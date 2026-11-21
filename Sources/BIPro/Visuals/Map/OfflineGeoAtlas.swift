import Foundation

/// Bảng toạ độ địa lý 100% ngoại tuyến (Hiến pháp IV: không gọi mạng) cho 50 bang Mỹ + DC và các quốc gia/khu vực phổ biến.
enum OfflineGeoAtlas {
    struct Coordinate: Hashable, Sendable {
        let lat: Double
        let lon: Double
        let isUSState: Bool
    }

    static func lookup(_ raw: String) -> Coordinate? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return entries[key]
    }

    /// 50 bang Mỹ + DC (tên đầy đủ & mã 2 chữ cái) + các quốc gia/khu vực chính.
    static let entries: [String: Coordinate] = {
        var map: [String: Coordinate] = [:]
        func addUS(_ name: String, _ code: String, _ lat: Double, _ lon: Double) {
            let c = Coordinate(lat: lat, lon: lon, isUSState: true)
            map[name.lowercased()] = c
            map[code.lowercased()] = c
        }
        func addWorld(_ names: [String], _ lat: Double, _ lon: Double) {
            let c = Coordinate(lat: lat, lon: lon, isUSState: false)
            for n in names { map[n.lowercased()] = c }
        }

        // 50 US States + DC
        addUS("Alabama", "AL", 32.806671, -86.791130)
        addUS("Alaska", "AK", 61.370716, -152.404419)
        addUS("Arizona", "AZ", 33.729759, -111.431221)
        addUS("Arkansas", "AR", 34.969704, -92.373123)
        addUS("California", "CA", 36.116203, -119.681564)
        addUS("Colorado", "CO", 39.059811, -105.311104)
        addUS("Connecticut", "CT", 41.597782, -72.755371)
        addUS("Delaware", "DE", 39.318523, -75.507141)
        addUS("District of Columbia", "DC", 38.897438, -77.026817)
        addUS("Florida", "FL", 27.766279, -81.686783)
        addUS("Georgia", "GA", 33.040619, -83.643074)
        addUS("Hawaii", "HI", 21.094318, -157.498337)
        addUS("Idaho", "ID", 44.240459, -114.478828)
        addUS("Illinois", "IL", 40.349457, -88.986137)
        addUS("Indiana", "IN", 39.849426, -86.258278)
        addUS("Iowa", "IA", 42.011539, -93.210526)
        addUS("Kansas", "KS", 38.526600, -96.726486)
        addUS("Kentucky", "KY", 37.668140, -84.670067)
        addUS("Louisiana", "LA", 31.169546, -91.867805)
        addUS("Maine", "ME", 44.693947, -69.381927)
        addUS("Maryland", "MD", 39.063946, -76.802101)
        addUS("Massachusetts", "MA", 42.230171, -71.530106)
        addUS("Michigan", "MI", 43.326618, -84.536095)
        addUS("Minnesota", "MN", 45.694454, -93.900192)
        addUS("Mississippi", "MS", 32.741646, -89.678696)
        addUS("Missouri", "MO", 38.456085, -92.288368)
        addUS("Montana", "MT", 46.921925, -110.454353)
        addUS("Nebraska", "NE", 41.125370, -98.268082)
        addUS("Nevada", "NV", 38.313515, -117.055374)
        addUS("New Hampshire", "NH", 43.452492, -71.563896)
        addUS("New Jersey", "NJ", 40.298904, -74.521011)
        addUS("New Mexico", "NM", 34.840515, -106.248482)
        addUS("New York", "NY", 42.165726, -74.948051)
        addUS("North Carolina", "NC", 35.630066, -79.806419)
        addUS("North Dakota", "ND", 47.528912, -99.784012)
        addUS("Ohio", "OH", 40.388783, -82.764915)
        addUS("Oklahoma", "OK", 35.565342, -96.928917)
        addUS("Oregon", "OR", 44.572021, -122.070938)
        addUS("Pennsylvania", "PA", 40.590752, -77.209755)
        addUS("Rhode Island", "RI", 41.680893, -71.511780)
        addUS("South Carolina", "SC", 33.856892, -80.945007)
        addUS("South Dakota", "SD", 44.299782, -99.438828)
        addUS("Tennessee", "TN", 35.747845, -86.692345)
        addUS("Texas", "TX", 31.054487, -97.563461)
        addUS("Utah", "UT", 40.150032, -111.862434)
        addUS("Vermont", "VT", 44.045876, -72.710686)
        addUS("Virginia", "VA", 37.769337, -78.169968)
        addUS("Washington", "WA", 47.400902, -121.490494)
        addUS("West Virginia", "WV", 38.491226, -80.954453)
        addUS("Wisconsin", "WI", 44.268543, -89.616508)
        addUS("Wyoming", "WY", 42.755966, -107.302490)

        // World countries & major regions
        addWorld(["United States", "United States of America", "USA", "US"], 39.8283, -98.5795)
        addWorld(["Canada"], 56.1304, -106.3468)
        addWorld(["Mexico"], 23.6345, -102.5528)
        addWorld(["Brazil"], -14.2350, -51.9253)
        addWorld(["Argentina"], -38.4161, -63.6167)
        addWorld(["Chile"], -35.6751, -71.5430)
        addWorld(["Colombia"], 4.5709, -74.2973)
        addWorld(["Peru"], -9.1900, -75.0152)
        addWorld(["United Kingdom", "UK", "Great Britain", "England"], 55.3781, -3.4360)
        addWorld(["France"], 46.2276, 2.2137)
        addWorld(["Germany"], 51.1657, 10.4515)
        addWorld(["Italy"], 41.8719, 12.5674)
        addWorld(["Spain"], 40.4637, -3.7492)
        addWorld(["Portugal"], 39.3999, -8.2245)
        addWorld(["Netherlands"], 52.1326, 5.2913)
        addWorld(["Belgium"], 50.5039, 4.4699)
        addWorld(["Switzerland"], 46.8182, 8.2275)
        addWorld(["Austria"], 47.5162, 14.5501)
        addWorld(["Poland"], 51.9194, 19.1451)
        addWorld(["Sweden"], 60.1282, 18.6435)
        addWorld(["Norway"], 60.4720, 8.4689)
        addWorld(["Denmark"], 56.2639, 9.5018)
        addWorld(["Finland"], 61.9241, 25.7482)
        addWorld(["Ireland"], 53.1424, -7.6921)
        addWorld(["Czech Republic", "Czechia"], 49.8175, 15.4730)
        addWorld(["Greece"], 39.0742, 21.8243)
        addWorld(["Turkey"], 38.9637, 35.2433)
        addWorld(["Russia", "Russian Federation"], 61.5240, 105.3188)
        addWorld(["Ukraine"], 48.3794, 31.1656)
        addWorld(["Vietnam", "Viet Nam", "Việt Nam"], 14.0583, 108.2772)
        addWorld(["China"], 35.8617, 104.1954)
        addWorld(["Japan"], 36.2048, 138.2529)
        addWorld(["South Korea", "Korea", "Republic of Korea"], 35.9078, 127.7669)
        addWorld(["India"], 20.5937, 78.9629)
        addWorld(["Indonesia"], -0.7893, 113.9213)
        addWorld(["Thailand"], 15.8700, 100.9925)
        addWorld(["Singapore"], 1.3521, 103.8198)
        addWorld(["Malaysia"], 4.2105, 101.9758)
        addWorld(["Philippines"], 12.8797, 121.7740)
        addWorld(["Taiwan"], 23.6978, 120.9605)
        addWorld(["Hong Kong"], 22.3193, 114.1694)
        addWorld(["Australia"], -25.2744, 133.7751)
        addWorld(["New Zealand"], -40.9006, 174.8860)
        addWorld(["South Africa"], -30.5595, 22.9375)
        addWorld(["Egypt"], 26.8206, 30.8025)
        addWorld(["Nigeria"], 9.0820, 8.6753)
        addWorld(["Kenya"], -0.0236, 37.9062)
        addWorld(["Saudi Arabia"], 23.8859, 45.0792)
        addWorld(["United Arab Emirates", "UAE"], 23.4241, 53.8478)
        addWorld(["Israel"], 31.0461, 34.8516)
        // US regions (used in Nhom6 Dim_District / sales datasets)
        addWorld(["Northeast", "East"], 41.5, -74.0)
        addWorld(["Midwest", "Central"], 41.5, -93.0)
        addWorld(["South"], 33.0, -86.0)
        addWorld(["West"], 39.0, -118.0)
        addWorld(["North"], 45.0, -95.0)
        return map
    }()
}
