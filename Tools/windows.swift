import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "") ?? -1
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w["kCGWindowOwnerName"] as? String) == "Framecast" {
    if pid >= 0, (w["kCGWindowOwnerPID"] as? Int) != pid { continue }
    let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
    print(w["kCGWindowNumber"] ?? "", b["Width"] ?? "", b["Height"] ?? "")
}
