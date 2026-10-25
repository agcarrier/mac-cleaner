// Replaces fetch with a tiny fake of the two Stripe endpoints the Worker calls.
import { vi } from "vitest";

export type FakeSession = { id: string; payment_status: string; email: string; receipt: string; payment_link?: string };

export function stubStripe(sessions: FakeSession[]) {
  const calls: string[] = [];
  vi.stubGlobal("fetch", async (input: string) => {
    const url = new URL(input);
    calls.push(url.pathname + url.search);
    const shape = (s: FakeSession) => ({
      id: s.id, object: "checkout.session", payment_status: s.payment_status, payment_link: s.payment_link ?? null,
      customer_details: { email: s.email },
      payment_intent: { id: "pi_1", latest_charge: { id: "ch_1", receipt_number: s.receipt } },
    });
    const one = url.pathname.match(/^\/v1\/checkout\/sessions\/(.+)$/);
    if (one) {
      const s = sessions.find((s) => s.id === decodeURIComponent(one[1]));
      return s ? Response.json(shape(s)) : Response.json({ error: { message: "No such checkout.session" } }, { status: 404 });
    }
    if (url.pathname === "/v1/checkout/sessions") {
      const email = url.searchParams.get("customer_details[email]");
      return Response.json({ object: "list", has_more: false, data: sessions.filter((s) => s.email === email).map(shape) });
    }
    return new Response("not found", { status: 404 });
  });
  return calls;
}
