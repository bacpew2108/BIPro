import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

enum MatrixGradient {
    /// Tính giá trị min và max từ các ô **không phải tổng** của measure trong matrix:
    /// - Bỏ qua các hàng/cột có `isGrandTotal == true` hoặc `isSubtotal == true`;
    /// - Ô BLANK với `rule.nullStrategy == "asZero"` thì tính giá trị 0.0.
    static func minMax(
        data: MatrixData,
        measureIndex: Int = 0,
        rule: GradientRule
    ) -> (min: Double, max: Double)? {
        var minVal: Double?
        var maxVal: Double?

        for (r, row) in data.rows.enumerated() {
            if row.isGrandTotal || row.isSubtotal { continue }
            for (c, col) in (data.columns.isEmpty ? [MatrixHeader(path: [], level: 0)] : data.columns).enumerated() {
                if col.isGrandTotal || col.isSubtotal { continue }
                let cell = data.cell(row: r, column: c, measure: measureIndex)
                if let num = NumberDisplay.numericValue(cell.value) {
                    minVal = Swift.min(minVal ?? num, num)
                    maxVal = Swift.max(maxVal ?? num, num)
                } else if case .blank = cell.value, rule.nullStrategy == "asZero" {
                    minVal = Swift.min(minVal ?? 0.0, 0.0)
                    maxVal = Swift.max(maxVal ?? 0.0, 0.0)
                }
            }
        }

        guard let minV = minVal, let maxV = maxVal else { return nil }
        return (min: minV, max: maxV)
    }

    /// Trả về màu nền nội suy min → mid → max:
    /// - Ô BLANK xử lý theo `nullStrategy` ("asZero" thì coi như 0);
    /// - min/mid/max nội suy tuyến tính.
    static func color(
        value: Double?,
        min: Double,
        max: Double,
        rule: GradientRule,
        theme: ReportTheme = .fallback
    ) -> Color? {
        let numericValue: Double
        if let v = value {
            numericValue = v
        } else if rule.nullStrategy == "asZero" {
            numericValue = 0.0
        } else {
            return nil
        }

        guard let minC = theme.color(rule.minColor),
              let maxC = theme.color(rule.maxColor) else {
            return nil
        }

        if max <= min {
            return minC
        }

        if numericValue <= min {
            return minC
        }
        if numericValue >= max {
            return maxC
        }

        if let midLit = rule.midColor, let midC = theme.color(midLit) {
            let mid = (min + max) / 2.0
            if numericValue < mid {
                let fraction = (numericValue - min) / (mid - min)
                return minC.mixed(with: midC, by: fraction)
            } else {
                let fraction = (numericValue - mid) / (max - mid)
                return midC.mixed(with: maxC, by: fraction)
            }
        } else {
            let fraction = (numericValue - min) / (max - min)
            return minC.mixed(with: maxC, by: fraction)
        }
    }
}
