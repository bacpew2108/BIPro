import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

enum DataLabels {
    static func text(
        cell: DataCell,
        is100Percent: Bool = false,
        ratio: Double? = nil,
        format: DataLabelsFormat
    ) -> String {
        if is100Percent {
            let r = ratio ?? (NumberDisplay.numericValue(cell.value) ?? 0)
            let p = format.precision ?? 2
            return NumberDisplay.decimal(r * 100, precision: p) + "%"
        }
        return NumberDisplay.text(
            cell,
            units: format.displayUnits,
            precision: format.precision
        )
    }
}
