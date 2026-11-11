# Quint findings: `quint/cloud_auth.qnt`

Model: [quint/cloud_auth.qnt](../../../quint/cloud_auth.qnt). Module plan: [state-machine report, section 9.6.2](../2026-11-07-state-machines.md) (`cloud_auth`, new, P1).
Code base: branch `wave4/cloud_auth`, made from e4f0a32. The model follows that code. This file is hand-written. The traces come from
the `run` tests in the model and from the Quint simulator (seed `0x5eed`).

## Wave 4

### 1. What the model covers

| Machine | Model actions | Code |
|---|---|---|
| auth mode per app (production, staging-local, off) | `cfg`, `restart` | api.ts:153-193 (cloudFor) |
| Cloud sign-in (callback) | `cloudLogin` | api.ts:413-455, cloud-delegation.ts:22-28 |
| OTP login (only its mode guard) | `otpLogin` | api.ts:482-499 |
| cloud-session-validation with the `validated` TTL cache | `reqBegin`, `cloudAnswer`, `reqEnd` / `reqEndWith`, `cacheClear` | api.ts:264-300, 314-322, 660-667 |
| Cloud grant authority and validation | `reqBegin(_, "grant")`, `grantBegin`, `cloudAnswer`, `grantEnd` | api.ts:668-697, mcp handler.ts:549, 775-786 |
| Cloud-issued proof clock skew | `proofArrives` | network-delegation.ts:41, proof-window.ts:10 and its four Cloud callers |
| other actors | `cloudRevoke`, `cloudBind`, `recycle` / `recycleStale`, `textJoin`, `ban`, `tick` | Cloud, carrier, accounts.createPerson + bindSessions, bans |

Proof states: issued (a session holds it), validated (a live cache entry), expired (`now >= expiresAt`), revoked (Cloud denies it).
One validation is three actions (begin, Cloud answer, end), because `validate()` is an await (api.ts:277, 695).

