import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index.ts";
import { sign } from "../src/license.ts";
import vector from "./vector.json" with { type: "json" };
import { TEST_PRIVATE_KEY } from "./make-vector.ts";
import { stubStripe } from "./stripe-stub.ts";

const env = { STRIPE_SECRET_KEY: "rk_test_x", LICENSE_PRIVATE_KEY: TEST_PRIVATE_KEY };
const get = (path: string) => worker.fetch(new Request("https://spruce.test" + path), env);
const findPost = (email: string, receipt: string) =>
  worker.fetch(new Request("https://spruce.test/find", { method: "POST", body: new URLSearchParams({ email, receipt }) }), env);
const keyIn = (html: string) => html.match(/SPRUCE-[A-Za-z0-9_\-.]+/)?.[0];

afterEach(() => vi.unstubAllGlobals());

describe("license", () => {
  it("signMatchesVector", async () => {
    expect(await sign(vector.sessionID, TEST_PRIVATE_KEY)).toBe(vector.key);
  });
});

describe("thanks", () => {
  it("thanksIsDeterministic", async () => {
    stubStripe([{ id: "cs_test_vector", payment_status: "paid", email: "a@b.c", receipt: "1111-2222" }]);
    const one = await (await get("/thanks?session_id=cs_test_vector")).text();
    const two = await (await get("/thanks?session_id=cs_test_vector")).text();
    expect(keyIn(one)).toBe(vector.key);
    expect(keyIn(two)).toBe(vector.key);
    expect(one).toContain("spruce://unlock?key=" + encodeURIComponent(vector.key));
  });

  it("unpaidSessionGetsNoKey", async () => {
    stubStripe([{ id: "cs_unpaid", payment_status: "unpaid", email: "a@b.c", receipt: "1" }]);
    for (const id of ["cs_unpaid", "cs_missing", ""]) {
      const html = await (await get("/thanks?session_id=" + id)).text();
      expect(html).toContain("We couldn't find a finished payment");
      expect(html).not.toContain("SPRUCE-");
    }
  });

  it("ignoresOtherPaymentLinks", async () => {
    stubStripe([{ id: "cs_other", payment_status: "paid", email: "a@b.c", receipt: "1", payment_link: "plink_other" }]);
    const res = await worker.fetch(new Request("https://spruce.test/thanks?session_id=cs_other"),
      { ...env, PAYMENT_LINK_ID: "plink_spruce" });
    expect(await res.text()).not.toContain("SPRUCE-");
  });

  it("escapesInput", async () => {
    stubStripe([]);
    const html = await (await get("/thanks?session_id=" + encodeURIComponent("<script>alert(1)</script>"))).text();
    expect(html).not.toContain("<script>alert");
  });

  it("sendsCSP", async () => {
    stubStripe([]);
    expect((await get("/thanks?session_id=x")).headers.get("content-security-policy")).toContain("default-src 'none'");
  });
});

describe("find", () => {
  it("findNeedsReceiptNumber", async () => {
    stubStripe([{ id: "cs_test_vector", payment_status: "paid", email: "a@b.c", receipt: "1111-2222" }]);
    const wrong = await (await findPost("a@b.c", "9999-0000")).text();
    const unknown = await (await findPost("nobody@b.c", "1111-2222")).text();
    expect(wrong).toBe(unknown);
    expect(wrong).not.toContain("SPRUCE-");
    expect(keyIn(await (await findPost("a@b.c", "#1111-2222")).text())).toBe(vector.key);
    expect(keyIn(await (await findPost(" A@B.c ", "1111-2222")).text())).toBe(vector.key);
  });

  it("emptyReceiptNeverMatches", async () => {
    stubStripe([{ id: "cs_x", payment_status: "paid", email: "a@b.c", receipt: "" }]);
    expect(await (await findPost("a@b.c", "")).text()).not.toContain("SPRUCE-");
  });

  it("showsForm", async () => {
    expect(await (await get("/find")).text()).toContain('<form method="post"');
  });
});

it("everythingElse404s", async () => {
  expect((await get("/")).status).toBe(404);
  expect((await get("/admin")).status).toBe(404);
});
