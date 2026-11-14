import Foundation

/// Edits to `report.json` > `resourcePackages` (VM-D12): when the last page that uses a shape map or an image is deleted,
/// Power BI Desktop drops the item from its package and the file from `Report/StaticResources/`. Like the other patches
/// here, the edit splices bytes (what is not touched stays byte for byte), then re-parses and compares.
///
/// Observed in `docs/phase-d-evidence/vm-d12/QUAN-SAT.md`: `SharedResources` > `ShapeMap` and `RegisteredResources` > `Image`
/// are dropped with the page that alone refers to them (`"ItemName":"<name>"` in a `visual.json` or `page.json`); an item
/// that another page still refers to stays; themes stay.
public enum PBIRResourcePatch {
    public struct Item: Equatable, Sendable {
        public var package: String
        public var name: String
        public var path: String
        public var type: String
        /// The item object exactly as it is in the file.
        public var raw: Data

        /// Part name inside the archive: `Report/StaticResources/<package>/<path>`.
        public var partPath: String { "Report/StaticResources/\(package)/\(path)" }
        /// Key used in sets: `<package>/<name>`.
        public var key: String { "\(package)/\(name)" }
        /// Only these types are dropped with their last page; themes and the like are left alone.
        public var isCleanable: Bool { type == "ShapeMap" || type == "Image" }
        /// How a part of a page refers to it.
        public var reference: String { #""ItemName":"\#(name)""# }
    }

    /// Every item of every package, in file order. Empty when the file has no `resourcePackages`.
    public static func items(in report: Data) -> [Item] {
        let bytes = [UInt8](report)
        guard let packages = JSONCursor.children(at: [.key("resourcePackages")], in: bytes) else { return [] }
        var out: [Item] = []
        for (p, _) in packages.enumerated() {
            let base: [JSONPathStep] = [.key("resourcePackages"), .index(p)]
            guard let nameRange = JSONCursor.locate((base + [.key("name")])[...], in: bytes),
                  let package = JSONCursor.string(in: bytes, nameRange),
                  let kids = JSONCursor.children(at: base + [.key("items")], in: bytes) else { continue }
            for kid in kids {
                let raw = Data(bytes[kid.value])
                guard let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
                      let name = object["name"] as? String, let path = object["path"] as? String, let type = object["type"] as? String else { continue }
                out.append(Item(package: package, name: name, path: path, type: type, raw: raw))
            }
        }
        return out
    }

    /// `report` with each package holding exactly the items of `baseline` (the report as it was opened) whose key is not in
    /// `removing`, in the baseline order, followed by the items only `report` has. Packages absent from `report` are not
    /// created. Returns `report` itself when nothing differs.
    public static func settingItems(removing removed: Set<String>, baseline: Data, in report: Data) throws -> Data {
        let wanted = items(in: baseline)
        let onDisk = items(in: report)
        guard !wanted.isEmpty || !removed.isEmpty else { return report }
        var bytes = [UInt8](report)
        guard let packages = JSONCursor.children(at: [.key("resourcePackages")], in: bytes) else { return report }
        var edits: [(range: Range<Int>, text: [UInt8])] = []
        var expectedByPackage: [String: [String]] = [:]
        for (p, _) in packages.enumerated() {
            let base: [JSONPathStep] = [.key("resourcePackages"), .index(p)]
            guard let nameRange = JSONCursor.locate((base + [.key("name")])[...], in: bytes),
                  let package = JSONCursor.string(in: bytes, nameRange),
                  let itemsRange = JSONCursor.locate((base + [.key("items")])[...], in: bytes) else { continue }
            let current = onDisk.filter { $0.package == package }
            var desired = wanted.filter { $0.package == package && !removed.contains($0.key) }
            let known = Set(wanted.filter { $0.package == package }.map(\.name))
            desired += current.filter { !known.contains($0.name) }
            if desired.map(\.raw) == current.map(\.raw) { continue }
            var text: [UInt8] = [UInt8(ascii: "[")]
            for (i, item) in desired.enumerated() {
                if i > 0 { text.append(UInt8(ascii: ",")) }
                text += [UInt8](item.raw)
            }
            text.append(UInt8(ascii: "]"))
            edits.append((itemsRange, text))
            expectedByPackage[package] = desired.map(\.name)
        }
        guard !edits.isEmpty else { return report }
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }
        let result = Data(bytes)
        // Check: nothing but those item lists changed.
        guard var expected = (try? JSONSerialization.jsonObject(with: report)) as? [String: Any],
              var packagesJSON = expected["resourcePackages"] as? [[String: Any]],
              let actual = (try? JSONSerialization.jsonObject(with: result)) as? [String: Any] else {
            throw WriteError.verificationFailed("report.json is not an object")
        }
        for (i, var package) in packagesJSON.enumerated() {
            guard let name = package["name"] as? String, let names = expectedByPackage[name] else { continue }
            let source = (wanted + onDisk).filter { $0.package == name }
            package["items"] = names.compactMap { itemName in
                source.first { $0.name == itemName }.flatMap { try? JSONSerialization.jsonObject(with: $0.raw) }
            }
            packagesJSON[i] = package
        }
        expected["resourcePackages"] = packagesJSON
        guard (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("resourcePackages splice changed other content")
        }
        return result
    }
}
