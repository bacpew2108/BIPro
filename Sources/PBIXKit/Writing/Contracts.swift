import Foundation

// Shared contract for the Phase W write path. Owned by the lead; work packages
// implement the signatures in their own files and must not change these types.
// See docs/PHASE_W_PLAN.md §1 and docs/phase-w-ownership.tsv.

/// Errors thrown by the write path.
public enum WriteError: Error, CustomStringConvertible {
    case notImplemented(String)
    case invalid(String)
    case verificationFailed(String)

    public var description: String {
        switch self {
        case .notImplemented(let what): "not implemented: \(what)"
        case .invalid(let message): "invalid write request: \(message)"
        case .verificationFailed(let message): "written file failed verification: \(message)"
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
public struct NewMeasure: Sendable, Equatable {
    public var table: String
    public var name: String
    /// DAX expression without the leading `=`.
    public var expression: String
    public var formatString: String?
    public var displayFolder: String?
    public var description: String?
    public var isHidden: Bool

    public init(table: String, name: String, expression: String, formatString: String? = nil,
                displayFolder: String? = nil, description: String? = nil, isHidden: Bool = false) {
        self.table = table
        self.name = name
        self.expression = expression
        self.formatString = formatString
        self.displayFolder = displayFolder
        self.description = description
        self.isHidden = isHidden
    }
}

/// Everything one save changes.
public struct PBIXChanges: Sendable {
    /// T1: replaced PBIR parts, keyed by ZIP member path.
    public var reportParts: [String: Data] = [:]
    /// T2: measures to add.
    public var measures: [NewMeasure] = []

    public init() {}

    public var tier: SaveTier { measures.isEmpty ? .report : .metadata }
}
