import Foundation

/// Just enough HTTP/1.1 to serve curl on loopback.
public struct HTTPRequest {
    public let method: String
    public let path: String
    public let body: Data

    /// nil while the request is still incomplete or malformed.
    public static func parse(_ data: Data) -> HTTPRequest? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<sep.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let body = data[sep.upperBound...]
        guard body.count >= length else { return nil }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), body: Data(body.prefix(length)))
    }

    /// Claude Code's hook JSON carries `session_id`; anything else counts as a manual poke.
    public var sessionID: String {
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let s = obj["session_id"] as? String, !s.isEmpty { return s }
        return "manual"
    }
}
