import SwiftUI
import ColumnStore

struct ColumnProfileView: View {
    let profile: ColumnProfile?
    let previewRows: Int
    var scrollable: Bool = true
    let onClose: () -> Void

    var body: some View {
        if let profile {
            VStack(spacing: 0) {
                headerView(profile: profile)
                    .hairline(.bottom)

                bodyContent(profile: profile)
                    .padding(8)
            }
            .frame(height: 200)
            .background(DS.Palette.chrome)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }

    private func headerView(profile: ColumnProfile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)

            Text(bi("Hồ sơ cột — ", "Column profile — "))
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)
            +
            Text(profile.columnName)
                .font(DS.Typeface.headlineSmall)
                .bold()
                .foregroundColor(DS.Palette.accent)

            Spacer()

            Text(QueryEditorFormat.profileCaption(rowsProfiled: previewRows, language: AppPreferences.shared.effectiveLanguage))
                .font(DS.Typeface.labelSmall)
                .foregroundStyle(DS.Palette.secondaryLabel)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(bi("Đóng hồ sơ cột", "Close column profile"))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(DS.Palette.canvas)
    }

    private func bodyContent(profile: ColumnProfile) -> some View {
        HStack(spacing: 8) {
            // Left Card: Column Statistics
            statisticsCard(profile: profile)
                .frame(minWidth: 220, idealWidth: 320, maxWidth: 320)

            // Right Card: Value Distribution
            distributionCard(profile: profile)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    private func statisticsCard(profile: ColumnProfile) -> some View {
        let count = QueryEditorFormat.countLine(profile)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(bi("Thống kê cột (\(profile.columnName))", "Column statistics (\(profile.columnName))"), systemImage: "analytics")
                    .font(DS.Typeface.label)
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)
                Spacer()
                Badge(text: bi("\(count) dòng", "\(count) rows"), color: DS.Palette.accent)
            }
            .padding(.bottom, 2)
            .hairline(.bottom)

            // Two-column property layout
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    statRow(label: bi("Số dòng", "Count"), value: "\(count)")
                    statRow(label: bi("Khác nhau", "Distinct"), value: "\(profile.distinct)")
                    statRow(label: bi("Lỗi", "Error"), value: "\(profile.error)", isDanger: profile.error > 0)
                    statRow(label: bi("Duy nhất", "Unique"), value: "\(profile.unique)")
                }
                VStack(spacing: 2) {
                    statRow(label: bi("Trống", "Empty"), value: "\(profile.empty)", isWarning: profile.empty > 0)
                    statRow(label: bi("Nhỏ nhất", "Min"), value: profile.min ?? "—")
                    statRow(label: bi("Lớn nhất", "Max"), value: profile.max ?? "—")
                    statRow(label: bi("Trung bình", "Average"), value: profile.average ?? "—")
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(8)
        .background(DS.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private func statRow(label: String, value: String, isDanger: Bool = false, isWarning: Bool = false) -> some View {
        HStack {
            Text(label + ":")
                .font(DS.Typeface.labelSmall)
                .foregroundStyle(DS.Palette.secondaryLabel)
            Spacer()
            Text(value)
                .font(DS.Typeface.mono)
                .foregroundStyle(isDanger ? DS.Palette.danger : (isWarning ? DS.Palette.warning : DS.Palette.label))
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .hairline(.bottom)
    }

    private func distributionCard(profile: ColumnProfile) -> some View {
        let count = QueryEditorFormat.countLine(profile)
        let maxCount = profile.distribution.map(\.count).max() ?? 1
        let buckets = scrollable ? profile.distribution : Array(profile.distribution.prefix(5))

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(bi("Phân bố giá trị (\(profile.columnName))", "Value distribution (\(profile.columnName))"), systemImage: "chart.bar")
                    .font(DS.Typeface.label)
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)
                Spacer()
                Text(bi("\(profile.distinct) giá trị", "\(profile.distinct) values"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(.bottom, 2)
            .hairline(.bottom)

            Group {
                if scrollable {
                    ScrollView(.vertical) {
                        bucketList(buckets: buckets, totalCount: count, maxCount: maxCount)
                    }
                } else {
                    bucketList(buckets: buckets, totalCount: count, maxCount: maxCount)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(8)
        .background(DS.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private func bucketList(buckets: [ProfileBucket], totalCount: Int, maxCount: Int) -> some View {
        VStack(spacing: 3) {
            ForEach(buckets.indices, id: \.self) { idx in
                let bucket = buckets[idx]
                let fraction = maxCount > 0 ? CGFloat(bucket.count) / CGFloat(maxCount) : 0
                HStack(spacing: 6) {
                    Text(bucket.label.isEmpty ? bi("(Trống)", "(Empty)") : bucket.label)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(bucket.label.isEmpty ? DS.Palette.tertiaryLabel : DS.Palette.label)
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DS.Palette.controlFill)
                                .frame(height: 8)

                            Capsule()
                                .fill(DS.Palette.accent)
                                .frame(width: max(4, geo.size.width * fraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("\(bucket.count) (\(QueryEditorFormat.percent(bucket.count, of: totalCount)))")
                        .font(DS.Typeface.mono)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(width: 64, alignment: .trailing)
                        .lineLimit(1)
                }
                .padding(.vertical, 1)
            }
        }
    }
}
