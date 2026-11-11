// -*- mode: Bluespec; -*-
// quint-check: max-steps=20 max-samples=3000
//
// boot_config: a platform process starts only with a complete configuration (fail closed), the dev
// shortcuts run only in a declared dev environment that does not say production, and the four Pages
// projects keep a proxy secret that the backend accepts.
//
// WHAT THIS MODELS
//   Part A, the process. Four entry points, each with the gate its code runs NOW:
//   - main.ts (packages/network/service/main.ts:31): assertBootConfig, so bootConfigProblems and the
//     LemmaScript functions of packages/platform/src/env-core.ts (declaredEnv, productionEnv,
//     devAllowed, deployedReady, bootProblems; each is a pure def here with the same decision). Then
//     main.ts:34-35 reads the database URL with `??` (W3-458).
//   - server.ts (deploy/backend/server.ts:31; the production entry: Dockerfile CMD, railway.toml). It
//     runs backend.ts loadConfig (backend.ts:85-113), which calls only requirePlatformEnv and its own
//     checks; NO production path calls bootProblems (W3-448). Then server.ts:44-51 moves
//     platform.settings.environment from 'dev' to PLATFORM_ENV once (PLATFORM_DB_ENVIRONMENT_INIT=1,
//     deployed only), and server.ts:57-60 refuses a superuser, BYPASSRLS or owner login (deployed only).
//   - scripts/platform-dev.ts: no gate. It refuses isProduction (:45), then WRITES process.env
//     (PLATFORM_ENV ??= "dev" at :47, PLATFORM_PROXY_SECRET ||= 32 random bytes at :61) before it builds
//     the service. `snap` is the environment the callers read after these writes (W3-452).
//   - packages/mcp/src/dev-server.ts:11: devShortcutsAllowed() only, memory stores, no service.
//   After the gate, the NetworkService constructor, its public API (built at boot by server.ts:93) and
//   start() can still refuse (W3-454): the review option (service.ts:336), SERVICE_TURN_SECRET
//   (service.ts:104-110,343), the hash key (service.ts:348, api.ts:133), the OTP provider
//   (otp.ts:110-115: the console provider outside dev throws), the Turnstile verifier (turnstile.ts:47:
//   the bypass outside dev throws) and the database environment row (service.ts:518-521).
//   A refused start exits 1. Railway restarts ON_FAILURE at most 5 times (railway.toml), then the
//   service stays down until a new deployment (W3-455).
//   Each caller of devShortcutsAllowed is one shortcut kind with the guard its code uses (W3-456).
//
//   Part B, the sites deploy workflow (.github/workflows/deploy-sites.yml, M-148) and the proxy secret
//   rotation of docs/deploy.md 3.4 (M-131) for each of the four Pages projects (W3-344). Per project:
//   the stored bindings (PLATFORM_PROXY_SECRET, BACKEND_ORIGIN), the bindings of the running
//   deployment (a binding applies from the next deployment), and the deployment before it (the Pages
//   dashboard rollback target). The run: environment approval, then for each project in matrix order
//   (max-parallel 1, fail-fast false) Inspect -> [PATCH -> readback] -> build and deploy -> smoke.
//   The backend accepts PLATFORM_PROXY_SECRET and, during a rotation, PLATFORM_PROXY_SECRET_PREVIOUS
//   (backend.ts:93,253-262). The edge decision itself is proved in auth_edge; here it is one def.
//
// BOUNDS
//   PLATFORM_ENV and NODE_ENV take every value class the core tells apart, plus one unknown value.
//   A secret length is 0 (unset), 10 (too short) or 32 (long enough). Four projects, at most three
//   proxy secret values. Run with --max-steps=20. The full rotation is the run test sitesRotationTest
//   (a random walk of 20 steps seldom completes four jobs), not a witness.
//
// LENGTH UNITS (W3-455)
//   env-core.ts:73 and backend.ts:107-109 count PLATFORM_PROXY_SECRET, PLATFORM_HASH_KEY and
//   PLATFORM_SESSION_SECRET in UTF-16 code units (`.length`). backend.ts:112 counts LEAK_LABEL_KEY in
//   UTF-8 bytes (TextEncoder). docs/deploy.md asks for "32+ random bytes". A string of n UTF-16 units
//   has at least n UTF-8 bytes, so the unit check is the stricter one and the byte rule holds for each
//   secret. The model gives the proxy, hash and session lengths in units and the leak key in bytes.
//
// TIME
//   No decision here uses time. Time is the order of actions only.
//
// ABSTRACTIONS
//   - The OTP provider check (otp-config.ts otpConfigProblems) is one boolean: otpOk.
//   - db: NETWORK_DATABASE_URL or DATABASE_URL is a non-empty string. netUrlBlank: NETWORK_DATABASE_URL
//     is set to "" (main.ts `??` then takes "", W3-458).
//   - The PLATFORM_DEV_* switches are one boolean: devSwitch (at least one is set to a value).
//   - NETWORK_REVIEW_MODE: Unset, Human ("human"), Auto (any other value, "" included).
//   - TURNSTILE_SECRET_KEY is one boolean: turnstile (set and not "").
//   - MIGRATION_DATABASE_URL: "unset", "same" (equal to the service URL) or "distinct".
//   - The shortest NETWORK_SERVICE_TOKENS token and NETWORK_SERVICE_CONSOLE_TOKEN: a length (0 = unset).
//   - A Pages origin binding: "good" (the declared backend), "stale" (another https origin) or "unset"
//     (the built-in BACKEND_ORIGIN is used, pages-worker.ts:24; the build uses the declared backend).
//   - Each Cloudflare or GitHub failure (an Inspect that needs owner review, a Turnstile widget that
//     does not cover the host, an API error, a build or wrangler error, a smoke failure) is a
//     nondeterministic failure.
//   - The problem texts are outside the model; only "no problem" matters for each gate.
//
// ASSUMPTIONS (named; no code makes them true)
//   - W3-452: no code snapshots the environment. Each caller reads `o.env ?? process.env` when it is
//     built (api.ts:130, serve.ts:38, service.ts:337, handler.ts:155). The production entries pass no
//     `env` and write no variable, so their callers read the environment the gate read. platform-dev.ts
//     writes two variables before it builds anything; `snap` has those writes. Tests inject `env`; a
//     test is not an entry point.
//   - NETWORK_REVIEW_MODE and PLATFORM_DEV_* have no reader outside env.ts and env-core.ts (W3-450).
//     The review mode of a running service is the `review` option of its constructor: both entries pass
//     none, so the ConsentNetwork default "human" holds, and service.ts:336 refuses any other value.
//     The model keeps the two env-core.ts clauses (they are a tripwire for an operator who sets them).
//     Human review of each proposal is proved in quint/opportunity.qnt, not here.
//   - A Pages deployment keeps the bindings it was made with. A dashboard rollback brings back the
//     bundle and the bindings of that older deployment; it does not change the stored project bindings
//     (docs/deploy.md 2.7 "A deployment rollback does not restore this project setting").
//   - The platform.settings environment row is missing only when somebody deletes it (migration 0003
//     inserts 'dev' with `on conflict do nothing`). The model has that as an operator action.
//
// OUTSIDE THE MODEL
//   - REQUIRED_TABLES (service.ts:511-516), BACKEND_EXTRA_HOSTS and STAGING_SITE_ORIGINS, the ports
//     and binds, the channel and live-send flags (AGENTS.md environment section: every send is dry-run
//     without them; runtime_ops and outbound_queue model the sends).
//   - The token grammar of parseTokenGrants (explicitApp only in production, service.ts:351).
//   - main.ts:47 trustForwardedHost on the server.ts path: server.ts:82 passes false.
//   - AVAILABILITY of the sites after runbook step 3 is a named value outside `safety`
//     (availabilityAfterDrop below), with its reason.
module boot_config {

