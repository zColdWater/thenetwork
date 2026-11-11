# Quint findings: `quint/boot_config.qnt`

Model: [quint/boot_config.qnt](../../../quint/boot_config.qnt). Module plan: section 9.6 of
[the state-machine report](../2026-11-07-state-machines.md) (`boot_config`, P1, 11 items). The wave 3 audit
of this model is [audit-boot_config.md](../state-machines/wave3/audit-boot_config.md).
This file is hand-written. The check results are copied from the commands named with them.

## Wave 4, after the fixes (final state)

Compared with the code at b5f026d (branch wave4/boot_config, the five fix commits on e4f0a32).

The model now follows the fixed code. `safety` holds (all 18 invariants), every witness is reachable,
and the run tests replay the fixed traces. The section "Wave 4" below is the model as it was before the
fixes; its counterexamples are the defects that the fix commits close.

### Items after the fixes

| Item | Result | Commit | Test that failed before the fix | Model change |
|---|---|---|---|---|
| Q-boot_config-W4-1 | fixed | 3ef93b6 | deploy/backend/boot-config-w4.integration.test.ts "Q-boot_config-W4-1: server.ts refuses PLATFORM_ENV=dev with NODE_ENV=production" | `loadConfigOk` is now `bootOk` and the backend's own checks (a database in every environment, the migration login, the proxy secret length in every environment); the duplicate deployed checks are gone. Run tests `loadConfigGateTest`, `backendDevProductionTest` (server.ts, main.ts, platform-dev.ts and the MCP dev server all refuse dev that says production) and `backendIgnoresReviewModeTest` (server.ts refuses NETWORK_REVIEW_MODE=auto and a PLATFORM_DEV_* switch). |
| Q-boot_config-W4-2 | fixed | 8935589 | packages/network/test/boot-config-w4.integration.test.ts "Q-boot_config-W4-2: a staging service refuses to start when platform.settings has no environment row" | `serviceRefusal` refuses `db_env` when the row is missing (`dbEnv != declared(c)`, service.ts:523-525). Run test `missingEnvRowTest` (production on server.ts and dev on main.ts both refuse). |
| Q-boot_config-W4-3 | fixed | ab19a16 | deploy/backend/boot-config-w4.integration.test.ts "Q-boot_config-W4-3: main.ts refuses production without LEAK_LABEL_KEY, and with a superuser service login" | `deployedReady` has `leakBytes >= 32` (env-core.ts:100, BootFacts.leakKeyBytes); `startedDeployedIsReady` names the same rule (env.ts comment). `mainDbUrl` refuses `service_login` outside dev (main.ts:39-45). Run test `mainProductionNoLeakKeyTest`. |
| W3-457 | fixed | d49a578 | packages/network/test/boot-config-w4.integration.test.ts "W3-457: a staging service refuses a staff token or a console token shorter than 32 characters" | `serviceRefusal` refuses `staff_token` and `console_token` outside dev, after the hash key (service.ts:352-354). Run test `shortStaffTokenTest` (production staff token, staging console token refused; dev accepts both). |
| W3-458 | fixed | b5f026d | deploy/backend/boot-config-w4.integration.test.ts "W3-458: main.ts takes DATABASE_URL when NETWORK_DATABASE_URL is empty, as the gate does" | `mainDbUrl` refuses only when no URL is set (`||`, main.ts:36-37). Run test `mainBlankDbUrlTest` (the process comes up). |
| W3-344, W3-448, W3-450 to W3-456 | modelled | (wave 4 model commit 770c336) | none (model items) | No change in meaning. W3-448: the two gates now differ only by the backend's own extra checks. |

Not reproduced: none. Skipped: none. `availabilityAfterDrop` (W3-344, M-148) stays outside `safety`, with
its reason in the model and below: a check needs a new deploy-process feature (founder approval only).

### Model changes that are not fixes

- ASSUMPTION (new, in the header): the owner edits the platform.settings environment row only while no
  process runs; `editEnvRow` has the guard `not(started)`. With the missing-row fix, the only trace left
  for `upDbAgrees` was an owner edit while the service is up. The service logins can only read the row
  (migration 0004:163 grant select, 0007:237 revoke update), start() checks it once, and an owner edit
  changes the 555-01xx guard at once whatever the process does, so no process check can see it.
