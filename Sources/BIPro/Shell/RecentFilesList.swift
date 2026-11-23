import AppKit
import SwiftUI

/// Một mục tài liệu mở gần đây hiển thị ở màn hình Khởi động và File Backstage.
struct RecentFileEntry: Identifiable, Hashable {
    let url: URL
    let openedAt: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var location: String { url.deletingLastPathComponent().path }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    var canOpen: Bool { exists }

    static func load() -> [RecentFileEntry] {
        var seen = Set<String>()
        var urls: [URL] = []
        let sources = NSDocumentController.shared.recentDocumentURLs + RecentFiles.urls
        for url in sources {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                urls.append(url)
            }
        }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
            let date = values?.contentAccessDate ?? values?.contentModificationDate
            return RecentFileEntry(url: url, openedAt: date)
        }
    }
}

/// Bảng tệp gần đây chuẩn Power BI Desktop (`f_file.png`): Recent / Shared with me, Filter by keyword, bảng Name / Location / Opened.
struct RecentFilesList: View {
    let entries: [RecentFileEntry]
    var onOpen: (URL) -> Void = { url in
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    @Environment(\.isSnapshotRender) private var isSnapshotRender
    @State private var keyword = ""

    private var filtered: [RecentFileEntry] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.name.lowercased().contains(q) || $0.location.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(bi("Gần đây", "Recent"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.canvas)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(DS.Palette.label))

                Button {} label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2")
                            .font(.system(size: 11))
                        Text(bi("Được chia sẻ với tôi", "Shared with me"))
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().strokeBorder(DS.Palette.separator))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help(bi("Tệp chia sẻ từ Power BI Service: chưa hỗ trợ trên BI Pro.",
                         "Shared files from Power BI Service: not supported in BI Pro yet."))

                Spacer()

                filterBox
            }

            // Header row
            HStack(spacing: 12) {
                Text(bi("Tên", "Name"))
                    .frame(width: 220, alignment: .leading)
                Text(bi("Vị trí", "Location"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(bi("Đã mở", "Opened"))
                    .frame(width: 120, alignment: .leading)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DS.Palette.secondaryLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .hairline(.bottom)

            if filtered.isEmpty {
                Text(keyword.isEmpty
                     ? bi("Chưa có tệp .pbix mở gần đây.", "No recently opened .pbix files yet.")
                     : bi("Không có tệp khớp \"\(keyword)\".", "No files match \"\(keyword)\"."))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .padding(14)
            } else if isSnapshotRender {
                VStack(spacing: 0) {
                    ForEach(filtered.prefix(6)) { entry in
                        recentRow(entry)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            recentRow(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var filterBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.tertiaryLabel)
            if isSnapshotRender {
                Text(bi("Lọc theo từ khoá", "Filter by keyword"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer(minLength: 0)
            } else {
                TextField(bi("Lọc theo từ khoá", "Filter by keyword"), text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !keyword.isEmpty {
                    Button { keyword = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 210, height: 26)
        .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator))
    }

    private func recentRow(_ entry: RecentFileEntry) -> some View {
        Button {
            if entry.canOpen { onOpen(entry.url) }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(entry.exists ? Color(hex: "#E6A817")! : DS.Palette.tertiaryLabel)
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(entry.exists ? DS.Palette.label : DS.Palette.tertiaryLabel)
                        .lineLimit(1)
                }
                .frame(width: 220, alignment: .leading)

                Text(entry.location)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(Self.formatDate(entry.openedAt))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 120, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .opacity(entry.exists ? 1 : 0.48)
            .contentShape(Rectangle())
            .hairline(.bottom)
        }
        .buttonStyle(.plain)
        .disabled(!entry.canOpen)
        .help(entry.exists ? entry.url.path : bi("Tệp không còn tồn tại trên đĩa.", "File no longer exists on disk."))
        .accessibilityLabel(entry.name)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func formatDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
