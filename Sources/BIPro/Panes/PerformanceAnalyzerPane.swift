import PBIXKit
import SwiftUI

/// Một dòng đo của Performance analyzer: thời gian truy vấn DAX và tổng thời gian nạp của một visual.
struct PerfEntry: Identifiable, Equatable {
    let id = UUID()
    let visualID: String
    let title: String
    let symbol: String
    let queryMs: Double
    let totalMs: Double
    let error: String?
}

/// Ghi lại thời gian nạp từng visual của trang đang mở (như ngăn Performance analyzer của Desktop, VM 2026-11-21 `pn_perfanalyzer.png`):
/// Start recording → Refresh visuals nạp lại mọi visual của trang và ghi từng dòng → Stop. Đo bằng engine DAX của BI Pro nên
/// con số là của BI Pro, không so được với Desktop.
@MainActor
@Observable
final class PerformanceRecorder {
    var isRecording = false
    var entries: [PerfEntry] = []

    func start(interaction: ReportInteraction) {
        entries = []
        isRecording = true
        interaction.onVisualLoaded = { [weak self] visual, query, total in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                self.entries.append(PerfEntry(visualID: visual.id, title: VisualCatalog.displayTitle(visual),
                                              symbol: VisualCatalog.symbol(visual.type),
                                              queryMs: Self.ms(query), totalMs: Self.ms(total), error: nil))
            }
        }
    }

    func stop(interaction: ReportInteraction) {
        isRecording = false
        interaction.onVisualLoaded = nil
    }

    func clear() { entries = [] }

    var totalMs: Double { entries.reduce(0) { $0 + $1.totalMs } }

    /// Buộc mọi visual chạy lại truy vấn (bỏ bộ nhớ đệm kết quả, giữ engine) để đo thật; từng lần nạp tự ghi qua `onVisualLoaded`.
    func refresh(interaction: ReportInteraction) {
        guard isRecording else { return }
        interaction.reloadVisualsBypassingCache()
    }

    static func ms(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}

struct PerformanceAnalyzerPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?

    var body: some View {
        let recorder = state.perf
        VStack(spacing: 0) {
            PaneHeader(title: bi("Phân tích hiệu năng", "Performance analyzer"), symbol: "gauge.with.dots.needle.67percent", collapse: collapse)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    recorder.start(interaction: state.interaction)
                } label: {
                    Label(bi("Bắt đầu ghi", "Start recording"), systemImage: "record.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(recorder.isRecording)
                HStack(spacing: 6) {
                Button {
                    recorder.refresh(interaction: state.interaction)
                } label: {
                    Label(bi("Làm mới visual", "Refresh visuals"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!recorder.isRecording)
                Button {
                    recorder.stop(interaction: state.interaction)
                } label: {
                    Label(bi("Dừng", "Stop"), systemImage: "stop.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!recorder.isRecording)
                Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            .lineLimit(1)

            if recorder.entries.isEmpty {
                Text(recorder.isRecording
                     ? bi("Đang ghi. Bấm Làm mới visual (hoặc đổi slicer, đổi trang) để đo thời gian nạp của từng visual.",
                          "Recording. Click Refresh visuals (or change a slicer or page) to measure how long each visual takes.")
                     : bi("Bắt đầu theo dõi để xem thời gian mỗi visual truy vấn dữ liệu và vẽ kết quả.",
                          "Start monitoring your report to see details about the time taken by each visual to query for its data and render the result."))
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                HStack {
                    Text(bi("Tổng truy vấn: \(Int(recorder.entries.reduce(0) { $0 + $1.queryMs }.rounded())) ms", "Total DAX time: \(Int(recorder.entries.reduce(0) { $0 + $1.queryMs }.rounded())) ms"))
                        .font(DS.Typeface.label).foregroundStyle(DS.Palette.label)
                    Spacer()
                    Button(bi("Xoá", "Clear")) { recorder.clear() }.buttonStyle(.plain).font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.accent)
                }
                .padding(.horizontal, 12).padding(.bottom, 4)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recorder.entries.sorted { $0.queryMs > $1.queryMs }) { entry in row(entry, max: recorder.entries.map(\.queryMs).max() ?? 1) }
                    }
                }
            }
            PaneFooter(text: bi("Đo bằng engine DAX của BI Pro; không so được với Power BI Desktop.",
                                "Measured with BI Pro's DAX engine; not comparable with Power BI Desktop."))
        }
        .background(DS.Palette.chrome)
    }

    private func row(_ entry: PerfEntry, max: Double) -> some View {
        Button {
            state.visualID = entry.visualID
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: entry.symbol).font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 14)
                    Text(entry.title).font(DS.Typeface.bodySmall).lineLimit(1).foregroundStyle(DS.Palette.label)
                    Spacer()
                    Text("\(Int(entry.queryMs.rounded())) ms").font(DS.Typeface.mono).foregroundStyle(DS.Palette.label)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.separator)
                        Capsule().fill(entry.error == nil ? DS.Palette.accent : DS.Palette.danger)
                            .frame(width: geo.size.width * CGFloat(max > 0 ? entry.queryMs / max : 0))
                    }
                }
                .frame(height: 4)
                Text(entry.error ?? bi("Truy vấn DAX · tổng nạp \(Int(entry.totalMs.rounded())) ms (gồm chờ engine và vẽ)", "DAX query · total load \(Int(entry.totalMs.rounded())) ms (incl. engine wait)"))
                    .font(DS.Typeface.labelSmall).foregroundStyle(entry.error == nil ? DS.Palette.tertiaryLabel : DS.Palette.danger).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
