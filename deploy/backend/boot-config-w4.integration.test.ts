// Integration: the boot gates of the process entries (quint/boot_config.qnt, docs/research/quint-findings/boot_config.md).
// Each case starts the real entry (deploy/backend/server.ts or packages/network/service/main.ts) as a child
// process on a migrated database of its own on the dev Postgres (:54339), and reads its exit code and logs.
// Sends are dry-run. Skipped without Postgres.
import { afterAll, describe, expect, test } from "bun:test";
import { resolve } from "node:path";
import { SQL } from "bun";
import { dropDb, migratedDb, pgAvailable } from "../../packages/platform/test/pg.ts";

const REPO = resolve(import.meta.dir, "../..");
const OTP = { OTP_PROVIDER: "twilio", TWILIO_ACCOUNT_SID: "ACfake", TWILIO_AUTH_TOKEN: "fake", TWILIO_VERIFY_SERVICE_SID: "VAfake" };
/** Variables of the parent process that must never reach the child. */
const CLEARED = { NODE_ENV: "", NETWORK_CHANNEL: "", BLOOIO_ALLOW_SEND: "", NTWRK_LIVE_APPROVED: "", SERVICE_TURN_SECRET: "", NETWORK_REVIEW_MODE: undefined,
  PLATFORM_SESSION_SECRET: undefined, LEAK_LABEL_KEY: undefined, NETWORK_DATABASE_URL: undefined, MIGRATION_DATABASE_URL: undefined, NETWORK_SERVICE_TOKENS: undefined };
const urls: string[] = [];
/** A production environment that the proved gate accepted before LEAK_LABEL_KEY was in it. */
const PRODUCTION = { ...OTP, PLATFORM_ENV: "production", TURNSTILE_SECRET_KEY: "fake", PLATFORM_PROXY_SECRET: "s".repeat(40), PLATFORM_HASH_KEY: "h".repeat(40), PLATFORM_SESSION_SECRET: "e".repeat(40) };

/** Starts one entry. Gives the exit code (null when it was still running after `ms` and was killed) and the logs. */
async function run(entry: string[], extra: Record<string, string | undefined>, ms = 20_000) {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries({ ...process.env, ...CLEARED, ...extra })) if (v !== undefined) env[k] = v;
  const proc = Bun.spawn(["bun", "run", ...entry], { cwd: REPO, env, stdout: "pipe", stderr: "pipe" });
  let killed = false;
  const timer = setTimeout(() => { killed = true; proc.kill("SIGKILL"); }, ms);
  const [code, out, err] = await Promise.all([proc.exited, new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  clearTimeout(timer);
  return { code: killed ? null : code, logs: out + err };
}

describe.skipIf(!pgAvailable)("boot gates of the process entries", () => {
  afterAll(async () => { for (const u of urls) await dropDb(u); });

  test("Q-boot_config-W4-1: server.ts refuses PLATFORM_ENV=dev with NODE_ENV=production", async () => {
    const url = await migratedDb("bootw4_devprod");
    urls.push(url);
    const r = await run(["deploy/backend/server.ts"], {
      ...OTP, PLATFORM_ENV: "dev", NODE_ENV: "production", DATABASE_URL: url, PLATFORM_HASH_KEY: "h".repeat(40), TURNSTILE_SECRET_KEY: "fake",
      PORT: "0", BACKEND_STAFF: "off", TICK_MS: "3600000",
    });
    expect(r.code).toBe(1);
    expect(r.logs).toMatch(/start failed.*NODE_ENV=production with PLATFORM_ENV=dev/);
  }, 60_000);

  test("Q-boot_config-W4-3: main.ts refuses production without LEAK_LABEL_KEY, and with a superuser service login", async () => {
    const url = await migratedDb("bootw4_main");
    urls.push(url);
    const sql = new SQL({ url, max: 1 });
    try { await sql`update platform.settings set value = 'production' where key = 'environment'`; } finally { await sql.close(); }
    const main = ["packages/network/service/main.ts", "--once", "--dry-run"];
    const noKey = await run(main, { ...PRODUCTION, DATABASE_URL: url });
    expect(noKey.code).toBe(1);
    expect(noKey.logs).toMatch(/refusing to start.*LEAK_LABEL_KEY/);
    // The dev cluster's own login is a superuser: RLS and the grants would not apply to it.
    const superuser = await run(main, { ...PRODUCTION, DATABASE_URL: url, LEAK_LABEL_KEY: "l".repeat(40) });
    expect(superuser.code).toBe(1);
    expect(superuser.logs).toMatch(/refusing to start.*superuser/);
  }, 90_000);

  test("W3-458: main.ts takes DATABASE_URL when NETWORK_DATABASE_URL is empty, as the gate does", async () => {
    const url = await migratedDb("bootw4_blankurl");
    urls.push(url);
    const r = await run(["packages/network/service/main.ts", "--once", "--dry-run"], { PLATFORM_ENV: "dev", NETWORK_DATABASE_URL: "", DATABASE_URL: url });
    expect(r.logs).not.toMatch(/set NETWORK_DATABASE_URL/);
    expect(r.code).toBe(0);
  }, 60_000);
});