- Sampling only (the reachable configurations do not change): `configureNear` starts from READY with
  PLATFORM_DB_ENVIRONMENT_INIT=1 and a free main.ts bind, its option k=2 varies the staff token or the
  console token, and k=8 varies the turn route and the turn secret; half of the `editEnvRow` choices set
  the row to the declared environment. Before the fixes a missing row let a deployed service come up
  easily; after them the simulator needs these weights to reach the deployed services that the
  mutation probes below need.

### Mutation probes after the fixes

Copies of the fixed model in the session scratchpad, each with one fix taken back out and `--invariant`
on one value (`quint run --backend rust --seed 0x5eed --max-steps 20 --max-samples 3000`). The copies were
deleted.

| Probe | Fix taken out | Value | Result |
|---|---|---|---|
| M5 | a missing environment row passes start() (W4-2) | `upDbAgrees` | violated |
| M6 | no staff token length check (W3-457) | `upLiveStaffTokensLong` | violated |
| M6b | no console token length check (W3-457) | `upLiveStaffTokensLong` | violated |
| M7 | loadConfig without the gate (W4-1) | `startedDevNotProduction` | violated |
| M8 | main.ts without the service-login check (W4-3) | `upLiveServiceLogin` | violated with `--max-samples 30000` (not found at 3000: it needs five specific steps; `mainProductionNoLeakKeyTest` replays it, and Apalache covers it within 8 steps) |
| M9 | bootProblems without LEAK_LABEL_KEY (W4-3) | `upLiveLeakKeyed` | violated |
| M10 | main.ts with `??` (W3-458) | `mainDbMatchesGate` | violated |

### Checks after the fixes

- `bun run quint:check quint/boot_config.qnt` (header bounds max-steps 20, max-samples 3000): typecheck ok,
  test ok (21 run tests), all 14 witnesses reachable, `safety` ok. 33 s wall time on the shared machine
  (`safety` alone 14 s to 20 s).
- `bun run quint:check --verify quint/boot_config.qnt` (Apalache, verify-steps 8, the default): all checks ok, `verify safety` ok in 468 s (8 min). The verify-steps bound is not lowered.
- `bun test --conditions eliza-source --timeout 120000 deploy/backend/boot-config-w4.integration.test.ts
  packages/network/test/boot-config-w4.integration.test.ts`: 5 pass, 0 fail.

## Wave 4, before the fixes

This section is the model at commit 770c336, before the fix commits. The section above is the final state.

### What the model had

Part A, the process (four entry points, each with the gate its code runs now):

| Entry | Code | Gate in the model | Then |
|---|---|---|---|
| `main` | `packages/network/service/main.ts:31-35` | `bootOk` (env-core.ts bootProblems) | `mainDbUrl` (the `??` read), `construct` |
| `backend` (production: Dockerfile CMD, railway.toml) | `deploy/backend/server.ts:31-60`, `backend.ts:85-113` | `loadConfigOk` | `backendInit` (environment-row init, service-login check), `construct` |
| `platformDev` | `scripts/platform-dev.ts:45-61` | not isProduction, then its two env writes | `construct` |
| `mcpDev` | `packages/mcp/src/dev-server.ts:11` | `devAllowed` | up (memory stores) |

`construct` is the NetworkService constructor, the public API that server.ts builds at boot and
`start()`, with each refusal in code order (`serviceRefusal`). A failed start exits 1; Railway restarts
it at most 5 times (`MAX_RESTARTS`), then the stage is `dead` until a new deployment (`configure`).
`dbEnv` is the `platform.settings` environment row (migration 0003 makes it `dev`). Each caller of
`devShortcutsAllowed` is one shortcut kind with its own guard (`callerAllows`).

Part B, the sites deploy workflow (`.github/workflows/deploy-sites.yml`) and the rotation runbook
(`docs/deploy.md` 3.4) for the four Pages projects: stored bindings, running bindings, the deployment
before (rollback target), the run (approval, then per project Inspect, PATCH and readback, deploy, smoke,
in matrix order, fail-fast false), and the backend's current and previous proxy secret.

The wave 2 model is kept: the four invariants, the four witnesses and the six run tests are unchanged in
meaning. The run tests now use the helper actions `setCfg` and `check`, because the model has more state
variables.

