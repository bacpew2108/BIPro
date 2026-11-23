import PBIXKit
import SwiftUI

/// Giới hạn và bước thu phóng chuẩn Power BI Desktop (25%–400%).
enum StatusBarZoom {
    static let minScale: Double = 0.25
    static let maxScale: Double = 4.0
    static let step: Double = 0.10

    static func clamped(_ value: Double) -> Double {
        min(maxScale, max(minScale, value))
    }

    static func stepOut(from value: Double) -> Double {
        clamped(((value - step) * 100).rounded() / 100)
    }

    static func stepIn(from value: Double) -> Double {
        clamped(((value + step) * 100).rounded() / 100)
    }
}

/// Thanh trạng thái toàn cửa sổ (`UIMetrics.statusBar` = 23 pt) theo Power BI Desktop 2.159.
struct WindowStatusBar: View {
    @Bindable var state: DocumentState
    @Environment(\.isSnapshotRender) private var isSnapshotRender
    private let preferences = AppPreferences.shared

    var body: some View {
        let lang = preferences.effectiveLanguage
        HStack(spacing: 10) {
            Text(StatusLine.text(mode: state.mode, state: state, language: lang))
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.secondaryLabel)
                .lineLimit(1)

            if let message = state.layout.fieldRefusal ?? state.layout.notice {
                Text("·").foregroundStyle(DS.Palette.tertiaryLabel)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(1)
                    .help(message)
            }

            Spacer(minLength: 8)

            trailingControls
        }
        .padding(.horizontal, 10)
        .frame(height: UIMetrics.statusBar)
        .background(DS.Palette.chrome)
        .hairline(.top)
    }

    @ViewBuilder private var trailingControls: some View {
        switch state.mode {
        case .report:
            zoomSlider(
                scale: Binding(
                    get: { StatusBarZoom.clamped(state.zoom ?? state.renderedScale) },
                    set: { state.fitsWidth = false; state.zoom = StatusBarZoom.clamped($0) }
                ),
                onZoomOut: { state.fitsWidth = false; state.zoom = StatusBarZoom.stepOut(from: state.zoom ?? state.renderedScale) },
                onZoomIn: { state.fitsWidth = false; state.zoom = StatusBarZoom.stepIn(from: state.zoom ?? state.renderedScale) },
                onFit: { state.fitsWidth = false; state.zoom = nil },
                fitHelp: tr(.zoomFit)
            )
        case .model:
            HStack(spacing: 6) {
                Button { state.resetDiagramPositions() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.plain)
                .help(bi("Đặt lại bố cục sơ đồ", "Reset layout"))
                .accessibilityLabel(bi("Đặt lại bố cục sơ đồ", "Reset layout"))

                zoomSlider(
                    scale: Binding(
                        get: { StatusBarZoom.clamped(state.modelZoom) },
                        set: { state.modelZoom = StatusBarZoom.clamped($0) }
                    ),
                    onZoomOut: { state.modelZoom = StatusBarZoom.stepOut(from: state.modelZoom) },
                    onZoomIn: { state.modelZoom = StatusBarZoom.stepIn(from: state.modelZoom) },
                    onFit: { state.modelZoom = 0.6 },
                    fitHelp: bi("Vừa màn hình", "Zoom to fit")
                )
            }
        case .table, .daxQuery, .tmdl:
            EmptyView()
        }
    }

    private func zoomSlider(
        scale: Binding<Double>,
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onFit: @escaping () -> Void,
        fitHelp: String
    ) -> some View {
        let percent = Int((scale.wrappedValue * 100).rounded())
        return HStack(spacing: 4) {
            Button(action: onZoomOut) {
                Image(systemName: "minus")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 16, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(scale.wrappedValue <= StatusBarZoom.minScale)
            .help(tr(.zoomOut))
            .accessibilityLabel(tr(.zoomOut))

            if isSnapshotRender {
                let ratio = (scale.wrappedValue - StatusBarZoom.minScale) / (StatusBarZoom.maxScale - StatusBarZoom.minScale)
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.separator).frame(width: 72, height: 2.5)
                    Circle().fill(DS.Palette.secondaryLabel).frame(width: 8, height: 8)
                        .offset(x: CGFloat(max(0, min(1, ratio))) * 64)
                }
                .frame(width: 72, height: 14)
            } else {
                Slider(value: scale, in: StatusBarZoom.minScale...StatusBarZoom.maxScale)
                    .controlSize(.mini)
                    .frame(width: 78)
                    .accessibilityLabel(bi("Thu phóng", "Zoom"))
            }

            Button(action: onZoomIn) {
                Image(systemName: "plus")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 16, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(scale.wrappedValue >= StatusBarZoom.maxScale)
            .help(tr(.zoomIn))
            .accessibilityLabel(tr(.zoomIn))

            Text("\(percent)%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(DS.Palette.secondaryLabel)
                .frame(width: 36, alignment: .trailing)
                .accessibilityLabel("\(percent)%")

            Button(action: onFit) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(fitHelp)
            .accessibilityLabel(fitHelp)
        }
    }
}

/// Shim tương thích cho `TableWorkspace`, `ModelWorkspace`, `QueryWorkspaces` (sẽ gỡ triệt để ở T076–T078).
/// Không vẽ thanh lặp vì `ShellView` đã gắn `WindowStatusBar` toàn cửa sổ.
struct StatusBar<Trailing: View>: View {
    let workspace: Workspace
    var detail: String = ""
    @ViewBuilder var trailing: Trailing

    var body: some View { EmptyView() }
}

extension StatusBar where Trailing == EmptyView {
    init(workspace: Workspace, detail: String = "") {
        self.init(workspace: workspace, detail: detail) { EmptyView() }
    }
}

/// Zoom control tương thích (sẽ gỡ khi `ModelWorkspace` hoàn tất ở T077).
struct ZoomControl: View {
    let percent: Int
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let fit: () -> Void

    var body: some View { EmptyView() }
}
