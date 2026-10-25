// Prints a new Spruce Supporter signing keypair. Run once: swift tools/make-license-keys.swift
// The private key goes only into the Worker (wrangler secret put); never commit it.
import CryptoKit

let key = Curve25519.Signing.PrivateKey()
print("PRIVATE (wrangler secret put LICENSE_PRIVATE_KEY): \(key.rawRepresentation.base64EncodedString())")
print("PUBLIC (paste into License.swift): \(key.publicKey.rawRepresentation.base64EncodedString())")
