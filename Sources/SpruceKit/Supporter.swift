import CryptoKit
import Foundation
import Observation
import MacCleanerCore

/// Whether this Mac has a valid Spruce Supporter key. Checked locally against the embedded public key; Spruce never
/// asks a server. Unlocks thank-you extras only, never a tool.
@MainActor @Observable
public final class SupporterModel {
    public static let defaultsKey = "supporterKey"
    /// Spruce's Stripe Payment Link (pay what you want, $3 minimum).
    public static let paymentLink = URL(string: "https://buy.stripe.com/8x2dRa1usdWd7pdfeIbsc01")!
    public static let findKeyPage = URL(string: "https://spruce.andrewcarrier.dev/find")!
    public static let directLine = URL(string: "mailto:andrew@carrierpigeonai.dev?subject=Spruce%20idea")!

    public private(set) var isSupporter: Bool

    private let defaults: UserDefaults
    private let publicKey: Curve25519.Signing.PublicKey

    public init(defaults: UserDefaults = .standard, publicKey: Curve25519.Signing.PublicKey = License.publicKey) {
        self.defaults = defaults
        self.publicKey = publicKey
        isSupporter = defaults.string(forKey: Self.defaultsKey).map { License.verify($0, with: publicKey) } ?? false
    }

    /// Stores the key only when it verifies. Returns whether it did.
    @discardableResult
    public func unlock(_ key: String) -> Bool {
        guard License.verify(key, with: publicKey) else { return false }
        defaults.set(License.normalize(key), forKey: Self.defaultsKey)
        isSupporter = true
        return true
    }
}

/// The key from `spruce://unlock?key=…`, the scheme's only action. Anything else is ignored.
public func unlockKey(from url: URL) -> String? {
    guard url.scheme == "spruce", url.host() == "unlock",
          let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "key" })?.value,
          !key.isEmpty
    else { return nil }
    return key
}
