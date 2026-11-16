import Foundation

// Shared contract for the Phase W write path. Owned by the lead; work packages
// implement the signatures in their own files and must not change these types.
// See docs/PHASE_W_PLAN.md §1 and docs/phase-w-ownership.tsv.

/// Errors thrown by the write path.
public enum WriteError: Error, CustomStringConvertible {
    case notImplemented(String)
    case invalid(String)
    case verificationFailed(String)
    case backupFailed(String)

    public var description: String {
        switch self {
        case .notImplemented(let what): "not implemented: \(what)"
        case .invalid(let message): "invalid write request: \(message)"
        case .verificationFailed(let message): "written file failed verification: \(message)"
        case .backupFailed(let message): "could not keep a backup of the previous file: \(message)"
        }
    }
}

/// Save tiers (docs/BIPRO_BUILD_PLAN.md §2). The lowest tier that covers the change is used.
public enum SaveTier: Int, Sendable, Comparable {
    /// T1: PBIR parts only. The DataModel member is copied byte-for-byte.
    case report = 1
    /// T2: metadata.sqlitedb changed. ABF is rebuilt and recompressed; VertiPaq data is kept.
    case metadata = 2
    /// T3: VertiPaq tables added or changed.
    case data = 3

    public static func < (lhs: SaveTier, rhs: SaveTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A file to add to or replace in the ABF backup.
public struct ABFPayload: Sendable, Equatable {
    /// Path as printed by `pbix-dump files`, e.g. `metadata.sqlitedb`.
    public var path: String
    public var data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// A measure to add to the model (T2).
public struct NewMeasure: Sendable, Hashable {
    public var table: String
    public var name: String
    /// DAX expression without the leading `=`.
    public var expression: String
    public var formatString: String?
    public var displayFolder: String?
    public var description: String?
    public var isHidden: Bool
    /// AMO `DataType` của kết quả (Int64 6, Double 8, ...). `nil`: dùng `MetadataWriter.measureDataType`.
    public var dataType: Int?

    public init(table: String, name: String, expression: String, formatString: String? = nil,
                displayFolder: String? = nil, description: String? = nil, isHidden: Bool = false, dataType: Int? = nil) {
        self.table = table
        self.name = name
        self.expression = expression
        self.formatString = formatString
        self.displayFolder = displayFolder
        self.description = description
        self.isHidden = isHidden
        self.dataType = dataType
    }
}

/// Everything one save changes.
public struct PBIXChanges: Sendable {
    /// T1: replaced PBIR parts, keyed by ZIP member path. Each path must already exist.
    public var reportParts: [String: Data] = [:]
    /// T1: PBIR parts to add, keyed by ZIP member path. Each path must not exist yet.
    /// A part is placed right after the last member of the same page's `visuals/` folder.
    public var addedParts: [String: Data] = [:]
    /// T1: ZIP member paths to drop. Each path must exist, and must not also be replaced.
    public var removedParts: Set<String> = []
    /// T2: measures to add (kept for older callers; same as `.addMeasure` edits placed before `modelEdits`).
    public var measures: [NewMeasure] = []
    /// T2: model edits (Phase E), applied to `metadata.sqlitedb` in order after `measures`.
    public var modelEdits = ModelEdits()
    /// Replaces the `DiagramLayout` member (UTF-16LE JSON). The member must exist. Does not touch the DataModel.
    public var diagramLayout: Data?
    /// T084: giá trị đã tính của cột tính toán và cột của bảng tính toán trong `modelEdits`, khoá `Bảng[Cột]`.
    public var calculatedData: [String: VertiPaqWriter.Values] = [:]

    public init() {}

    public var tier: SaveTier { measures.isEmpty && modelEdits.isEmpty ? .report : max(.metadata, modelEdits.tier) }

    /// True when the DataModel member is rebuilt.
    var changesModel: Bool { !measures.isEmpty || !modelEdits.isEmpty }

    /// `measures` and `modelEdits` as one ordered list.
    var allModelEdits: ModelEdits {
        var all = ModelEdits(measures.map { .addMeasure($0) })
        for edit in modelEdits.items { all.append(edit) }
        return all
    }

    /// True when any `Report/definition/**` part is replaced, added or removed. Power BI Desktop then refuses a
    /// file that still carries the old `SecurityBindings` ("This file is corrupted..."), so the writer drops that
    /// member and its `[Content_Types].xml` override (measured on the VM, 2026-11-10).
    public var changesReport: Bool { !reportParts.isEmpty || !addedParts.isEmpty || !removedParts.isEmpty }
}

/// What `PBIXWriter.save` does with the file it is about to replace.
public enum BackupPolicy: Sendable {
    /// Keep `<name>.pbix.bak` next to the file, only the first time (the CLI behaviour).
    case sideBak
    /// Copy the previous file into this folder as `<hash of its path>-<name>`, replacing any older copy.
    case directory(URL)
    case none
}
