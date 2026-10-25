// Writes test/vector.json and the Swift copy. The key below is a test key, used only by tests; never deploy it.
import { writeFileSync } from "node:fs";
import { publicKeyOf, sign } from "../src/license.ts";

export const TEST_PRIVATE_KEY = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A=";

if (import.meta.url === `file://${process.argv[1]}`) {
  const vector = { publicKey: await publicKeyOf(TEST_PRIVATE_KEY), sessionID: "cs_test_vector",
                   key: await sign("cs_test_vector", TEST_PRIVATE_KEY) };
  const json = JSON.stringify(vector, null, 2) + "\n";
  writeFileSync(new URL("./vector.json", import.meta.url), json);
  writeFileSync(new URL("../../Tests/MacCleanerCoreTests/license-vector.json", import.meta.url), json);
  console.log(json);
}
