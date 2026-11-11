// Integration: the boot gates of the process entries (quint/boot_config.qnt, docs/research/quint-findings/boot_config.md).
// Each case starts the real entry (deploy/backend/server.ts or packages/network/service/main.ts) as a child
// process on a migrated database of its own on the dev Postgres (:54339), and reads its exit code and logs.
// Sends are dry-run. Skipped without Postgres.
import { afterAll, describe, expect, test } from "bun:test";
import { resolve } from "node:path";
import { dropDb, migratedDb, pgAvailable } from "../../packages/platform/test/pg.ts";

const REPO = resolve(import.meta.dir, "../..");
const OTP = { OTP_PROVIDER: "twilio", TWILIO_ACCOUNT_SID: "ACfake", TWILIO_AUTH_TOKEN: "fake", TWILIO_VERIFY_SERVICE_SID: "VAfake" };
/** Variables of the parent process that must never reach the child. */
const CLEARED = { NODE_ENV: "", NETWORK_CHANNEL: "", BLOOIO_ALLOW_SEND: "", NTWRK_LIVE_APPROVED: "", SERVICE_TURN_SECRET: "", NETWORK_REVIEW_MODE: undefined,
  PLATFORM_SESSION_SECRET: undefined, LEAK_LABEL_KEY: undefined, NETWORK_DATABASE_URL: undefined, MIGRATION_DATABASE_URL: undefined, NETWORK_SERVICE_TOKENS: undefined };
const urls: string[] = [];

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
});
