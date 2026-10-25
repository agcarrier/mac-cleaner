import CryptoKit
import Foundation
import Testing
import MacCleanerCore
@testable import SpruceKit

private let signer = Curve25519.Signing.PrivateKey()

private func freshDefaults() -> UserDefaults {
    let name = "SupporterTests-\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor @Test func unlockStoresOnlyValidKeys() {
    let defaults = freshDefaults()
    let model = SupporterModel(defaults: defaults, publicKey: signer.publicKey)
    #expect(!model.isSupporter)
    #expect(!model.unlock("SPRUCE-nonsense"))
    #expect(!model.isSupporter)
    #expect(defaults.string(forKey: SupporterModel.defaultsKey) == nil)

    let key = License.make(sessionID: "cs_test_1", signer: signer)
    #expect(model.unlock("  " + key.dropFirst("SPRUCE-".count) + "\n"))  // pasted, wrapped, prefix lost
    #expect(model.isSupporter)
    #expect(defaults.string(forKey: SupporterModel.defaultsKey) == key)
}

@MainActor @Test func supporterSurvivesRelaunch() {
    let defaults = freshDefaults()
    _ = SupporterModel(defaults: defaults, publicKey: signer.publicKey).unlock(License.make(sessionID: "cs_1", signer: signer))
    #expect(SupporterModel(defaults: defaults, publicKey: signer.publicKey).isSupporter)
}

@MainActor @Test func badStoredKeyIsNotSupporter() {
    let defaults = freshDefaults()
    defaults.set("garbage", forKey: SupporterModel.defaultsKey)
    #expect(!SupporterModel(defaults: defaults, publicKey: signer.publicKey).isSupporter)
    // A real key from another keypair (another build's test key) doesn't count either.
    defaults.set(License.make(sessionID: "cs_1", signer: Curve25519.Signing.PrivateKey()), forKey: SupporterModel.defaultsKey)
    #expect(!SupporterModel(defaults: defaults, publicKey: signer.publicKey).isSupporter)
    defaults.set(42, forKey: SupporterModel.defaultsKey)
    #expect(!SupporterModel(defaults: defaults, publicKey: signer.publicKey).isSupporter)
}

@Test func urlParsing() {
    #expect(unlockKey(from: URL(string: "spruce://unlock?key=X")!) == "X")
    #expect(unlockKey(from: URL(string: "spruce://unlock?key=SPRUCE-a%2Bb.c")!) == "SPRUCE-a+b.c")
    #expect(unlockKey(from: URL(string: "spruce://other?key=X")!) == nil)
    #expect(unlockKey(from: URL(string: "https://unlock?key=X")!) == nil)
    #expect(unlockKey(from: URL(string: "spruce://unlock")!) == nil)
    #expect(unlockKey(from: URL(string: "spruce://unlock?key=")!) == nil)
}