Named assumption **ASSUME_CLOUD_PHONE_CURRENT** (W3-127): the phone that Cloud signs into a Network delegation names the
current holder of the number. `recycle` keeps it (Cloud drops other accounts' bindings to the number at once);
`recycleStale` is the same carrier event without it. Nothing in this repository can check it; it needs an upstream answer
(does Cloud re-verify the phone within the 45-day carrier aging?).

### 2. Items

| Id | Kind | What I did |
|---|---|---|
| W3-125 | model_gap | Modelled the per-app auth mode: `cfg` has `prod` and `cloudApps` (production: all four apps; staging-local: only the app of NETWORK_CLOUD_AUTH_SITE_ORIGIN; off: none). `restart` changes the env and drops the in-memory cache and the requests in flight. Invariant `authModeMatches` (a login path runs and a session is accepted only on an app of its mode). Run tests `w3_125PerAppModeTest`, `w3_125GuardsTest`, `w3_125CloudGuardTest`; witness `witness_otpRefusedOnCloud`. Holds. Mutation check: with the OTP guard removed from `otpLogin`, the simulator finds a violation at once. |
| W3-126 | model_gap | Modelled cloudGrantAuthority (a grant from a valid Cloud session, personId from personFor, expiry min(session, proof)) and validateCloudGrant (checks before the Cloud call, the Cloud answer, the expiry check after it). Invariant `cloudActsForHolder` covers grants; `bannedGrantRefused` and `expiredNeverAccepted` too. Result: the null-personId acceptance (api.ts:693) is safe only under ASSUME_CLOUD_PHONE_CURRENT. `w3_126NullGrantTest` shows that without it an earlier holder's person-less grant acts for the new holder's person (text joins end person-less sessions, but not grants). `w3_126AssumptionTest`: with the assumption, Cloud denies it. No separate code fix: a refusal of null-personId grants once the number has a person would also break the holder's own MCP signup (the grant stays person-less after submit_profile). |
| W3-127 | model_error | The assumption is now explicit and named in the header (ASSUME_CLOUD_PHONE_CURRENT), and `cloudLogin` runs for whatever human Cloud binds to the number (not only the holder). `cloudActsForHolder` holds with the assumption and fails without it (`w3_127StaleProofTest`: Cloud keeps bob on Y, the carrier gives Y to alice, alice joins by text, bob signs in and his session acts for alice's person), so the invariant is not vacuous. Blocked for a code fix: it needs an upstream confirmation of Cloud's phone re-verification. |
| W3-134 | open_carveout (SD-308) | Re-checked at e4f0a32: proofWindowOk (proof-window.ts:7-11) still refuses `issuedAt > now`, and its four Cloud-issued callers pass no skew: profile-review-owner.ts:55, profile-review-source.ts:68, profile-review-withdrawal.ts:49, profile-review-disconnect.ts:54 (learning-consent-context.ts:62 is issued by this backend, not by Cloud). The login and grant parsers allow 30 s (network-delegation.ts:41, api.ts:438, 684). Invariant `cloudProofSkewTolerated` fails: counterexample `w3_134SkewTest`. Still wrong and in scope: in code_items. |
| W3-373 | new_machine | Modelled the `validated` map: absent or valid-until(t); written on the callback, on a positive validation (also in production, where it is never read); deleted on a bad identity cookie, an expired proof or a non-valid answer; cleared above 10 000 entries (`cacheClear`); lost on restart. The rotation write (api.ts:330) cannot run for a Cloud session: its life is at most 1 h and sessions.ts:53 rotates after 24 h (invariant `cloudSessionNeverRotates`). By design a revocation that no request has seen is accepted from the cache for up to 60 s (`witness_revokedWithinTtl`, `w3_373CacheTtlTest`). The rule "a denial is never cached" is `denialNeverCached`; it fails through W3-671. |
| W3-671 | model_gap | Split validation into begin, Cloud answer and end. `denialNeverCached` FAILS (counterexample below). The proposed generation-counter fix is the parameter `genFix` of `reqEndWith`; `w3_671FixTest` shows that the invariant holds with it. Production is not affected (`w3_671ProductionTest`): no request reads the cache there. In code_items. |

### 3. Counterexamples

**W3-671: a late positive answer overwrites a delivered denial** (`w3_671LateValidTest`, quint/cloud_auth.qnt:631; staging-local or
dev only, `!productionCloud`):

1. `cloudLogin("alice","slop")` - session 1, cache entry until t+60 (api.ts:447).
2. `tick(61)` - the entry is old.
3. `reqBegin(1,"auth")` - request A calls validate() (api.ts:277).
4. `cloudAnswer(1, valid)` - Cloud says valid for A (the answer is on the wire).
5. `cloudRevoke(1)` - Cloud revokes the delegation.
6. `reqBegin(1,"site")` - request B through authenticatedSiteSession (the MCP authorize page, api.ts:660-667).
7. `cloudAnswer(2)` - Cloud denies B; `reqEnd(2)` deletes the entry (api.ts:282) but does not revoke the row (api.ts:665: only auth() revokes, api.ts:320).
8. `reqEnd(1)` - A's late "valid" writes the entry again (api.ts:281). `denialNeverCached` is false.
9. `reqBegin(1,"auth")` - request C is accepted from the cache (api.ts:275) with no Cloud call, for 60 s.

If B goes through auth() the row is revoked and C fails at sessions.authenticate, so the window needs the authorize-page
path (or a grant path, which is production only and has no cache). Fix: a per-session generation counter; a denial bumps
it, and a positive answer is stored only if the counter did not change since the request began. Test: an integration
case in packages/platform/test (staging-local tuple, a controlled Cloud transport that holds A's "valid" until B's 403
returns) that fails before the fix.

**W3-134 / SD-308: a Cloud clock 20 s ahead** (`w3_134SkewTest`, quint/cloud_auth.qnt:813): `proofArrives("login",20)` and
`proofArrives("grant",20)` are accepted; `proofArrives("owner",20)` is refused (proofWindowOk with skew 0). The same holds for
the source, withdrawal and disconnect proofs. Fix: an issuedAt-only skew argument for proofWindowOk (proof-window.ts is a
LemmaScript file: the proof must still pass), 30 s from the four Cloud-issued callers, with one integration case per endpoint.

**W3-127 / W3-126 without the assumption** (`w3_127StaleProofTest`:730, `w3_126NullGrantTest`:740): see section 2. These show
what the assumption carries; they are not code counterexamples until upstream answers.

No new defect (Q-cloud_auth-W4-n) was found. Two smaller observations, not defects:
- authenticatedSiteSession and cloudGrantAuthority do not revoke the session row on "invalid" (auth() does). In production
  the next request asks Cloud again, so this matters only with the cache (it is the precondition of W3-671).
- validateCloudGrant checks the ban, the hold and the owner before the Cloud await (api.ts:693-695). A ban that commits during
  the call can still answer "valid" (`witness_lateBanGrantValid`, `banGrantTest`); the next validation refuses it. This is the
  class of the accepted SD-013 remainder, so `bannedGrantRefused` is stated for a validation that began after the ban.

### 4. Check results

`bun run quint:check quint/cloud_auth.qnt` (max-steps 20, max-samples 10000, seed 0x5eed):

```
ok   typecheck
ok   test                              (16 run tests)
FAIL safety                            (denialNeverCached: W3-671; cloudProofSkewTolerated: W3-134)
ok   witness_cloudLogin, witness_freshAccept, witness_cacheAccept, witness_revokedWithinTtl, witness_grantValid,
     witness_lateBanGrantValid, witness_otpRefusedOnCloud, witness_skewSeen (all reachable)
```

Each invariant alone (3000 to 10000 samples): prodNoCacheAccept, authModeMatches, cloudActsForHolder, bannedGrantRefused,
expiredNeverAccepted and cloudSessionNeverRotates hold; denialNeverCached and cloudProofSkewTolerated are violated.

Mutation checks (temporary edits, reverted): no ban check in `grantBegin` makes `bannedGrantRefused` fail; no `not(cfg.prod)`
in the cache read makes `prodNoCacheAccept` fail; no mode guard in `otpLogin` makes `authModeMatches` fail. With no expiry
check at the end of a validation (api.ts:278) the random simulation did not find a violation in 10000 samples, so the run
test `sessionExpiryInFlightTest` pins that check.

`--verify` (Apalache) was not run in this step.
