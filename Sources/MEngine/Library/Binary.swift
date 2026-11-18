// Đợt tồn đọng sau Phase F, T026: giá trị nhị phân cho M của Enter Data (VM-F11a, docs/phase-f2-evidence/vm-f11/QUAN-SAT.md mục a):
// `Binary.FromText("…", BinaryEncoding.Base64)` rồi `Binary.Decompress(…, Compression.Deflate)` (Deflate thô, không header zlib) rồi
// `Json.Document`. Hằng số theo tài liệu M: BinaryEncoding.Base64 0, Hex 1; Compression.GZip 0, Deflate 1.
import Compression
import Foundation

enum BinaryLibrary {
    static let functions: [MFunction] = [fromText, decompress]

    static func constant(named name: String) -> MValue? {
        switch name {
        case "BinaryEncoding.Base64", "Compression.GZip": .number(0)
        case "BinaryEncoding.Hex", "Compression.Deflate": .number(1)
        default: nil
        }
    }

    /// `Binary.FromText(text, encoding?)`: mặc định Base64.
    static let fromText = MFunction(
        name: "Binary.FromText", parameters: [MParameter(name: "text"), MParameter(name: "encoding", isOptional: true)], observed: true
    ) { args in
        let text = try args.text(0, "Binary.FromText")
        switch try args.optional(1).map({ try MInt.from(MOperators.number($0) ?? -1, "Binary.FromText") }) ?? 0 {
        case 0:
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters), !(data.isEmpty && !text.isEmpty) else {
                throw MError(reason: "DataFormat.Error", message: "Binary.FromText: chuỗi không phải Base64 hợp lệ")
            }
            return .binary(data)
        case 1:
            let digits = Array(text.utf8)
            guard digits.count.isMultiple(of: 2) else { throw MError(reason: "DataFormat.Error", message: "Binary.FromText: chuỗi Hex lẻ ký tự") }
            var bytes: [UInt8] = []
            for i in stride(from: 0, to: digits.count, by: 2) {
                guard let byte = UInt8(String(decoding: digits[i...i + 1], as: UTF8.self), radix: 16) else {
                    throw MError(reason: "DataFormat.Error", message: "Binary.FromText: chuỗi không phải Hex hợp lệ")
                }
                bytes.append(byte)
            }
            return .binary(Data(bytes))
        default:
            throw MError.expression("Binary.FromText: encoding không hợp lệ")
        }
    }

    /// `Binary.Decompress(binary, compressionType)`: chỉ `Compression.Deflate` (Deflate thô, `COMPRESSION_ZLIB` của Apple).
    static let decompress = MFunction(
        name: "Binary.Decompress", parameters: [MParameter(name: "binary"), MParameter(name: "compressionType")], observed: true
    ) { args in
        guard case .binary(let data) = args[0] else {
            throw MError.expression("Binary.Decompress: đối số 1 phải là binary, nhận \(args[0].kindName)")
        }
        guard try MInt.from(MOperators.number(args[1]) ?? -1, "Binary.Decompress") == 1 else {
            throw MError.unsupported("Binary.Decompress với kiểu nén khác Compression.Deflate")
        }
        return .binary(try MBinary.inflate(data))
    }
}

/// Deflate thô (không header zlib) như `Compression.Deflate` của M, dùng `COMPRESSION_ZLIB` của Apple. BIPro dùng để dựng M Enter Data.
public enum MBinary {
    /// Nén. Với bảng nhỏ của VM-F11 kết quả trùng từng byte với Desktop (zlib mọi mức); bảng lớn có thể khác byte mà vẫn giải được.
    public static func deflate(_ data: Data) -> Data { (try? process(data, operation: COMPRESSION_STREAM_ENCODE)) ?? Data() }

    /// Giải nén; dữ liệu hỏng thì `MError` `DataFormat.Error`.
    public static func inflate(_ data: Data) throws -> Data { try process(data, operation: COMPRESSION_STREAM_DECODE) }

    private static func process(_ data: Data, operation: compression_stream_operation) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw MError.expression("Binary: không khởi tạo được bộ nén")
        }
        defer { compression_stream_destroy(stream) }
        let chunk = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var output = Data()
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data in
            stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(buffer)
            stream.pointee.src_size = raw.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: chunk - stream.pointee.dst_size)
                switch status {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return output
                default: throw MError(reason: "DataFormat.Error", message: "Binary.Decompress: dữ liệu nén Deflate hỏng")
                }
            }
        }
    }
}
