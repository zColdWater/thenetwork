// Integration: the NetworkService constructor and start() as the boot model sees them
// (quint/boot_config.qnt `construct`, docs/research/quint-findings/boot_config.md). A migrated database of
// its own on the dev Postgres (:54339). Nothing is sent. Skipped without Postgres.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { SQL } from "bun";
import { SimClock } from "@thenetwork/core";
import { dropDb, migratedDb, pgAvailable } from "../../platform/test/pg.ts";
import { NetworkService, type ServiceOptions } from "../service/service.ts";

const KEY = "k".repeat(40);
let url = "";
const open: NetworkService[] = [];

function service(env: Record<string, string>, more: Partial<ServiceOptions> = {}) {
  const s = new NetworkService({ url, clock: new SimClock(Date.UTC(2026, 10, 11, 16)), instance: "boot-config-w4", photoStorage: null, notify: false,
    log: () => {}, env: { CLEF_RATINGS: "off", ...env }, networks: [{ id: "ntwrk:nyc", matchingEnabled: false }], network: { seed: 1 }, ...more });
  open.push(s);
  return s;
}
async function asOwner(fn: (sql: SQL) => Promise<unknown>) { const sql = new SQL({ url, max: 1 }); try { await fn(sql); } finally { await sql.close(); } }

describe.skipIf(!pgAvailable)("the service boot checks", () => {
  beforeAll(async () => { url = await migratedDb("bootw4_service"); });
  afterAll(async () => { for (const s of open) await s.close().catch(() => {}); if (url) await dropDb(url); });

  test("Q-boot_config-W4-2: a staging service refuses to start when platform.settings has no environment row", async () => {
    await asOwner(sql => sql`delete from platform.settings where key = 'environment'`);
    try {
      await expect(service({ PLATFORM_ENV: "staging", PLATFORM_HASH_KEY: KEY }).start()).rejects.toThrow(/platform\.settings\.environment/);
    } finally {
      await asOwner(sql => sql`insert into platform.settings (key, value) values ('environment', 'dev') on conflict (key) do update set value = 'dev'`);
    }
  }, 60_000);
});
