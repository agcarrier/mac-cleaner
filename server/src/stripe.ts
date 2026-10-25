// The two read-only Stripe calls. The key is restricted: read Checkout Sessions, PaymentIntents and Charges.

export type Session = {
  id: string;
  payment_status: string;
  payment_link: string | null;
  customer_details: { email: string | null } | null;
  payment_intent: { latest_charge: { receipt_number: string | null } | null } | null;
};

async function stripe(path: string, key: string): Promise<any | null> {
  const res = await fetch(`https://api.stripe.com${path}`, { headers: { Authorization: `Bearer ${key}` } });
  return res.ok ? res.json() : null;
}

const isOurs = (s: Session, paymentLink?: string) => s.payment_status === "paid" && (!paymentLink || s.payment_link === paymentLink);

/** The session, only when it's paid (and from Spruce's Payment Link, when one is configured). */
export async function getPaidSession(id: string, key: string, paymentLink?: string): Promise<Session | null> {
  if (!/^cs_[A-Za-z0-9_]+$/.test(id)) return null;
  const s: Session | null = await stripe(`/v1/checkout/sessions/${id}`, key);
  return s && isOurs(s, paymentLink) ? s : null;
}

const normalReceipt = (r: string) => r.trim().replace(/^#/, "").toLowerCase();

/** Both factors must match: the purchase email and the receipt number from the receipt email. */
export async function findByEmailAndReceipt(email: string, receipt: string, key: string, paymentLink?: string): Promise<Session | null> {
  const wanted = normalReceipt(receipt);
  email = email.trim().toLowerCase();
  if (!wanted || !email) return null;
  const q = new URLSearchParams({ "customer_details[email]": email, limit: "100", "expand[]": "data.payment_intent.latest_charge" });
  const list = await stripe(`/v1/checkout/sessions?${q}`, key);
  return (list?.data as Session[] | undefined)?.find((s) =>
    isOurs(s, paymentLink) && normalReceipt(s.payment_intent?.latest_charge?.receipt_number ?? "") === wanted) ?? null;
}
