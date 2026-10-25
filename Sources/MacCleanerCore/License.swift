import CryptoKit
import Foundation

/// Spruce Supporter keys: `SPRUCE-<base64url(payload)>.<base64url(Ed25519 signature)>`, signed by the Worker in `server/`
/// after Stripe confirms payment, verified here offline. The payload names a purchase, never a person.
public enum License {
    /// Placeholder until Andrew runs `swift tools/make-license-keys.swift`; its private half was never saved.
    static let publicKeyBase64 = "JBWPvsG2HsnZeH/ZsV5P+r5aaLOPy6t5zLwDK+YnCDI="
    public static let publicKey = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKeyBase64)!)

    static let prefix = "SPRUCE-"
    static let payloadPrefix = "spruce-supporter|1|"

    public static func payload(sessionID: String) -> String { payloadPrefix + sessionID }

    public static func make(sessionID: String, signer: Curve25519.Signing.PrivateKey) -> String {
        let payload = Data(payload(sessionID: sessionID).utf8)
        return prefix + payload.base64URL + "." + (try! signer.signature(for: payload)).base64URL
    }

    /// Trims, drops all whitespace (email clients wrap long strings) and restores a missing prefix.
    public static func normalize(_ key: String) -> String {
        let compact = key.filter { !$0.isWhitespace }
        return compact.hasPrefix(prefix) ? compact : prefix + compact
    }

    public static func verify(_ key: String, with publicKey: Curve25519.Signing.PublicKey = License.publicKey) -> Bool {
        let body = normalize(key).dropFirst(prefix.count)
        guard let dot = body.lastIndex(of: "."),
              let payload = Data(base64URL: body[..<dot]),
              let signature = Data(base64URL: body[body.index(after: dot)...]),
              let text = String(data: payload, encoding: .utf8),
              text.hasPrefix(payloadPrefix), text.count > payloadPrefix.count
        else { return false }
        return publicKey.isValidSignature(signature, for: payload)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL text: Substring) {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }
}
