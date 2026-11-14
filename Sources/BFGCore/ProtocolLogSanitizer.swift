import Foundation

/// Defense in depth for both direct TX logs and echoed authentication frames.
public enum ProtocolLogSanitizer {
    private static let authentication = try! NSRegularExpression(
        pattern: "(?i)(5aa5[0-9a-f]{6}(?:5b|5c|5d)[0-9a-f]{2})[0-9a-f]*")

    public static func sanitize(_ line: String) -> String {
        let text = line.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        if text.hasPrefix("PRE_COMM RX plain=") {
            return "PRE_COMM reply received; authentication material hidden"
        }
        return authentication.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: "$1[authentication-payload-hidden]")
    }
}