### Items

| Item | Kind | What I did |
|---|---|---|
| W3-344 | new_machine | Part B (actions `startRun`, `approve`, `inspect`, `deploy`, `smoke`, `rotateBackend`, `dropPrevious`, `rollback`). Safety: `sitesOnlyApproved`, `sitesSecretOnlyByRotation`, `sitesPushNeverPatches`, `edgeRefusesUnsigned`. Availability is the named value `availabilityAfterDrop`, outside `safety`, with its reason in the model. Run tests `sitesRotationTest`, `sitesDropAfterPartialRunTest`, `sitesRollbackAfterDropTest`, `sitesPushStaleOriginTest`. |
| W3-448 | model_error | The header now says which entry runs which gate. New action `bootBackend` with `loadConfigOk`, a def that copies backend.ts:85-113. `startedDevNotProduction` now fails on the server.ts path (Q-boot_config-W4-1). `loadConfigGateTest` pins the five differences between the two gates. The coverage row of env.ts names the gap. The drift entry is not changed here (a later stage stamps). |
| W3-450 | model_error | The two clauses stay (a tripwire for an operator). The header says that nothing else reads NETWORK_REVIEW_MODE or PLATFORM_DEV_*, and that human review is proved in quint/opportunity.qnt. The real review source is modelled: `entryReview` (both entries pass no `review`, so the default `human`) and the refusal of service.ts:336. New invariant `upReviewHuman`; it can fail (mutation M3 below). |
| W3-451 | model_error | The invariants no longer only restate the guards: four entries with different gates, the post-gate refusals and seven shortcut callers with their own guards. New invariants are written from the rules (deploy.md, AGENTS.md, code comments), not from the defs. Mutations M1 to M4 below show that they fail when one guard changes. |
| W3-452 | model_error | Written as a named ASSUMPTION in the header: no code snapshots the environment; the production entries write no variable. `snap` is now the environment the callers read: `bootPlatformDev` applies `PLATFORM_ENV ??= "dev"` and `PLATFORM_PROXY_SECRET ||=` before `construct`. Run test `platformDevWriteTest`, witness `witness_neverPlatformDevShortcut`. |
| W3-453 | model_gap | `dbEnv` in {missing, dev, staging, production}; the one-way init in `backendInit` (deployed and `PLATFORM_DB_ENVIRONMENT_INIT=1` and row `dev`; kept when the login check then refuses); the start() check in `serviceRefusal`; `editEnvRow` for a deleted or hand-set row. New invariant `upDbAgrees`: it fails on a missing row (Q-boot_config-W4-2). |
| W3-454 | model_gap | `construct` with each refusal (review option, turn secret, hash key, OTP provider, Turnstile verifier, environment row). Witness `witness_neverRefusedAfterGate` ("the gate passed, the service still refused"). The isProduction split: `relayHoldsAll` (relay-endpoint.ts:86), invariant `upProductionRelayClosed`, witness `witness_neverStagingRulesOnly`. main.ts:47 is the shortcut kind `trustFwdMain` with its real guard. |
| W3-455 | model_gap | `failures`, `MAX_RESTARTS = 5`, stage `dead`, invariant `deadIsDown`, witness `witness_neverDead`, run test `restartBudgetTest`. Length units are in the header: proxy, hash and session in UTF-16 units, LEAK_LABEL_KEY in bytes (`leakBytes`); the unit check is the stricter one, so no rule is at risk. |
| W3-456 | open_carveout | Closed in scope. `callShortcut` takes one of seven kinds (otp.ts:36, turnstile.ts:41, api.ts:132-135 with service.ts:348, service.ts:383, serve.ts:39 with handler.ts:194, handler.ts:157, main.ts:47). `construct` takes the dev fallbacks (`constructShortcut`). `bootMcpDev` is dev-server.ts:11. All ask devAllowed except main.ts:47, which asks the gate's result; mutation M2 shows that it is safe only because the main.ts gate refuses dev that says production, and M1 shows that the same decision on server.ts would break `shortcutsOnlyInDev`. The drift entry is for the later stamp stage. |
| W3-457 | suspected_defect (confirmed) | New invariant `upLiveStaffTokensLong`; it fails (run test `shortStaffTokenTest`). In code_items. |
| W3-458 | suspected_defect (disputed) | `mainDbUrl` reads with `??`; invariant `mainDbMatchesGate` fails (run test `mainBlankDbUrlTest`). Benign: the process fails closed. In code_items, last. |

