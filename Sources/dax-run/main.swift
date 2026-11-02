// dax-run: CLI của engine DAX (lead). `bench` từ đợt 1a (CS), `query` chờ đợt 2 (QRY).
import DAXEngine
import Foundation

let usage = """
dùng: dax-run <lệnh> [tham số]
  help                                  hiện trợ giúp này
  bench <file.pbix> [--verify]          đo thời gian nạp cột (--verify: đối chiếu distinct count)
  measures-run <file.pbix> <measures.tsv> <out.tsv> [--per-measure-timeout GIÂY] [--limit N]
                                        đánh giá từng measure, ghi từng dòng, có giới hạn thời gian
  query <file.pbix> <out-dir> <a.dax> [b.dax ...] [--timeout GIÂY]
                                        chạy truy vấn DAX, ghi <out-dir>/<tên>.engine.tsv (ô dạng KIỂU:giá trị)
"""

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "help"

switch command {
case "help", "-h", "--help":
    print(usage)
case "bench":
    exit(runBenchCommand(arguments: Array(arguments.dropFirst())))
case "measures-run":
    exit(runMeasuresCommand(arguments: Array(arguments.dropFirst())))
case "query":
    exit(runQueryCommand(arguments: Array(arguments.dropFirst())))
default:
    FileHandle.standardError.write(Data("lệnh chưa có: \(command)\n\(usage)\n".utf8))
    exit(2)
}