  // ---------------------------------------------------------------- types (own, small)
  type Review = Unset | Human | Auto
  type Config = {
    platformEnv: str,   // "" when unset
    nodeEnv: str,       // "" when unset
    otpOk: bool,
    turnstile: bool,
    proxyLen: int,      // UTF-16 units
    hashLen: int,       // UTF-16 units
    sessionLen: int,    // UTF-16 units
    db: bool,
    review: Review,
    devSwitch: bool,
    // wave 4
    netUrlBlank: bool,      // NETWORK_DATABASE_URL="" (W3-458)
    leakBytes: int,         // LEAK_LABEL_KEY in UTF-8 bytes (W3-455)
    mig: str,               // MIGRATION_DATABASE_URL: "unset" | "same" | "distinct"
    migrateOnBoot: bool,    // MIGRATE_ON_BOOT is not "0"
    svcLoginOk: bool,       // the service login is not a superuser, BYPASSRLS or the owner (server.ts:57-60)
    initFlag: bool,         // PLATFORM_DB_ENVIRONMENT_INIT=1
    turnRoute: bool,        // NETWORK_CHANNEL=eliza_cloud or NETWORK_ROUTE_AUTHORITY_POLICY set (service.ts:106)
    turnLen: int,           // SERVICE_TURN_SECRET (0 = unset)
    staffTokenLen: int,     // the shortest NETWORK_SERVICE_TOKENS token (0 = no token)
    consoleTokenLen: int,   // NETWORK_SERVICE_CONSOLE_TOKEN (0 = unset)
    localBind: bool,        // main.ts --host is 127.0.0.1 or localhost
  }
  // One Pages binding pair: PLATFORM_PROXY_SECRET (0 = none) and BACKEND_ORIGIN.
  type Bind = { secret: int, origin: str }

  pure val PLATFORM_ENVS = Set("", "production", "staging", "dev", "other")
  pure val NODE_ENVS = Set("", "production", "test", "other")
  pure val LENGTHS = Set(0, 10, 32)
  pure val MIN_SECRET_LENGTH = 32
  pure val MAX_RESTARTS = 5     // railway.toml restartPolicyMaxRetries
  pure val ENTRIES = Set("main", "backend", "platformDev", "mcpDev")
  // The callers of devShortcutsAllowed (W3-456), one kind each.
  pure val SHORTCUTS = Set(
    "otpConsole",         // otp.ts:36 DevConsoleProvider
    "turnstileBypass",    // turnstile.ts:41 DevTurnstileBypass
    "devKeys",            // api.ts:132-135 and service.ts:348: DEV_HASH_KEY, DEV_SESSION_SECRET, cookies without Secure
    "devMatching",        // service.ts:383
    "mcpDev",             // serve.ts:39 and handler.ts:194: MCP without Turnstile site key, http issuers
    "privateOpenAiApps",  // handler.ts:157
    "trustFwdMain",       // main.ts:47, then api.ts:136 and handler.ts:195
  )
  pure val PROJECTS = ["slop-date", "ntwrk-party", "peon-biz", "friends-help"]   // deploy-sites.yml:101-105, in order
  pure val PROJECT_SET = Set("slop-date", "ntwrk-party", "peon-biz", "friends-help")
  pure val MAX_SECRET = 3

  // ---------------------------------------------------------------- env-core.ts, def for def
  // declaredEnv: PLATFORM_ENV wins when it is set; an unknown PLATFORM_ENV is not declared.
  pure def declaredEnv(p: str, n: str): str =
    if (p != "") (if (p == "production" or p == "staging" or p == "dev") p else "")
    else if (n == "production") "production"
    else if (n == "test") "dev"
    else ""

  pure def productionEnv(n: str, p: str): bool = n == "production" or p == "production"

  pure def devAllowed(p: str, n: str): bool = not(productionEnv(n, p)) and declaredEnv(p, n) == "dev"

  pure def deployedReady(c: Config): bool = and {
    c.otpOk, c.turnstile,
    c.proxyLen >= MIN_SECRET_LENGTH, c.hashLen >= MIN_SECRET_LENGTH, c.sessionLen >= MIN_SECRET_LENGTH,
    c.db,
    c.review != Auto,
    not(c.devSwitch),
  }

  // bootProblems(f).length == 0
  pure def bootOk(c: Config): bool =
    val e = declaredEnv(c.platformEnv, c.nodeEnv)
    if (e == "") false
    else if (e == "dev") not(productionEnv(c.nodeEnv, c.platformEnv))
    else deployedReady(c)

  // ---------------------------------------------------------------- the other gates, as the code does them NOW
  pure def dev(c: Config): bool = devAllowed(c.platformEnv, c.nodeEnv)
  pure def declared(c: Config): str = declaredEnv(c.platformEnv, c.nodeEnv)
  // backend.ts:89 `deployed = env === "staging" || env === "production"`.
  pure def deployed(c: Config): bool = declared(c) == "staging" or declared(c) == "production"
  // The rules below name "a staging or production process". A process whose environment says
  // production is one, whatever PLATFORM_ENV says (env.ts header: fail closed).
  pure def liveLike(c: Config): bool = deployed(c) or productionEnv(c.nodeEnv, c.platformEnv)

  // backend.ts loadConfig (85-113). requirePlatformEnv (87), the database URL with || (90-92),
  // the deployed checks (94-97), the migration login (102-105), the proxy secret length in every
  // environment (107), the hash key and session secret length (109) and LEAK_LABEL_KEY in bytes (111-112).
  // It does not check productionEnv against "dev", NETWORK_REVIEW_MODE or PLATFORM_DEV_* (W3-448).
  pure def loadConfigOk(c: Config): bool =
    val d = deployed(c)
    and {
      declared(c) != "",
      c.db,
      not(d) or and { c.hashLen > 0, c.sessionLen > 0, c.turnstile, c.otpOk, c.proxyLen > 0 },
      not(d and c.migrateOnBoot and c.mig == "unset"),
      not(d and c.mig == "same"),
      c.proxyLen == 0 or c.proxyLen >= MIN_SECRET_LENGTH,
      not(d) or (c.hashLen >= MIN_SECRET_LENGTH and c.sessionLen >= MIN_SECRET_LENGTH),
      not(d) or c.leakBytes >= MIN_SECRET_LENGTH,
    }

  // The review option each entry passes to the NetworkService constructor (main.ts:41-45,
  // server.ts:74-90: `network: { seed }`, no review), so the ConsentNetwork default.
  pure def entryReview(e: str, c: Config): Review = Human

  // The refusals after the gate, in code order (W3-454). "" when the service comes up.
  pure def serviceRefusal(c: Config, e: str, dbEnv: str): str =
    if (entryReview(e, c) != Human) "review_mode"                                                // service.ts:336
    else if ((c.turnLen > 0 or c.turnRoute) and c.turnLen < MIN_SECRET_LENGTH) "turn_secret"      // service.ts:104-110
    else if (c.hashLen == 0 and not(dev(c))) "hash_key"                                           // service.ts:348, api.ts:133
    else if (not(c.otpOk) and not(dev(c))) "otp_provider"                                         // otp.ts:110-115 then otp.ts:36
    else if (not(c.turnstile) and not(dev(c))) "turnstile_verifier"                               // turnstile.ts:47 then turnstile.ts:41
    else if (declared(c) != "" and dbEnv != "missing" and dbEnv != declared(c)) "db_env"          // service.ts:519-521
    else ""

  // Construction takes a dev fallback when a provider or key is not configured (otp.ts:115,
  // turnstile.ts:48, api.ts:133-135, service.ts:348). Each fallback asks devShortcutsAllowed.
  pure def constructShortcut(c: Config): bool =
    dev(c) and (not(c.otpOk) or not(c.turnstile) or c.hashLen == 0 or c.sessionLen == 0)

