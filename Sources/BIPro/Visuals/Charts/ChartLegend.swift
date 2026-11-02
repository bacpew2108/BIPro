import PBIXKit
import SwiftUI

struct LegendItem: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var color: Color
    
    init(id: String, name: String, color: Color) {
        self.id = id
        self.name = name
        self.color = color
    }
}

struct ChartLegendView: View {
    let items: [LegendItem]
    let position: String?
    let fontSize: Double?
    
    init(items: [LegendItem], position: String? = nil, fontSize: Double? = nil) {
        self.items = items
        self.position = position
        self.fontSize = fontSize
    }
    
    private var size: CGFloat {
        ReportUnits.pixels(fromPoints: fontSize ?? 9)
    }
    
    var body: some View {
        let pos = position ?? "Top"
        if pos.contains("Left") || pos.contains("Right") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    legendRow(item)
                }
            }
        } else {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    legendRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment(for: pos))
        }
    }
    
    private func alignment(for pos: String) -> Alignment {
        switch pos {
        case "TopCenter", "BottomCenter", "Center":
            return .center
        case "TopRight", "BottomRight", "Right":
            return .trailing
        default:
            return .leading
        }
    }
    
    private func legendRow(_ item: LegendItem) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(item.color)
                .frame(width: 7, height: 7)
            Text(item.name)
                .font(.system(size: size))
                .foregroundColor(Color(hex: "#252423") ?? .primary)
                .lineLimit(1)
        }
    }
}
