import CryptoKit
import Foundation
import Testing
@testable import MacCleanerCore

private let signer = Curve25519.Signing.PrivateKey()

@Test func roundTrip() {
    let key = License.make(sessionID: "cs_test_1", signer: signer)
    #expect(key.hasPrefix("SPRUCE-"))
    #expect(License.verify(key, with: signer.publicKey))
}

@Test func tamperedFails() {
    let key = License.make(sessionID: "cs_test_1", signer: signer)
    let dot = key.lastIndex(of: ".")!
    func flip(_ i: String.Index) -> String {
        var chars = Array(key)
        let n = key.distance(from: key.startIndex, to: i)
        chars[n] = chars[n] == "A" ? "B" : "A"
        return String(chars)
    }
    #expect(!License.verify(flip(key.index(key.startIndex, offsetBy: 9)), with: signer.publicKey))  // payload
    #expect(!License.verify(flip(key.index(after: dot)), with: signer.publicKey))                    // signature
}

@Test func wrongKeyFails() {
    let key = License.make(sessionID: "cs_test_1", signer: signer)
    #expect(!License.verify(key, with: Curve25519.Signing.PrivateKey().publicKey))
}

@Test func otherPayloadFails() throws {
    let payload = Data("other-app|1|x".utf8)
    let sig = try signer.signature(for: payload)
    let key = "SPRUCE-" + payload.base64URL + "." + sig.base64URL
    #expect(!License.verify(key, with: signer.publicKey))
    // The right prefix with an empty session id is no key either.
    let empty = Data("spruce-supporter|1|".utf8)
    #expect(!License.verify("SPRUCE-" + empty.base64URL + "." + (try signer.signature(for: empty)).base64URL,
                            with: signer.publicKey))
}

@Test func keyWithWhitespaceVerifies() {
    var key = License.make(sessionID: "cs_test_1", signer: signer)
    key.removeFirst("SPRUCE-".count)
    key.insert(contentsOf: "\n  ", at: key.index(key.startIndex, offsetBy: 10))
    #expect(License.verify("  " + key + "\n", with: signer.publicKey))
}

@Test func garbageFails() {
    for key in ["", "SPRUCE-", "SPRUCE-abc", "hello", "SPRUCE-.", "SPRUCE-!!!.???"] {
        #expect(!License.verify(key, with: signer.publicKey), "\(key)")
    }
}

/// The Worker signs, Spruce verifies: this vector comes from `server/` (`npm run vector`).
@Test func workerVectorVerifies() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "license-vector.json")
    let vector = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: vector["publicKey"]!)!)
    #expect(License.verify(vector["key"]!, with: publicKey))
    #expect(License.payload(sessionID: vector["sessionID"]!) == "spruce-supporter|1|cs_test_vector")
}