### Counterexamples (real code defects)

**Q-boot_config-W4-1 (P1): server.ts starts PLATFORM_ENV=dev with NODE_ENV=production.** This is
W3-449 with an OTP provider configured (W3-449 was refuted only because its trigger had no OTP provider,
so otp.ts:36 refused the console provider). Trace (`backendDevProductionTest`):

1. `configure` PLATFORM_ENV=dev, NODE_ENV=production, DATABASE_URL, PLATFORM_HASH_KEY (32),
   TURNSTILE_SECRET_KEY, OTP_PROVIDER=twilio with its credentials, a superuser login, no
   PLATFORM_SESSION_SECRET, no LEAK_LABEL_KEY.
2. `bootBackend`: backend.ts:87 requirePlatformEnv gives `dev`; :89 `deployed` is false, so :93-112 skip
   the session secret, LEAK_LABEL_KEY, proxy secret and migration login checks. Gate passes.
3. `backendInit`: server.ts:44 and :57 run only when deployed: no init, no service-login check.
4. `construct`: service.ts:519-521 passes (declared dev, row dev). devAllowed is false
   (productionEnv), so api.ts:135 uses PLATFORM_HASH_KEY as the session secret.
5. Up. Violated: `startedDevNotProduction`, `upLiveLeakKeyed`, `upLiveOwnSessionSecret`, `upLiveServiceLogin`.

bootProblems (env-core.ts:120) refuses this configuration; loadConfig does not call it. Fix: loadConfig
calls `bootConfigProblems(e)` first and keeps its own extra checks. Test: a case in a new
`deploy/backend/boot-config-w4.integration.test.ts` that starts server.ts with this environment and
expects exit 1 (it starts before the fix).

**Q-boot_config-W4-2 (P1): a production process starts with no environment row.** Trace
(`missingEnvRowTest`): `editEnvRow` missing, `bootBackend` (READY), `backendInit`, `construct`: up.
service.ts:521 `declared && envRow && ...` passes when the row is missing, and then the 555-01xx trigger of
migration 0003 (`refuse_synthetic_phone`, which reads the row) is off in production. Violated:
`upDbAgrees`. Fix: refuse to start when the row is missing. Test: an integration case that deletes the row
and expects `start()` to throw.

**Q-boot_config-W4-3 (P2): the proved gate lacks the deployed checks that loadConfig has.** Trace
(`mainProductionNoLeakKeyTest`): READY without LEAK_LABEL_KEY and with a superuser login, row
`production`, `boot`, `mainDbUrl`, `construct`: up. bootProblems does not require LEAK_LABEL_KEY, a
separate migration login or a non-superuser service login, and main.ts does not run serviceLoginProblem.
Violated: `upLiveLeakKeyed`, `upLiveServiceLogin`. main.ts is not the production entry today, so the
effect is low; the fix of W4-1 makes bootProblems the one gate, so the LEAK_LABEL_KEY rule belongs in it.
Fix: add LEAK_LABEL_KEY (32 bytes) to bootProblems; main.ts calls serviceLoginProblem when deployed.

**W3-457 (P2, confirmed): short staff bearer tokens in a deployed service.** Trace
(`shortStaffTokenTest`): READY with NETWORK_SERVICE_TOKENS="reviewer@*:<10 chars>", `bootBackend`,
`backendInit`, `construct`: up. service.ts:351 calls parseTokenGrants without `minLength`
(observatory/src/staff.ts:55 checks only when it is set); NETWORK_SERVICE_CONSOLE_TOKEN has no length
check (service.ts:340). Violated: `upLiveStaffTokensLong`. Fix: pass `minLength: 32` outside dev and check
the console token. Test: an integration case that builds the service with a short token in staging and
expects a refusal.

**W3-458 (P2, disputed, benign): main.ts `??` against the gate's "non-empty".** Trace
(`mainBlankDbUrlTest`): READY with NETWORK_DATABASE_URL="", `boot` passes (env-core.ts:98), `mainDbUrl`
throws (main.ts:34-35). Violated: `mainDbMatchesGate`. Fails closed; only the error is wrong. Fix: `||`, as
backend.ts:90.

