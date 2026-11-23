import PBIXKit
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — PerformanceAnalyzer")
@MainActor
struct PerformanceRecorderTests {
    private func makeState() throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: try NewDocument.blank()), fileName: "perf.pbix")
    }

    @Test func startArmsTheObserverAndStopRemovesIt() throws {
        let state = try makeState()
        let recorder = state.perf
        #expect(!recorder.isRecording && state.interaction.onVisualLoaded == nil)
        recorder.start(interaction: state.interaction)
        #expect(recorder.isRecording && state.interaction.onVisualLoaded != nil)
        recorder.stop(interaction: state.interaction)
        #expect(!recorder.isRecording && state.interaction.onVisualLoaded == nil)
    }

    @Test func recordsOnlyWhileRecordingAndClearsOnRestart() throws {
        let state = try makeState()
        let recorder = state.perf
        let visual = ReportVisual(id: "v1", type: "barChart", x: 0, y: 0, z: 0, width: 100, height: 100)
        recorder.start(interaction: state.interaction)
        state.interaction.onVisualLoaded?(visual, .milliseconds(30), .milliseconds(80))
        #expect(recorder.entries.count == 1)
        #expect(abs(recorder.entries[0].queryMs - 30) < 0.5 && abs(recorder.entries[0].totalMs - 80) < 0.5)
        let hook = state.interaction.onVisualLoaded
        recorder.stop(interaction: state.interaction)
        hook?(visual, .milliseconds(1), .milliseconds(1))
        #expect(recorder.entries.count == 1)   // đã dừng: không ghi thêm
        recorder.start(interaction: state.interaction)
        #expect(recorder.entries.isEmpty)
    }

    @Test func refreshDoesNothingWhenNotRecording() throws {
        let state = try makeState()
        let before = state.interaction.modelVersion
        state.perf.refresh(interaction: state.interaction)
        #expect(state.interaction.modelVersion == before)
    }
}
}