  // The guard each caller of a dev shortcut uses (W3-456). Every one asks devShortcutsAllowed on the
  // environment it reads; main.ts:47 decides with the gate's result (`env === "dev"`) and the local
  // bind, and createPublicApi (api.ts:136) then asks devShortcutsAllowed again.
  pure def callerAllows(k: str, e: str, c: Config): bool =
    if (k == "trustFwdMain") and { e == "main", c.localBind, declared(c) == "dev", dev(c) }
    else dev(c)

  // relay-endpoint.ts:86: production (isProduction) without the Workers AI keys holds every relayed
  // text for staff; staging and dev run on the rules alone. Recorded for W3-454 (the staging split).
  pure def relayHoldsAll(c: Config, clef: bool): bool = productionEnv(c.nodeEnv, c.platformEnv) and not(clef)

  // ---------------------------------------------------------------- the edge (auth_edge proves it; one def here)
  // backend.ts normalizeEdge (253-262): the current secret, else the previous one during a rotation.
  pure def accepts(s: int, cur: int, prev: int): bool = s != 0 and (s == cur or (prev != 0 and s == prev))
  // pages-worker.ts:24: a project variable wins; an unset one falls back to the built origin, which the
  // workflow builds from the declared backend (deploy-sites.yml:190).
  pure def effOrigin(o: str): str = if (o == "unset") "good" else o

  // ---------------------------------------------------------------- state, part A
  var cfg: Config
  var started: bool         // the gate passed and the process has not stopped
  var snap: Config          // the configuration the running process reads (after its own env writes)
  var shortcutsUsed: bool   // a dev shortcut ran in the running process
  var refused: int          // boots that a gate refused
  var entry: str            // the entry point of the running process ("" when none)
  var stage: str            // "down" | "gated" | "service" | "up" | "dead"
  var failures: int         // failed starts in this deployment (Railway restart budget)
  var lastRefusal: str      // why the last start failed
  var dbEnv: str            // platform.settings environment row: "missing" | "dev" | "staging" | "production"
  var svcReview: Review     // the review mode of the running service
  var relayHold: bool       // the running service holds every relayed text for staff
  var clefKeys: bool        // CLOUDFLARE_AI_TOKEN and CLOUDFLARE_ACCOUNT_ID are set
  var lastShortcut: str

  // ---------------------------------------------------------------- state, part B
  var stored: str -> Bind   // the project's production bindings
  var running: str -> Bind  // the bindings of the active deployment
  var prev: str -> Bind     // the deployment before it (rollback target)
  var runOp: str            // "none" | "deploy" (push) | "inspect" | "repair" | "repairProxy"
  var runApproved: bool     // the "production" environment approval
  var runCur: int           // index into PROJECTS of the matrix job that runs
  var runStep: str          // "wait" | "inspect" | "deploy" | "smoke"
  var runFailed: Set[str]   // the projects whose job failed in this run
  var bSecret: int          // backend PLATFORM_PROXY_SECRET
  var bPrev: int            // backend PLATFORM_PROXY_SECRET_PREVIOUS (0 = unset)
  var ghSecret: int         // the "production" environment secret PLATFORM_PROXY_SECRET
  var dropped: bool         // runbook step 3 ran at least once
  var ghostUnapproved: bool       // a binding or a deployment changed outside an approved run
  var ghostSecretNoRotation: bool // a stored proxy secret changed outside repair-proxy-and-deploy
  var ghostPushPatched: bool      // a push run changed a stored binding

  pure val EMPTY: Config = {
    platformEnv: "", nodeEnv: "", otpOk: false, turnstile: false,
    proxyLen: 0, hashLen: 0, sessionLen: 0, db: false, review: Unset, devSwitch: false,
    netUrlBlank: false, leakBytes: 0, mig: "unset", migrateOnBoot: true, svcLoginOk: true, initFlag: false,
    turnRoute: false, turnLen: 0, staffTokenLen: 0, consoleTokenLen: 0, localBind: true,
  }
  pure val GOOD: Bind = { secret: 1, origin: "good" }
  pure val ALL_GOOD: str -> Bind = PROJECT_SET.mapBy(p => GOOD)

  action init = all {
    cfg' = EMPTY,
    started' = false,
    snap' = EMPTY,
    shortcutsUsed' = false,
    refused' = 0,
    entry' = "",
    stage' = "down",
    failures' = 0,
    lastRefusal' = "",
    dbEnv' = "dev",
    svcReview' = Unset,
    relayHold' = false,
    clefKeys' = false,
    lastShortcut' = "",
    stored' = ALL_GOOD,
    running' = ALL_GOOD,
    prev' = ALL_GOOD,
    runOp' = "none",
    runApproved' = false,
    runCur' = 0,
    runStep' = "wait",
    runFailed' = Set(),
    bSecret' = 1,
    bPrev' = 0,
    ghSecret' = 1,
    dropped' = false,
    ghostUnapproved' = false,
    ghostSecretNoRotation' = false,
    ghostPushPatched' = false,
  }

  action sitesKeep = all {
    stored' = stored, running' = running, prev' = prev, runOp' = runOp, runApproved' = runApproved,
    runCur' = runCur, runStep' = runStep, runFailed' = runFailed, bSecret' = bSecret, bPrev' = bPrev,
    ghSecret' = ghSecret, dropped' = dropped, ghostUnapproved' = ghostUnapproved,
    ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
  }
  action procKeep = all {
    cfg' = cfg, started' = started, snap' = snap, shortcutsUsed' = shortcutsUsed, refused' = refused,
    entry' = entry, stage' = stage, failures' = failures, lastRefusal' = lastRefusal, dbEnv' = dbEnv,
    svcReview' = svcReview, relayHold' = relayHold, clefKeys' = clefKeys, lastShortcut' = lastShortcut,
  }
  // The rest of part A is unchanged (each action names what it changes).
  action keepRun = all { svcReview' = svcReview, relayHold' = relayHold, clefKeys' = clefKeys, lastShortcut' = lastShortcut }

