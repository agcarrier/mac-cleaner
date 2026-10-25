import { sign } from "./license.ts";
import { findByEmailAndReceipt, getPaidSession } from "./stripe.ts";

export interface Env {
  STRIPE_SECRET_KEY: string;
  LICENSE_PRIVATE_KEY: string;
  /** Optional: only sessions from this Payment Link (plink_…) earn a key. */
  PAYMENT_LINK_ID?: string;
}

const COPY_SCRIPT = `document.getElementById("copy").addEventListener("click",e=>{navigator.clipboard.writeText(document.getElementById("key").textContent);e.target.textContent="Copied"})`;
let copyHash: Promise<string> | undefined;
const scriptHash = () => (copyHash ??= crypto.subtle.digest("SHA-256", new TextEncoder().encode(COPY_SCRIPT))
  .then((d) => btoa(String.fromCharCode(...new Uint8Array(d)))));

const escape = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

async function page(title: string, body: string, status = 200, script = false) {
  const csp = `default-src 'none'; style-src 'unsafe-inline'; form-action 'self'${script ? `; script-src 'sha256-${await scriptHash()}'` : ""}`;
  const html = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${escape(title)}</title>
<style>
:root{color-scheme:light dark;--fg:#1d1d1f;--muted:#6e6e73;--bg:#f5f5f7;--card:#fff;--green:#1f9d55}
@media (prefers-color-scheme:dark){:root{--fg:#f5f5f7;--muted:#a1a1a6;--bg:#111;--card:#1c1c1e;--green:#34c759}}
body{margin:0;font:16px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;background:radial-gradient(ellipse at top,color-mix(in srgb,var(--green) 22%,transparent),transparent 60%) var(--bg);color:var(--fg);min-height:100vh}
main{max-width:560px;margin:0 auto;padding:64px 16px}
h1{font-size:28px;margin:0 0 8px}p{color:var(--muted)}
.card{background:var(--card);border-radius:14px;padding:20px;margin:24px 0;box-shadow:0 1px 3px #0002}
code{display:block;word-break:break-all;font:13px ui-monospace,Menlo,monospace;user-select:all}
a.pill,button{display:inline-block;border:0;border-radius:999px;padding:10px 20px;font:inherit;font-weight:600;cursor:pointer;text-decoration:none;margin:12px 8px 0 0}
a.pill{background:var(--green);color:#fff}button{background:color-mix(in srgb,var(--fg) 10%,transparent);color:var(--fg)}
label{display:block;margin-top:12px;font-weight:600}input{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #8886;font:inherit;background:transparent;color:inherit}
</style><main>${body}</main>${script ? `<script>${COPY_SCRIPT}</script>` : ""}</html>`;
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "content-security-policy": csp, "cache-control": "no-store",
               "referrer-policy": "no-referrer", "x-content-type-options": "nosniff" },
  });
}

async function keyPage(sessionID: string, env: Env) {
  const key = await sign(sessionID, env.LICENSE_PRIVATE_KEY);
  return page("Thank you — Spruce", `<h1>Thank you for supporting Spruce</h1>
<p>Your supporter key is below. Open it in Spruce, or copy it and paste it on Spruce's Supporter page.</p>
<div class="card"><code id="key">${escape(key)}</code>
<a class="pill" href="spruce://unlock?key=${escape(encodeURIComponent(key))}">Open in Spruce</a><button id="copy" type="button">Copy</button></div>
<p>Keep this page or the key. It works offline, on any of your Macs, for good.</p>`, 200, true);
}

const notFound = () => page("Not found — Spruce", `<h1>Not found</h1>`, 404);

const findForm = (message = "") => page("Find your key — Spruce", `<h1>Find your supporter key</h1>
<p>Enter the email you paid with and the receipt number from Stripe's receipt email.</p>
${message ? `<p><strong>${escape(message)}</strong></p>` : ""}
<form method="post" class="card"><label for="email">Email</label><input id="email" name="email" type="email" required autocomplete="email">
<label for="receipt">Receipt number</label><input id="receipt" name="receipt" required placeholder="1234-5678">
<button type="submit">Find my key</button></form>`);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/thanks" && request.method === "GET") {
      const session = await getPaidSession(url.searchParams.get("session_id") ?? "", env.STRIPE_SECRET_KEY, env.PAYMENT_LINK_ID);
      if (session) return keyPage(session.id, env);
      return page("Spruce", `<h1>We couldn't find a finished payment</h1>
<p>If you just paid, give it a moment and reload. Already paid before? <a href="/find">Find your key</a>.</p>`, 404);
    }
    if (url.pathname === "/find" && request.method === "GET") return findForm();
    if (url.pathname === "/find" && request.method === "POST") {
      const form = await request.formData().catch(() => null);
      const email = String(form?.get("email") ?? ""), receipt = String(form?.get("receipt") ?? "");
      const session = await findByEmailAndReceipt(email, receipt, env.STRIPE_SECRET_KEY, env.PAYMENT_LINK_ID);
      // One reply for a wrong receipt and an unknown email, so the form can't confirm who has paid.
      return session ? keyPage(session.id, env) : findForm("No payment matches that email and receipt number.");
    }
    return notFound();
  },
};