### Not a code item, with the reason

`availabilityAfterDrop` (W3-344, M-148) fails on `sitesDropAfterPartialRunTest`: rotate, then a
repair-proxy-and-deploy run where ntwrk-party's Inspect fails (deploy-sites.yml:146-149) while the other
three deploy (fail-fast false), then runbook step 3: ntwrk-party still signs with the old secret and the
backend answers 421 `edge_required` (backend.ts:388,399). `sitesRollbackAfterDropTest` shows the same after
a dashboard rollback. No code checks that all four projects run the new value before step 3. A check (for
example a per-host count of signatures made with the previous secret) is a new feature of the deploy
process, which is founder approval only (docs/deploy.md 3.4), so it stays a named value outside `safety`.

### Mutation probes (W3-450, W3-451, W3-456)

Copies of the model in the session scratchpad, each with one change and `--invariant` on one value
(`quint run --backend rust --seed 0x5eed --max-steps 12 --max-samples 3000`). The copies were deleted.

| Probe | Change | Value | Result |
|---|---|---|---|
| M1 (W3-451, W3-456) | the main.ts:47 decision (`local && env === "dev"`, no api.ts:136 re-check) also on server.ts | `shortcutsOnlyInDev` | violated: server.ts passes dev that says production |
| M2 (W3-456) | main.ts:47 without the api.ts:136 re-check, main.ts only | `shortcutsOnlyInDev` | holds: main.ts:47 is safe only because assertBootConfig refuses dev that says production |
| M3 (W3-450) | each entry passes NETWORK_REVIEW_MODE as the `review` option, and the service.ts:336 refusal is removed | `upReviewHuman` | violated |
| M4 (W3-451) | a run starts in Inspect without the environment approval | `sitesOnlyApproved` | violated |

So the invariants are not vacuous: each one fails when the code guard it depends on changes, and M2 shows
which guard main.ts:47 depends on.

### Checks

`bun run quint:check quint/boot_config.qnt --jobs 4` (2026-11-11): typecheck ok, test ok (21 run tests),
all 14 witnesses reachable, `safety` FAILS (expected: it shows the defects above).

Each invariant alone (`quint run --backend rust --seed 0x5eed --max-steps 20 --max-samples 3000 --invariant <name>`):

| Invariant | Result | Why |
|---|---|---|
| startedOnlyDeclared, shortcutsOnlyInDev, upReviewHuman, upProductionRelayClosed, deadIsDown, startedMatchesStage, sitesOnlyApproved, sitesSecretOnlyByRotation, sitesPushNeverPatches, edgeRefusesUnsigned | holds | |
| startedDevNotProduction | violated | Q-boot_config-W4-1 |
| startedDeployedIsReady | violated | server.ts starts production with NETWORK_REVIEW_MODE=auto or a PLATFORM_DEV_* switch (`backendIgnoresReviewModeTest`). Nothing reads those variables (W3-450), so no behaviour changes; the fix of W4-1 closes it. |
| upLiveLeakKeyed, upLiveServiceLogin | violated | Q-boot_config-W4-1 (server.ts), Q-boot_config-W4-3 (main.ts) |
| upLiveOwnSessionSecret | violated | Q-boot_config-W4-1 |
| upDbAgrees | violated | Q-boot_config-W4-2 |
| upLiveStaffTokensLong | violated | W3-457 |
| mainDbMatchesGate | violated | W3-458 |
| availabilityAfterDrop (not in safety) | violated | M-148, see above |

A simulation note: the guard `not(started)` of `configure` comes before its 22 nondet choices. With the
guard after them, the evaluator searched the choices for an enabled branch while the process ran, and one
sample took more than ten minutes. The bounds are max-steps 20 and max-samples 3000; the full rotation
(16 steps) is the run test `sitesRotationTest`, not a witness. `configureNear` (READY with the two
environment variables and one other variable free) makes the deployed configurations frequent in a
random walk.

Not done here (later stages): quint/drift.json is not stamped. docs/formal-coverage.md now names
boot_config for deploy-sites.yml, backend.ts, server.ts, pages-worker.ts and main.ts.
