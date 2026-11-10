import Foundation

enum InteractionEffect: Hashable, Sendable {
    case filter
    case highlight
    case none
}

struct InteractionOverride: Hashable, Sendable {
    var sourceID: String
    var targetID: String
    var effect: InteractionEffect

    init(sourceID: String, targetID: String, effect: InteractionEffect) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.effect = effect
    }
}

enum InteractionRules {
    /// Visual có thể phát ra lựa chọn (lọc chéo / tô sáng).
    static func canSelect(visualType: String) -> Bool {
        switch visualType {
        case "clusteredBarChart", "clusteredColumnChart",
             "stackedBarChart", "stackedColumnChart", "columnChart",
             "hundredPercentStackedColumnChart",
             "lineChart", "areaChart",
             "lineClusteredColumnComboChart", "lineStackedColumnComboChart",
             "donutChart", "pieChart",
             "treemap",
             "shapeMap", "filledMap",
             "pivotTable", "tableEx":
            return true
        default:
            return false
        }
    }

    /// Visual đích hỗ trợ tô sáng chéo.
    /// [QUAN SÁT: combo, donut, cột 100% (interactions-D2.png, xf-*.dax); phần còn lại SUY ĐOÁN.]
    static func supportsHighlight(visualType: String) -> Bool {
        switch visualType {
        case "lineClusteredColumnComboChart", "lineStackedColumnComboChart",
             "donutChart", "hundredPercentStackedColumnChart":
            return true
        case "pieChart", "treemap", // [SUY ĐOÁN]
             "clusteredBarChart", "clusteredColumnChart", // [SUY ĐOÁN]
             "stackedBarChart", "stackedColumnChart", "columnChart": // [SUY ĐOÁN]
            return true
        default:
            return false
        }
    }

    /// Hiệu ứng tương tác giữa visual nguồn và visual đích.
    static func effect(
        of source: InteractionTarget,
        on target: InteractionTarget,
        overrides: [InteractionOverride] = []
    ) -> InteractionEffect {
        // Nguồn và đích cùng visualID → .none
        if source.visualID == target.visualID {
            return .none
        }

        // Nguồn không canSelect → .none
        guard canSelect(visualType: source.visualType) else {
            return .none
        }

        // Khớp overrides theo sourceID/targetID
        if let ov = overrides.last(where: { $0.sourceID == source.visualID && $0.targetID == target.visualID }) {
            switch ov.effect {
            case .highlight:
                // Ghi đè .highlight lên đích không supportsHighlight thì thành .filter
                return supportsHighlight(visualType: target.visualType) ? .highlight : .filter
            case .filter:
                return .filter
            case .none:
                return .none
            }
        }

        // Mặc định: đích .none (slicer, textbox, actionButton, image, shape, basicShape, hoặc visualType lạ)
        switch target.visualType {
        case "slicer", "textbox", "actionButton", "image", "shape", "basicShape": // [SUY ĐOÁN]
            return .none
        default:
            break
        }

        // Đích tô sáng
        if supportsHighlight(visualType: target.visualType) {
            return .highlight
        }

        // Đích lọc: [QUAN SÁT: card, shape map (xf-card.dax, dt-card.dax); phần còn lại SUY ĐOÁN.]
        switch target.visualType {
        case "card", "shapeMap":
            return .filter
        case "multiRowCard", "filledMap", "lineChart", "areaChart", "pivotTable", "tableEx": // [SUY ĐOÁN]
            return .filter
        default: // Mọi visualType lạ -> .none // [SUY ĐOÁN]
            return .none
        }
    }
}