  // ---------------------------------------------------------------- actions, part A
  // An operator changes the configuration of a stopped process (a new deployment). Railway's restart
  // budget starts again with a new deployment.
  // The guard comes before the nondet choices: an evaluator that searches the choices for an enabled
  // branch would otherwise try every configuration while the process runs.
  action configure = all { not(started), configureAny }
  action configureAny = {
    nondet p = PLATFORM_ENVS.oneOf()
    nondet n = NODE_ENVS.oneOf()
    nondet o = Set(true, false).oneOf()
    nondet t = Set(true, false).oneOf()
    nondet l1 = LENGTHS.oneOf()
    nondet l2 = LENGTHS.oneOf()
    nondet l3 = LENGTHS.oneOf()
    nondet d = Set(true, false).oneOf()
    nondet r = Set(Unset, Human, Auto).oneOf()
    nondet s = Set(true, false).oneOf()
    nondet nb = Set(true, false).oneOf()
    nondet lk = LENGTHS.oneOf()
    nondet mg = Set("unset", "same", "distinct").oneOf()
    nondet mob = Set(true, false).oneOf()
    nondet slo = Set(true, false).oneOf()
    nondet ini = Set(true, false).oneOf()
    nondet tr = Set(true, false).oneOf()
    nondet tl = LENGTHS.oneOf()
    nondet stl = LENGTHS.oneOf()
    nondet ctl = LENGTHS.oneOf()
    nondet lb = Set(true, false).oneOf()
    nondet ck = Set(true, false).oneOf()
    all {
      not(started),
      cfg' = { platformEnv: p, nodeEnv: n, otpOk: o, turnstile: t, proxyLen: l1, hashLen: l2, sessionLen: l3,
               db: d, review: r, devSwitch: s, netUrlBlank: nb, leakBytes: lk, mig: mg, migrateOnBoot: mob,
               svcLoginOk: slo, initFlag: ini, turnRoute: tr, turnLen: tl, staffTokenLen: stl,
               consoleTokenLen: ctl, localBind: lb },
      clefKeys' = ck,
      stage' = "down", failures' = 0,
      started' = started, snap' = snap, shortcutsUsed' = shortcutsUsed, refused' = refused, entry' = entry,
      lastRefusal' = lastRefusal, dbEnv' = dbEnv, svcReview' = svcReview, relayHold' = relayHold,
      lastShortcut' = lastShortcut,
      sitesKeep,
    }
  }

  // The same operator change, near a ready deployment: PLATFORM_ENV, NODE_ENV and one other variable
  // take any value, the rest are as in READY. It reaches the same configurations as `configure`, but
  // a random walk hits the deployed ones much more often (the simulator samples uniformly).
  action configureNear = all { not(started), configureNearAny }
  action configureNearAny = {
    nondet p = PLATFORM_ENVS.oneOf()
    nondet n = NODE_ENVS.oneOf()
    nondet k = 0.to(9).oneOf()
    nondet b = Set(true, false).oneOf()
    nondet l = LENGTHS.oneOf()
    nondet ck = Set(true, false).oneOf()
    val r = { ...READY, platformEnv: p, nodeEnv: n }
    val c =
      if (k == 0) { ...r, sessionLen: l }
      else if (k == 1) { ...r, leakBytes: l }
      else if (k == 2) { ...r, staffTokenLen: l }
      else if (k == 3) { ...r, svcLoginOk: b }
      else if (k == 4) { ...r, initFlag: b }
      else if (k == 5) { ...r, netUrlBlank: b }
      else if (k == 6) { ...r, otpOk: b }
      else if (k == 7) { ...r, review: if (b) Auto else Unset }
      else if (k == 8) { ...r, localBind: b }
      else { ...r, mig: if (b) "same" else "unset" }
    all {
      not(started),
      cfg' = c, clefKeys' = ck,
      stage' = "down", failures' = 0,
      started' = started, snap' = snap, shortcutsUsed' = shortcutsUsed, refused' = refused, entry' = entry,
      lastRefusal' = lastRefusal, dbEnv' = dbEnv, svcReview' = svcReview, relayHold' = relayHold,
      lastShortcut' = lastShortcut,
      sitesKeep,
    }
  }

  // A start fails: the process exits 1. Railway restarts it at most MAX_RESTARTS times.
  action startFails(reason: str, byGate: bool, newDbEnv: str): bool = all {
    started' = false,
    stage' = if (failures + 1 > MAX_RESTARTS) "dead" else "down",
    failures' = failures + 1,
    refused' = if (byGate) refused + 1 else refused,
    lastRefusal' = reason,
    entry' = "",
    shortcutsUsed' = false,
    cfg' = cfg, snap' = snap, dbEnv' = newDbEnv,
    keepRun,
  }

  // The gate passed: the process reads `c` from now on.
  action pass(e: str, c: Config, nextStage: str): bool = all {
    started' = true, stage' = nextStage, snap' = c, entry' = e,
    refused' = refused, failures' = failures, lastRefusal' = lastRefusal,
    shortcutsUsed' = false,
    cfg' = cfg, dbEnv' = dbEnv,
    keepRun,
  }

  // main.ts:31 assertBootConfig(env) before anything else.
  action boot = all {
    stage == "down",
    if (bootOk(cfg)) pass("main", cfg, "gated") else startFails("gate", true, dbEnv),
    sitesKeep,
  }

  // main.ts:34-35: `NETWORK_DATABASE_URL ?? DATABASE_URL` keeps "" (W3-458).
  action mainDbUrl = all {
    stage == "gated", entry == "main",
    if (snap.netUrlBlank or not(snap.db))
      // The gate checked the database only for a deployed environment (env-core.ts:98,126).
      startFails(if (deployed(snap)) "main_db_url_after_gate" else "main_db_url", false, dbEnv)
    else all {
      stage' = "service",
      started' = started, snap' = snap, entry' = entry, refused' = refused, failures' = failures,
      lastRefusal' = lastRefusal, shortcutsUsed' = shortcutsUsed, cfg' = cfg, dbEnv' = dbEnv, keepRun,
    },
    sitesKeep,
  }

  // server.ts:31 loadConfig (W3-448).
  action bootBackend = all {
    stage == "down",
    if (loadConfigOk(cfg)) pass("backend", cfg, "gated") else startFails("gate", true, dbEnv),
    sitesKeep,
  }

  // server.ts:34-60. Migrations (outside the model), then the one-way environment init (its own
  // transaction, kept when the next check refuses), then the service-login check.
  action backendInit = {
    val moved = if (deployed(snap) and snap.initFlag and dbEnv == "dev") declared(snap) else dbEnv
    all {
      stage == "gated", entry == "backend",
      if (deployed(snap) and not(snap.svcLoginOk)) startFails("service_login", false, moved)
      else all {
        stage' = "service", dbEnv' = moved,
        started' = started, snap' = snap, entry' = entry, refused' = refused, failures' = failures,
        lastRefusal' = lastRefusal, shortcutsUsed' = shortcutsUsed, cfg' = cfg, keepRun,
      },
      sitesKeep,
    }
  }

  // scripts/platform-dev.ts:45-61: refuse isProduction, then PLATFORM_ENV ??= "dev",
  // refuse anything but dev, then PLATFORM_PROXY_SECRET ||= 32 random bytes. No boot gate.
  action bootPlatformDev = {
    val written = { ...cfg,
      platformEnv: if (cfg.platformEnv == "") "dev" else cfg.platformEnv,
      proxyLen: if (cfg.proxyLen == 0) 64 else cfg.proxyLen }
    all {
      stage == "down",
      if (productionEnv(cfg.nodeEnv, cfg.platformEnv) or written.platformEnv != "dev") startFails("platform_dev", true, dbEnv)
      else pass("platformDev", written, "service"),
      sitesKeep,
    }
  }

  // packages/mcp/src/dev-server.ts:11: devShortcutsAllowed(), memory stores, the console OTP provider.
  action bootMcpDev = all {
    stage == "down",
    if (dev(cfg)) all {
      started' = true, stage' = "up", snap' = cfg, entry' = "mcpDev",
      refused' = refused, failures' = failures, lastRefusal' = lastRefusal,
      shortcutsUsed' = true, lastShortcut' = "otpConsole",
      cfg' = cfg, dbEnv' = dbEnv, svcReview' = svcReview, relayHold' = relayHold, clefKeys' = clefKeys,
    } else startFails("mcp_dev", true, dbEnv),
    sitesKeep,
  }

  // The NetworkService constructor, its public API and start() (W3-454).
  action construct = {
    val why = serviceRefusal(snap, entry, dbEnv)
    all {
      stage == "service",
      if (why != "") startFails(why, false, dbEnv)
      else all {
        stage' = "up",
        svcReview' = entryReview(entry, snap),
        relayHold' = relayHoldsAll(snap, clefKeys),
        shortcutsUsed' = (shortcutsUsed or constructShortcut(snap)),
        lastShortcut' = if (constructShortcut(snap)) "construct" else lastShortcut,
        started' = started, snap' = snap, entry' = entry, refused' = refused, failures' = failures,
        lastRefusal' = lastRefusal, cfg' = cfg, dbEnv' = dbEnv, clefKeys' = clefKeys,
      },
      sitesKeep,
    }
  }

  // A dev shortcut runs in the running process when its caller's guard says yes (W3-456).
  action callShortcut = {
    nondet k = SHORTCUTS.oneOf()
    all {
      started, stage == "service" or stage == "up",
      callerAllows(k, entry, snap),
      shortcutsUsed' = true, lastShortcut' = k,
      cfg' = cfg, started' = started, snap' = snap, refused' = refused, entry' = entry, stage' = stage,
      failures' = failures, lastRefusal' = lastRefusal, dbEnv' = dbEnv, svcReview' = svcReview,
      relayHold' = relayHold, clefKeys' = clefKeys,
      sitesKeep,
    }
  }

  // Kept from wave 2: a caller that asks devShortcutsAllowed for the snapshot.
  action useShortcut = all {
    started,
    devAllowed(snap.platformEnv, snap.nodeEnv),
    shortcutsUsed' = true,
    cfg' = cfg, started' = started, snap' = snap, refused' = refused,
    entry' = entry, stage' = stage, failures' = failures, lastRefusal' = lastRefusal, dbEnv' = dbEnv,
    svcReview' = svcReview, relayHold' = relayHold, clefKeys' = clefKeys, lastShortcut' = "devAllowed",
    sitesKeep,
  }

  // SIGTERM or SIGINT: a clean exit (exit 0; Railway does not count it).
  action stop = all {
    started,
    started' = false, shortcutsUsed' = false, stage' = "down", entry' = "",
    cfg' = cfg, snap' = snap, refused' = refused, failures' = failures, lastRefusal' = lastRefusal,
    dbEnv' = dbEnv, svcReview' = Unset, relayHold' = false, clefKeys' = clefKeys, lastShortcut' = lastShortcut,
    sitesKeep,
  }

  // Somebody deletes the environment row (see ASSUMPTIONS), or sets it by hand.
  action editEnvRow = {
    nondet v = Set("missing", "dev", "staging", "production").oneOf()
    all {
      dbEnv' = v,
      cfg' = cfg, started' = started, snap' = snap, shortcutsUsed' = shortcutsUsed, refused' = refused,
      entry' = entry, stage' = stage, failures' = failures, lastRefusal' = lastRefusal, keepRun,
      sitesKeep,
    }
  }

  // ---------------------------------------------------------------- actions, part B (M-148, M-131)
  // Ends the job of the current project; the next matrix job starts (fail-fast false).
  action endJob(failed: bool): bool = all {
    runFailed' = if (failed) runFailed.union(Set(PROJECTS[runCur])) else runFailed,
    if (runCur + 1 >= PROJECTS.length()) all { runOp' = "none", runCur' = 0, runStep' = "wait", runApproved' = false }
    else all { runOp' = runOp, runCur' = runCur + 1, runStep' = "inspect", runApproved' = runApproved },
  }

  // A push to main (operation "deploy") or a workflow_dispatch. One run at a time (concurrency group,
  // no cancel for push).
  action startAs(op: str): bool = all {
    runOp == "none",
    runOp' = op, runApproved' = false, runCur' = 0, runStep' = "wait", runFailed' = Set(),
    stored' = stored, running' = running, prev' = prev, bSecret' = bSecret, bPrev' = bPrev,
    ghSecret' = ghSecret, dropped' = dropped, ghostUnapproved' = ghostUnapproved,
    ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
    procKeep,
  }
  action startRun = {
    nondet op = Set("deploy", "inspect", "repair", "repairProxy").oneOf()
    startAs(op)
  }

  // The "production" environment: a required reviewer approves the run, or rejects it.
  action approveAs(yes: bool): bool = all {
    runOp != "none", not(runApproved), runStep == "wait",
    if (yes) all { runApproved' = true, runStep' = "inspect", runOp' = runOp, runCur' = runCur }
    else all { runApproved' = false, runStep' = "wait", runOp' = "none", runCur' = 0 },
    runFailed' = runFailed,
    stored' = stored, running' = running, prev' = prev, bSecret' = bSecret, bPrev' = bPrev,
    ghSecret' = ghSecret, dropped' = dropped, ghostUnapproved' = ghostUnapproved,
    ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
    procKeep,
  }
  action approve = {
    nondet yes = Set(true, false).oneOf()
    approveAs(yes)
  }

  // The job goes on to the build and deploy steps of the same project.
  action toDeploy = all { runStep' = "deploy", runOp' = runOp, runCur' = runCur, runApproved' = runApproved, runFailed' = runFailed }

  // deploy-sites.yml:124-181, one project. Refusals before any change (:146-149, :159, :179), then the
  // PATCH (:172) and its readback (:173-176), which can fail after the PATCH changed the bindings.
  action inspectWith(extFail: bool, readbackFail: bool): bool = {
    val p = PROJECTS[runCur]
    val b = stored.get(p)
    val rotate = runOp == "repairProxy"
    val repair = runOp == "repair" or rotate
    val refuse = or {
      extFail,
      not(rotate) and b.secret == 0,
      runOp == "deploy" and b.origin == "stale",   // :178-179 "explicit manual repair approval is required"
    }
    val patch = not(refuse) and repair and (b.origin != "good" or rotate)
    val after = { secret: if (rotate) ghSecret else b.secret, origin: if (patch) "good" else b.origin }
    all {
      runOp != "none", runApproved, runStep == "inspect",
      stored' = if (patch) stored.set(p, after) else stored,
      if (refuse or (patch and readbackFail)) endJob(true)
      else if (runOp == "inspect") endJob(false)
      else toDeploy,
      ghostUnapproved' = (ghostUnapproved or (patch and not(runApproved))),
      ghostSecretNoRotation' = (ghostSecretNoRotation or (patch and after.secret != b.secret and not(rotate))),
      ghostPushPatched' = (ghostPushPatched or (patch and runOp == "deploy")),
      running' = running, prev' = prev, bSecret' = bSecret, bPrev' = bPrev, ghSecret' = ghSecret, dropped' = dropped,
      procKeep,
    }
  }
  action inspect = {
    nondet extFail = Set(true, false).oneOf()
    nondet readbackFail = Set(true, false).oneOf()
    inspectWith(extFail, readbackFail)
  }

  // :183-200 build, then wrangler pages deploy. The new deployment takes the stored bindings.
  action deployWith(buildFail: bool): bool = {
    val p = PROJECTS[runCur]
    all {
      runOp != "none", runStep == "deploy",
      if (buildFail) all { running' = running, prev' = prev, endJob(true) }
      else all {
        running' = running.set(p, { secret: stored.get(p).secret, origin: effOrigin(stored.get(p).origin) }),
        prev' = prev.set(p, running.get(p)),
        runStep' = "smoke", runOp' = runOp, runCur' = runCur, runApproved' = runApproved, runFailed' = runFailed,
      },
      ghostUnapproved' = (ghostUnapproved or (not(buildFail) and not(runApproved))),
      stored' = stored, bSecret' = bSecret, bPrev' = bPrev, ghSecret' = ghSecret, dropped' = dropped,
      ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
      procKeep,
    }
  }
  action deploy = {
    nondet buildFail = Set(true, false).oneOf()
    deployWith(buildFail)
  }

  // :201-210 smoke check. With --api it fails when the site cannot reach the backend; without it
  // (a push with BACKEND_LIVE not "true") it checks the static pages only. No rollback on failure.
  action smokeWith(apiFlag: bool, other: bool): bool = {
    val p = PROJECTS[runCur]
    val r = running.get(p)
    val api = apiFlag or runOp == "repair" or runOp == "repairProxy"
    val ok = not(other) and (not(api) or (accepts(r.secret, bSecret, bPrev) and r.origin == "good"))
    all {
      runOp != "none", runStep == "smoke",
      endJob(not(ok)),
      stored' = stored, running' = running, prev' = prev, bSecret' = bSecret, bPrev' = bPrev,
      ghSecret' = ghSecret, dropped' = dropped, ghostUnapproved' = ghostUnapproved,
      ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
      procKeep,
    }
  }
  action smoke = {
    nondet apiFlag = Set(true, false).oneOf()
    nondet other = Set(true, false).oneOf()
    smokeWith(apiFlag, other)
  }

  // docs/deploy.md 3.4 step 1 (founder approval): the backend gets the new value as
  // PLATFORM_PROXY_SECRET and the old one as PLATFORM_PROXY_SECRET_PREVIOUS; the owner puts the new value
  // into the "production" environment secret.
  action rotateBackend = all {
    bSecret < MAX_SECRET,
    bPrev' = bSecret, bSecret' = bSecret + 1, ghSecret' = bSecret + 1,
    stored' = stored, running' = running, prev' = prev, runOp' = runOp, runApproved' = runApproved,
    runCur' = runCur, runStep' = runStep, runFailed' = runFailed, dropped' = dropped,
    ghostUnapproved' = ghostUnapproved, ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
    procKeep,
  }

  // docs/deploy.md 3.4 step 3: remove PLATFORM_PROXY_SECRET_PREVIOUS and redeploy the backend. The
  // operator does it after a run ends; no code checks that all four projects run the new value.
  action dropPrevious = all {
    bPrev != 0, runOp == "none",
    bPrev' = 0, dropped' = true,
    stored' = stored, running' = running, prev' = prev, runOp' = runOp, runApproved' = runApproved,
    runCur' = runCur, runStep' = runStep, runFailed' = runFailed, bSecret' = bSecret, ghSecret' = ghSecret,
    ghostUnapproved' = ghostUnapproved, ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
    procKeep,
  }

  // The Pages dashboard rollback (docs/deploy.md 2.7): the earlier deployment, with its bindings.
  action rollback = {
    nondet p = PROJECT_SET.oneOf()
    all {
      running' = running.set(p, prev.get(p)), prev' = prev.set(p, running.get(p)),
      stored' = stored, runOp' = runOp, runApproved' = runApproved, runCur' = runCur, runStep' = runStep,
      runFailed' = runFailed, bSecret' = bSecret, bPrev' = bPrev, ghSecret' = ghSecret, dropped' = dropped,
      ghostUnapproved' = ghostUnapproved, ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
      procKeep,
    }
  }

  action step = any {
    configure, configureNear, boot, mainDbUrl, bootBackend, backendInit, bootPlatformDev, bootMcpDev, construct,
    callShortcut, useShortcut, stop, editEnvRow,
    startRun, approve, inspect, deploy, smoke, rotateBackend, dropPrevious, rollback,
  }

  // ---------------------------------------------------------------- invariants, part A
  // Rule: the service does not guess its environment (env.ts requirePlatformEnv; env-core.ts
  // bootProblems ensures "declaredEnv === "" ==> result.length > 0"; main.ts calls assertBootConfig).
  val startedOnlyDeclared = not(started) or declaredEnv(snap.platformEnv, snap.nodeEnv) != ""

  // Rule: a production or staging process has the OTP provider, Turnstile, the three secrets of at
  // least 32 characters, a database, review mode human, and no dev switch (env.ts bootConfigProblems
  // comment; env-core.ts bootProblems ensures "... ==> deployedReady(f)"). The review and dev-switch
  // clauses are a tripwire only (W3-450, ASSUMPTIONS).
  val startedDeployedIsReady =
    not(started and declaredEnv(snap.platformEnv, snap.nodeEnv) != "dev") or and {
      snap.otpOk, snap.turnstile, snap.db, snap.review != Auto, not(snap.devSwitch),
      snap.proxyLen >= 32, snap.hashLen >= 32, snap.sessionLen >= 32,
    }

  // Rule: dev that says production never starts (env-core.ts bootProblems ensures
  // "productionEnv ==> declaredEnv !== "dev""; env.ts header "fail closed"). On server.ts this fails
  // (Q-boot_config-W4-1).
  val startedDevNotProduction =
    not(started and declaredEnv(snap.platformEnv, snap.nodeEnv) == "dev") or not(productionEnv(snap.nodeEnv, snap.platformEnv))

  // Rule: dev shortcuts are never allowed in production, and only in a declared dev environment
  // (env.ts header comment; env-core.ts devAllowed ensures). Written on the raw variables, so a
  // caller with a weaker guard than devAllowed breaks it (W3-451).
  val shortcutsOnlyInDev = not(shortcutsUsed) or and {
    started,
    snap.nodeEnv != "production",
    snap.platformEnv != "production",
    snap.platformEnv == "dev" or (snap.platformEnv == "" and snap.nodeEnv == "test"),
  }

  // Rule: a staging or production process keys the leak guard's labels with LEAK_LABEL_KEY of at
  // least 32 bytes (AGENTS.md audit hand-offs "LEAK_LABEL_KEY in production"; backend.ts:110 comment;
  // docs/deploy.md 2.3). Fails on server.ts dev+production (W4-1) and on main.ts (W4-3).
  val upLiveLeakKeyed = not(stage == "up" and liveLike(snap)) or snap.leakBytes >= MIN_SECRET_LENGTH

  // Rule: a staging or production process has a session secret of its own of at least 32 characters,
  // never the hash key (docs/deploy.md 2.3 PLATFORM_SESSION_SECRET; backend.ts:108 comment, SD-164).
  // api.ts:135 falls back to the hash key outside dev. Fails on server.ts dev+production (W4-1).
  val upLiveOwnSessionSecret = not(stage == "up" and liveLike(snap)) or snap.sessionLen >= MIN_SECRET_LENGTH

  // Rule: deployed, the service login is never a superuser, BYPASSRLS or the owner, so RLS and the
  // grants apply (docs/deploy.md 2.1; server.ts:56 comment). Fails on server.ts dev+production (W4-1)
  // and on main.ts (W4-3).
  val upLiveServiceLogin = not(stage == "up" and liveLike(snap)) or snap.svcLoginOk

  // Rule: the database and the process agree on the environment; the 555-01xx guard reads the
  // database's (service.ts:518 comment; migration 0003 refuse_synthetic_phone). Fails when the row is
  // missing (Q-boot_config-W4-2).
  val upDbAgrees = not(stage == "up" and liveLike(snap)) or dbEnv == declared(snap)

  // Rule: every deployed secret is at least 32 characters (env.ts bootConfigProblems comment; the
  // Observatory refuses shorter staff tokens, observatory/src/server.ts:273). Fails (W3-457).
  val upLiveStaffTokensLong = not(stage == "up" and liveLike(snap)) or and {
    snap.staffTokenLen == 0 or snap.staffTokenLen >= MIN_SECRET_LENGTH,
    snap.consoleTokenLen == 0 or snap.consoleTokenLen >= MIN_SECRET_LENGTH,
  }

  // Rule: every proactive proposal and member request goes through human review (AGENTS.md code
  // invariants); the service refuses any other mode (service.ts:336).
  val upReviewHuman = not(stage == "up" and entry != "mcpDev") or svcReview == Human

  // Rule: production without the Workers AI keys holds every relayed text for staff (AGENTS.md Relay).
  val upProductionRelayClosed =
    not(stage == "up" and entry != "mcpDev" and productionEnv(snap.nodeEnv, snap.platformEnv) and not(clefKeys)) or relayHold

  // Rule: the gate is the start condition: what a process misses before it may start (env.ts
  // bootConfigProblems comment; main.ts:28-30). main.ts reads the database URL with `??` (W3-458).
  val mainDbMatchesGate = lastRefusal != "main_db_url_after_gate"

  // A dead service stays down until a new deployment (railway.toml).
  val deadIsDown = not(stage == "dead") or (not(started) and failures > MAX_RESTARTS)
  val startedMatchesStage = started == (stage == "gated" or stage == "service" or stage == "up")

  // ---------------------------------------------------------------- invariants, part B
  // Rule: no deploy without approval (AGENTS.md environment section; deploy-sites.yml "production"
  // environment with required reviewers). Neither a deployment nor a binding changes outside an
  // approved run.
  val sitesOnlyApproved = not(ghostUnapproved)
  // Rule: the proxy secret binding changes only on the explicit repair-proxy-and-deploy operation
  // (deploy-sites.yml header; docs/deploy.md 3.4, founder approval only).
  val sitesSecretOnlyByRotation = not(ghostSecretNoRotation)
  // Rule: a push never changes a binding (deploy-sites.yml:178-179 "explicit manual repair approval").
  val sitesPushNeverPatches = not(ghostPushPatched)
  // Rule: no unsigned request reaches the API (backend.ts header; auth_edge proves the decision).
  val edgeRefusesUnsigned = not(accepts(0, bSecret, bPrev))

  val safety = and {
    startedOnlyDeclared,
    startedDeployedIsReady,
    startedDevNotProduction,
    shortcutsOnlyInDev,
    upLiveLeakKeyed,
    upLiveOwnSessionSecret,
    upLiveServiceLogin,
    upDbAgrees,
    upLiveStaffTokensLong,
    upReviewHuman,
    upProductionRelayClosed,
    mainDbMatchesGate,
    deadIsDown,
    startedMatchesStage,
    sitesOnlyApproved,
    sitesSecretOnlyByRotation,
    sitesPushNeverPatches,
    edgeRefusesUnsigned,
  }

  // NOT IN `safety`, for a reason: availability of the four sites when no rotation is open. Runbook
  // step 3 (docs/deploy.md 3.4) is a manual operator step: "when all four sites are deployed with the
  // new value". The backend cannot see which secret a Pages deployment holds, and a run that is red for
  // one project still deploys the others (fail-fast false). A code check (for example a backend metric
  // of the signatures made with the previous secret, per host) is a new feature of the deploy process,
  // which needs founder approval (docs/deploy.md 3.4 "founder approval only"). The value fails on the
  // M-148 trace (run sitesDropAfterPartialRunTest).
  val availabilityAfterDrop =
    not(bPrev == 0 and runOp == "none") or PROJECT_SET.forall(p =>
      accepts(running.get(p).secret, bSecret, bPrev) and running.get(p).origin == "good")

  // ---------------------------------------------------------------- reachability witnesses (expected VIOLATED)
  // A production process starts.
  val witness_neverStartsProduction = not(started and declaredEnv(snap.platformEnv, snap.nodeEnv) == "production")
  // A dev process starts and uses a shortcut.
  val witness_neverShortcut = not(shortcutsUsed)
  // The gate refuses a boot.
  val witness_neverRefused = refused == 0
  // A staging process starts.
  val witness_neverStartsStaging = not(started and declaredEnv(snap.platformEnv, snap.nodeEnv) == "staging")
  // The production entry (server.ts) serves.
  val witness_neverBackendUp = not(stage == "up" and entry == "backend")
  // The gate passed and the service still refused (W3-454).
  val witness_neverRefusedAfterGate = not(refused == 0 and failures > 0)
  // The environment row moved from dev to the declared environment (server.ts:44-51).
  val witness_neverDbInit = not(dbEnv == "production" and stage == "up" and entry == "backend")
  // Railway gave up: the service stays down (W3-455).
  val witness_neverDead = stage != "dead"
  // platform-dev.ts wrote PLATFORM_ENV and a shortcut ran (W3-452).
  val witness_neverPlatformDevShortcut = not(entry == "platformDev" and cfg.platformEnv == "" and shortcutsUsed)
  // main.ts trusts X-Forwarded-Host on a local dev bind.
  val witness_neverTrustFwd = lastShortcut != "trustFwdMain"
  // Staging without the Workers AI keys runs on the rules alone (the isProduction split).
  val witness_neverStagingRulesOnly = not(stage == "up" and declared(snap) == "staging" and not(clefKeys) and not(relayHold))
  // A site runs a secret the backend no longer accepts (the M-148 availability break).
  val witness_neverSiteDownAfterDrop = not(dropped and PROJECT_SET.exists(p => not(accepts(running.get(p).secret, bSecret, bPrev))))
  // A run ends with some projects failed.
  val witness_neverPartialRun = not(runOp == "none" and runFailed.size() > 0 and runFailed.size() < 4)

  // ---------------------------------------------------------------- traces
  pure val READY: Config = {
    platformEnv: "production", nodeEnv: "production", otpOk: true, turnstile: true,
    proxyLen: 32, hashLen: 32, sessionLen: 32, db: true, review: Human, devSwitch: false,
    netUrlBlank: false, leakBytes: 32, mig: "distinct", migrateOnBoot: true, svcLoginOk: true, initFlag: false,
    turnRoute: true, turnLen: 32, staffTokenLen: 32, consoleTokenLen: 32, localBind: false,
  }

  // Set the configuration directly (a test step).
  action setCfg(c: Config): bool = all {
    cfg' = c, started' = started, snap' = snap, shortcutsUsed' = shortcutsUsed, refused' = refused,
    entry' = entry, stage' = stage, failures' = failures, lastRefusal' = lastRefusal, dbEnv' = dbEnv, keepRun,
    sitesKeep,
  }
  action setDbEnv(v: str): bool = all {
    dbEnv' = v,
    cfg' = cfg, started' = started, snap' = snap, shortcutsUsed' = shortcutsUsed, refused' = refused,
    entry' = entry, stage' = stage, failures' = failures, lastRefusal' = lastRefusal, keepRun,
    sitesKeep,
  }
  action check(ok: bool): bool = all { assert(ok), procKeep, sitesKeep }

  run declaredEnvTest = all {
    assert(declaredEnv("", "") == ""),
    assert(declaredEnv("other", "production") == ""),
    assert(declaredEnv("", "test") == "dev"),
    assert(declaredEnv("staging", "production") == "staging"),
    assert(not(devAllowed("dev", "production"))),
    assert(devAllowed("dev", "")),
    assert(not(devAllowed("", ""))),
  }

  run bootGateTest = all {
    assert(bootOk(READY)),
    assert(not(bootOk({ ...READY, hashLen: 10 }))),
    assert(not(bootOk({ ...READY, review: Auto }))),
    assert(not(bootOk({ ...READY, devSwitch: true }))),
    assert(not(bootOk({ ...READY, platformEnv: "", nodeEnv: "" }))),
    assert(not(bootOk({ ...EMPTY, platformEnv: "dev", nodeEnv: "production" }))),
    assert(bootOk({ ...EMPTY, platformEnv: "dev" })),
  }

  // The two gates differ (W3-448): loadConfig accepts dev that says production, NETWORK_REVIEW_MODE=auto
  // and a dev switch; bootProblems does not check LEAK_LABEL_KEY or the migration login.
  run loadConfigGateTest = all {
    assert(loadConfigOk(READY)),
    assert(loadConfigOk({ ...EMPTY, platformEnv: "dev", nodeEnv: "production", db: true })),
    assert(loadConfigOk({ ...READY, review: Auto, devSwitch: true })),
    assert(not(loadConfigOk({ ...READY, leakBytes: 10 }))),
    assert(bootOk({ ...READY, leakBytes: 0 })),
    assert(not(loadConfigOk({ ...READY, mig: "same" }))),
    assert(bootOk({ ...READY, mig: "same" })),
    assert(not(loadConfigOk({ ...EMPTY, platformEnv: "dev", proxyLen: 10, db: true }))),
  }

  run shortSecretRefusedTest =
    init
      .then(setCfg({ ...READY, sessionLen: 10 }))
      .then(boot)
      .then(check(not(started) and refused == 1))

  run productionHasNoShortcutTest =
    init
      .then(setCfg(READY))
      .then(boot)
      .then(check(started and not(devAllowed(snap.platformEnv, snap.nodeEnv))))

  run devShortcutTest =
    init
      .then(setCfg({ ...EMPTY, platformEnv: "dev" }))
      .then(boot)
      .then(useShortcut)
      .then(check(shortcutsUsed and safety))

  // Production through server.ts: the gate, the one-way init dev -> production, the login check, up.
  run backendProductionTest =
    init
      .then(setCfg({ ...READY, initFlag: true }))
      .then(bootBackend)
      .then(backendInit)
      .then(check(dbEnv == "production" and stage == "service"))
      .then(construct)
      .then(check(stage == "up" and svcReview == Human and safety))

  // Without PLATFORM_DB_ENVIRONMENT_INIT a fresh database says dev and start() refuses.
  run backendFreshDbRefusedTest =
    init
      .then(setCfg(READY))
      .then(bootBackend)
      .then(backendInit)
      .then(construct)
      .then(check(stage == "down" and lastRefusal == "db_env" and refused == 0 and failures == 1))

  // Q-boot_config-W4-1 (W3-449 with an OTP provider set): server.ts starts PLATFORM_ENV=dev with
  // NODE_ENV=production; no leak key, no session secret, a superuser login.
  run backendDevProductionTest =
    init
      .then(setCfg({ ...EMPTY, platformEnv: "dev", nodeEnv: "production", db: true, hashLen: 32,
                     turnstile: true, otpOk: true, svcLoginOk: false }))
      .then(bootBackend)
      .then(backendInit)
      .then(construct)
      .then(check(stage == "up" and not(startedDevNotProduction) and not(upLiveLeakKeyed)
                  and not(upLiveOwnSessionSecret) and not(upLiveServiceLogin)))

  // W3-450: server.ts starts production with NETWORK_REVIEW_MODE=auto and a PLATFORM_DEV_* switch
  // (loadConfig does not read them; nothing else does either). The review of the service stays human.
  run backendIgnoresReviewModeTest =
    init
      .then(setCfg({ ...READY, review: Auto, devSwitch: true, initFlag: true }))
      .then(bootBackend)
      .then(backendInit)
      .then(construct)
      .then(check(stage == "up" and not(startedDeployedIsReady) and upReviewHuman))

  // Q-boot_config-W4-2: a production process with no environment row starts (service.ts:521 `envRow &&`).
  run missingEnvRowTest =
    init
      .then(setCfg(READY))
      .then(setDbEnv("missing"))
      .then(bootBackend)
      .then(backendInit)
      .then(construct)
      .then(check(stage == "up" and not(upDbAgrees)))

  // W3-457: a 10-character staff token in production.
  run shortStaffTokenTest =
    init
      .then(setCfg({ ...READY, staffTokenLen: 10, initFlag: true }))
      .then(bootBackend)
      .then(backendInit)
      .then(construct)
      .then(check(stage == "up" and not(upLiveStaffTokensLong)))

  // W3-458: NETWORK_DATABASE_URL="" passes assertBootConfig, then main.ts throws.
  run mainBlankDbUrlTest =
    init
      .then(setCfg({ ...READY, netUrlBlank: true }))
      .then(boot)
      .then(mainDbUrl)
      .then(check(stage == "down" and not(mainDbMatchesGate)))

  // Q-boot_config-W4-3: main.ts starts production without LEAK_LABEL_KEY and with a superuser login.
  run mainProductionNoLeakKeyTest =
    init
      .then(setCfg({ ...READY, leakBytes: 0, svcLoginOk: false }))
      .then(setDbEnv("production"))
      .then(boot)
      .then(mainDbUrl)
      .then(construct)
      .then(check(stage == "up" and not(upLiveLeakKeyed) and not(upLiveServiceLogin)))

  // W3-455: six failed starts, then Railway stops restarting.
  run restartBudgetTest =
    init
      .then(setCfg({ ...READY, sessionLen: 0 }))
      .then(6.reps(_ => bootBackend))
      .then(check(stage == "dead" and failures == 6 and refused == 6))

  // W3-452: platform-dev.ts writes PLATFORM_ENV=dev, so an undeclared environment gets the shortcuts.
  run platformDevWriteTest =
    init
      .then(setCfg({ ...EMPTY, nodeEnv: "other" }))
      .then(bootPlatformDev)
      .then(construct)
      .then(check(stage == "up" and snap.platformEnv == "dev" and shortcutsUsed and safety))

  // main.ts:47: the local dev bind trusts X-Forwarded-Host; the same config in production cannot.
  run trustForwardedHostTest =
    init
      .then(setCfg({ ...EMPTY, platformEnv: "dev", localBind: true }))
      .then(boot)
      .then(mainDbUrl)
      .then(check(stage == "down" and lastRefusal == "main_db_url"))
      .then(setCfg({ ...EMPTY, platformEnv: "dev", localBind: true, db: true }))
      .then(boot)
      .then(mainDbUrl)
      .then(check(callerAllows("trustFwdMain", entry, snap) and not(callerAllows("trustFwdMain", entry, { ...snap, nodeEnv: "production" }))))

  // ---------------------------------------------------------------- part B traces
  // The runbook as written: rotate, a green repair-proxy-and-deploy run on all four, then step 3.
  run sitesRotationTest =
    init
      .then(rotateBackend)
      .then(startAs("repairProxy"))
      .then(approveAs(true))
      .then(4.reps(_ => inspectWith(false, false).then(deployWith(false)).then(smokeWith(true, false))))
      .then(dropPrevious)
      .then(check(runOp == "none" and runFailed.size() == 0 and availabilityAfterDrop and safety))

  // M-148: the Inspect of ntwrk-party fails (a binding that needs owner review); peon-biz and
  // friends-help still deploy; the run is red, three sites work; the operator runs step 3; ntwrk.party
  // signs with the old secret and the backend answers 421 edge_required on /api, /mcp and /oauth.
  run sitesDropAfterPartialRunTest =
    init
      .then(rotateBackend)
      .then(startAs("repairProxy"))
      .then(approveAs(true))
      .then(inspectWith(false, false)).then(deployWith(false)).then(smokeWith(true, false))
      .then(inspectWith(true, false))
      .then(inspectWith(false, false)).then(deployWith(false)).then(smokeWith(true, false))
      .then(inspectWith(false, false)).then(deployWith(false)).then(smokeWith(true, false))
      .then(check(runOp == "none" and runFailed == Set("ntwrk-party")))
      .then(dropPrevious)
      .then(check(not(availabilityAfterDrop) and not(accepts(running.get("ntwrk-party").secret, bSecret, bPrev)) and safety))

  // A dashboard rollback after a full rotation brings back the old bindings: the site answers 421.
  run sitesRollbackAfterDropTest =
    init
      .then(rotateBackend)
      .then(startAs("repairProxy"))
      .then(approveAs(true))
      .then(4.reps(_ => inspectWith(false, false).then(deployWith(false)).then(smokeWith(true, false))))
      .then(dropPrevious)
      .then(all {
        running' = running.set("slop-date", prev.get("slop-date")), prev' = prev.set("slop-date", running.get("slop-date")),
        stored' = stored, runOp' = runOp, runApproved' = runApproved, runCur' = runCur, runStep' = runStep,
        runFailed' = runFailed, bSecret' = bSecret, bPrev' = bPrev, ghSecret' = ghSecret, dropped' = dropped,
        ghostUnapproved' = ghostUnapproved, ghostSecretNoRotation' = ghostSecretNoRotation, ghostPushPatched' = ghostPushPatched,
        procKeep,
      })
      .then(check(not(availabilityAfterDrop) and stored.get("slop-date").secret == bSecret))

  // A push with a stale origin binding is refused at Inspect and changes nothing.
  run sitesPushStaleOriginTest =
    init
      .then(all { stored' = stored.set("slop-date", { secret: 1, origin: "stale" }),
                  running' = running, prev' = prev, runOp' = runOp, runApproved' = runApproved, runCur' = runCur,
                  runStep' = runStep, runFailed' = runFailed, bSecret' = bSecret, bPrev' = bPrev, ghSecret' = ghSecret,
                  dropped' = dropped, ghostUnapproved' = ghostUnapproved, ghostSecretNoRotation' = ghostSecretNoRotation,
                  ghostPushPatched' = ghostPushPatched, procKeep })
      .then(startAs("deploy"))
      .then(approveAs(true))
      .then(inspectWith(false, false))
      .then(check(runFailed == Set("slop-date") and stored.get("slop-date").origin == "stale" and safety))
}
