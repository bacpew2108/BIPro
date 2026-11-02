import DAXEngine
import Foundation

// MARK: - Chạy truy vấn DAX (UI1)
//
// Chạy nền: `QueryRunner.execute` là hàm async không gắn actor, nên engine chạy ngoài main thread.
// Huỷ: `Task.cancel()` trên task của tab; engine kiểm `Task.isCancelled` trong vòng lặp và ném DAXError .cancelled.
// Nhiều EVALUATE: engine trả mỗi EVALUATE một bảng. Một EVALUATE lỗi thì cả truy vấn lỗi, không có kết quả nào,
// đúng như Power BI (quan sát O5, docs/phase-b-evidence/BUOI1.md).

extension DocumentState {
    var currentDAXTab: DAXQueryTab? {
        daxQueries.indices.contains(daxSelection) ? daxQueries[daxSelection] : nil
    }

    /// Trạng thái chạy của tab đang chọn (nil khi tab chưa chạy lần nào).
    var currentDAXRun: DAXQueryState? {
        currentDAXTab.flatMap { daxRuns[$0.id] }
    }

    var isRunningDAX: Bool { currentDAXRun?.status == .running }

    /// Có thể chạy khi file có mô hình dữ liệu và tab hiện tại có văn bản.
    var canRunDAX: Bool {
        workspace.metadata != nil && !(currentDAXTab?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Chạy tab đang chọn. Nếu editor đang có vùng chọn thì chỉ chạy vùng chọn.
    func runDAXQuery() {
        guard let tab = currentDAXTab, canRunDAX else { return }
        let full = tab.text as NSString
        var text = tab.text
        var offset = 0
        let selection = daxEditorSelection
        if selection.length > 0, NSMaxRange(selection) <= full.length {
            text = full.substring(with: selection)
            offset = selection.location
        }

        let run = daxRuns[tab.id] ?? DAXQueryState(tab: tab)
        daxRuns[tab.id] = run
        daxTasks[tab.id]?.cancel()
        run.beginRun(text: text, offset: offset)

        let workspace = self.workspace
        let id = tab.id
        daxTasks[id] = Task { [weak self] in
            let outcome = await QueryRunner.execute(text, workspace: workspace)
            switch outcome {
            case .success(let result):
                run.finish(result)
            case .failure(let error) where error.kind == .cancelled:
                run.markCancelled()
            case .failure(let error):
                run.fail(error)
            }
            self?.daxTasks[id] = nil
        }
    }

    /// Huỷ lần chạy của tab đang chọn.
    func cancelDAXQuery() {
        guard let tab = currentDAXTab, let task = daxTasks[tab.id] else { return }
        task.cancel()
    }
}

enum QueryRunner {
    /// Tạo engine (lần đầu) và chạy truy vấn, ngoài main thread. Huỷ theo task đang gọi.
    static func execute(_ text: String, workspace: Workspace) async -> Result<QueryResult, DAXError> {
        do {
            let engine = try await Task.detached(priority: .userInitiated) { try workspace.daxEngine() }.value
            if Task.isCancelled { return .failure(DAXError(.cancelled, "Đã huỷ")) }
            return .success(try await engine.execute(text))
        } catch let error as DAXError {
            return .failure(error)
        } catch {
            return .failure(DAXError(.runtime, "\(error)"))
        }
    }
}
