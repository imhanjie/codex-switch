import Foundation

enum Base64URL {
    static func encode(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) throws -> Data {
        let base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = String(repeating: "=", count: (4 - (base64.count % 4)) % 4)
        guard let data = Data(base64Encoded: base64 + padding) else {
            throw CodexSwitchError("无法解析 JWT payload")
        }
        return data
    }
}
