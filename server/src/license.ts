// Spruce Supporter keys: SPRUCE-<base64url(payload)>.<base64url(Ed25519 signature)>, verified offline by
// Sources/MacCleanerCore/License.swift. Ed25519 signatures are deterministic, so a session always gets the same key.

const PKCS8_ED25519 = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20]);

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const b64url = (bytes: Uint8Array) => b64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

/** The private key is the raw 32-byte seed, base64 (what tools/make-license-keys.swift prints). */
function importKey(privateKeyB64: string) {
  const seed = unb64(privateKeyB64);
  if (seed.length !== 32) throw new Error("LICENSE_PRIVATE_KEY must be a 32-byte base64 seed");
  const pkcs8 = new Uint8Array(PKCS8_ED25519.length + 32);
  pkcs8.set(PKCS8_ED25519);
  pkcs8.set(seed, PKCS8_ED25519.length);
  return crypto.subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, true, ["sign"]);
}

export async function sign(sessionID: string, privateKeyB64: string): Promise<string> {
  const payload = new TextEncoder().encode(`spruce-supporter|1|${sessionID}`);
  const signature = new Uint8Array(await crypto.subtle.sign("Ed25519", await importKey(privateKeyB64), payload));
  return `SPRUCE-${b64url(payload)}.${b64url(signature)}`;
}

/** The raw public key, base64 — what License.swift embeds. Used by the vector tool. */
export async function publicKeyOf(privateKeyB64: string): Promise<string> {
  const jwk = await crypto.subtle.exportKey("jwk", await importKey(privateKeyB64)) as JsonWebKey;
  return b64(unb64(jwk.x!.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - jwk.x!.length % 4) % 4)));
}
