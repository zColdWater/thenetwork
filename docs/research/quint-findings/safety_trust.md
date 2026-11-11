# Quint findings: `quint/safety_trust.qnt`

Module plan: [docs/research/2026-11-07-state-machines.md](../2026-11-07-state-machines.md) section 6.9 (P0).
Model: [quint/safety_trust.qnt](../../../quint/safety_trust.qnt). This file is hand-written. The traces are
from `quint run` (seed `0x5eed` unless stated) and from the model's `run` tests.

## 1. Final state

The model follows the code on branch `wave2/safety_trust` after the fixes `f8d9de8..49602b7` and the
SD-044 follow-up fix in this commit. `safety` holds the rules of every fixed defect and passes. The rules
of the skipped defects (SD-027, SD-074, SD-253) and two new findings (NEW-2, NEW-3) stay out of `safety`
as their own named values. Each has a comment with the id and the reason, and a `run` test replays a trace
that breaks it.

What changed in the model, by fix:

| Defect | Commit | Model change |
|---|---|---|
| SD-044 | f8d9de8 + this commit | `metBefore` reads `told` (bookedTold). The check-in record names the `told` people (see 3.1). |
| SD-045 | df588c8 | `callOffPair` closes only items that the blocker and the target are both going to. |
| SD-025 | de48147 | The tick runs `callOffPair` for every person block on every app. `meet` (the tick's advance) cannot finalize an item that two blocked people are going to. |
| SD-021, SD-022 | 059965d | New state `personHolds` (platform.person_holds). A staff hold writes `(p, "*")` first. A leave of a member who is held, has an urgent report open or was reported as a minor writes `(p, app)`. A covered member is out of matching, and `sync` (syncMember/personHold) holds them at their next unit or tick. A lift turns `"*"` into one row per other app and deletes this app's row. |
| SD-141 | db176ce | `addPts` restarts the decay clock at each event with points. |
| SD-072 | ab4ff2a | `reportHeld` skips a report whose reporter is on hold (a blank reporter id counts as "ok"). |
| SD-067 | 0e0bf2a | The check-in reader (an oracle) reads a happy answer as no report. The corpus gate checks the reader itself. |
| SD-220 | 33ea2bc | New action `disclose(k, m, kind)`: a later disclosure in the 7-day window files the check-in report. |
| SD-221 | 9b8ef32 | Both apps have `postDateReports`. |
| SD-222, SD-442 | 581888d | The check-in record has `by` and the meeting time. `noShows` and `dates` count records by that member. |
| SD-229 | db4ea4c | `blockAndReport` is the one path for "report X" and the check-in: trust block, call off, trust report, case event, record, minor step. |
| SD-250 | 4878d3c | `report` routing: a member of several apps whose text names a counterpart goes to the app of the newest meeting with them. |
| SD-254 | fa81646 | Relay decision `blockSevere` writes a 0-point case event. A block for the form (`block`) opens nothing. |
| SD-475 | 49602b7 | The hold notice outside the member's own turn is the `safety` kind. |

Rules that were rewritten:

- `autoHoldFollowsPerson`, `minorSignalFollowsPerson` and `urgentMetReportBlocksMatching` are now in two
  forms. The `InApp` form (same app, any member id: SD-021) is in `safety`. The every-app form is SD-074
  (skipped) and stays out of `safety`. The ghosts `autoHeldP` and `minorP` now hold `(person, app)`.
- `urgentMetReportBlocksMatchingInApp` counts only a report by a reporter in good standing (the SD-072
  rule), and it accepts a staff lift of the rejoined member as the staff decision.
  `minorSignalFollowsPersonInApp` also accepts that lift (see 3.4).
- `reporterNotHeld` now says what SD-072 asks: a live member that a report holds has such a report by a
  reporter who is not on hold and not banned. The earlier form ("every open met urgent report is
  credible") was about the record, but the fix keeps the record for staff.
- `blockClosesAllApps` allows a pair's item on another app to stay booked until that app's next tick (ghost
  `pendingCallOff`, cleared at the tick). The item cannot finalize first. This is the design of the
  SD-025 fix. The app where the block was made still closes the item at once.
- `blockOnlyAffectsPair` is the SD-045 rule: a block calls an item off only when the blocker and the target
  are both going. The stricter earlier form ("nobody else is going") is NEW-3.
- `relayBlockReachesSafety` is about a severe block (the sender's own words), and it asks for a case
  (`caseSt != "none"`), so that a later staff close does not break it.

## 2. Check results

Bounds: 2 apps, 3 adult persons, member generation 0..1, 3 opportunity slots, days 0..60.

| Check | Result |
|---|---|
| `quint typecheck` | ok |
| `quint test` (29 `run` tests) | ok |
| `safety` simulation (max-steps 14, max-samples 6000, seeds `0x5eed`, `0x1234`, `0xbeef`) | ok: no violation |
| 11 witnesses (date done, check-in report, met message report, staff hold, lift to ok, watch, rejoin, ban, carried-over hold on a rejoin, call-off on another app, relay case) | all reachable |
| `quint verify --invariant safety --max-steps 2` (Apalache 0.62.4, verify-steps 2) | ok: no violation (521 s) |

`bun run quint:check --verify` failed to connect to the shared Apalache server on `localhost:8822` (other
sessions use it: "Connection dropped"), so the verify step ran by hand with `--server-endpoint
localhost:18931`. Deeper bounded checks were not run: 2 steps already take 521 s. A witness for the late
disclosure path (SD-220) was not reachable in 6000 random samples of 14 steps (it needs a booked date, the
meeting, a first answer and the disclosure on the same member and slot), so the model has no witness for it;
`sd220DisclosureAfterAnswerTest` replays that path.

The values kept out of `safety`, simulated at the same bounds (seed `0x5eed`):

| Value | Defect | Result |
|---|---|---|
| `autoHoldFollowsPerson` | SD-074 (skipped) | violated |
| `minorSignalFollowsPerson` | SD-074 (skipped) | violated |
| `urgentMetReportBlocksMatching` | SD-074 (skipped) | violated |
| `engineHoldVisible` | SD-027 (skipped) | violated |
| `staffDecisionEndsEngineHold` | SD-027 (skipped) | `sd027TrustReviewTest` and the simulator |
| `pastContactsToldOfBan` | SD-253 (skipped) | violated (`sd253BanNoticeTest`) |
| `reporterStandingKept` | NEW-2 | violated (`new2HeldReporterLeavesTest`) |
| `blockLeavesOthersPlan` | NEW-3 | violated (`new3BlockInPlanTest`) |

## 3. Register defects of this module

### Fixed (16)

Each fix has its test in the code (named in the commit). The model's `run` test for each replays the
earlier counterexample and now ends in a state that keeps the rule:

| Id | Fix commit | Model run test |
|---|---|---|
| SD-021 | 059965d | `sd021LeaveRejoinKeepsHoldTest`, `sd021MinorReportCarriedOverTest` |
| SD-022 | 059965d | `sd022HoldNotAtomicTest`, `sd022JoinDuringHoldTest`, `sd022JoinDuringHoldTextTest` |
| SD-025 | de48147 | `sd025BlockAcrossAppsTest`, `sd025NoMeetingBeforeCallOffTest` |
| SD-044 | f8d9de8, this commit | `sd044sd045DeclinerTest`, `sd044AfterCheckInTest` |
| SD-045 | df588c8 | `sd044sd045DeclinerTest` |
| SD-067 | 0e0bf2a | `sd067HappyCheckInTest`, `sd067NoMisreadTest` |
| SD-072 | ab4ff2a | `sd072BannedReporterTest` |
| SD-141 | db176ce | `sd141WatchLastsTest` |
| SD-220 | 33ea2bc | `sd220DisclosureAfterAnswerTest` |
| SD-221 | 9b8ef32 | `sd221PeonCheckInTest` |
| SD-222 | 581888d | `sd222SelfNoShowTest` |
| SD-229 | db4ea4c | `sd229CheckInCountedTest` |
| SD-250 | 4878d3c | `sd250ReportRoutedToMeetingTest`, `sd250NotRoutedElsewhereTest` |
| SD-254 | fa81646 | `sd254RelayBlockTest` |
| SD-442 | 581888d (in part) | `sd442SlotTest`. The model uses days; `slotOf` still reads UTC hours, which the model does not cover. |
| SD-475 | 49602b7 | `sd475HoldNoticeKindTest` |

#### 3.1 SD-044: a second path, fixed in this commit

After the f8d9de8 fix the model found a second path to the same defect. `onFeedback` wrote the check-in
record with `participants: [...o.participants]`. A plan keeps a member who said no in `participants`, and
`metBefore` and `counterparts` read the record. So after the plan met and one member answered the
check-in, the decliner counted as someone who met them, and the decliner's urgent report held that member.
Trace: `bookPlan(o1, slop, ana, ben, cy, declined)`, `meet(o1)`, `checkIn(o1, ana@slop, fine)`,
`report(cy, slop, ana, report, harassment)` -> `met = true`.

Fix: the record names the people the booked plan reached (`o.bookedTold ?? o.participants`,
`packages/network/src/network.ts` onFeedback). Test: `packages/network/test/report-plan-decliner.test.ts`
"SD-044: after the plan, a check-in answer does not make the decliner someone who met them". It failed
before the fix (`met` was `true`) and passes after it. The test files of the check-in record
(`check-in-history`, `check-in-report-trust`, `check-in-late-report`, `peon-check-in-report`) also pass.

### Not reproduced

None.

### Skipped (3)

- **SD-027** (founder decision). The slop `trust_review` rule holds a member after 2 blocks or 2 no-shows
  with no case and no staff exit. A fix adds a new staff action and member copy, or removes an engine
  safety filter. `engineHoldVisible` and `staffDecisionEndsEngineHold` stay out of `safety`.
- **SD-074** (founder decision). An automatic hold, a minor report or an urgent report on one app does not
  hold the person on the other apps. It is not clear which staff decision ends such a hold in the other
  apps, and one verifier vote says per-app reach is by design. `autoHoldFollowsPerson`,
  `minorSignalFollowsPerson` and `urgentMetReportBlocksMatching` stay out of `safety`. Their `InApp` forms
  (SD-021) are in `safety` and pass.
- **SD-253** (founder decision). No notice of a ban goes to past contacts. It is new member copy.
  `pastContactsToldOfBan` stays out of `safety`.

### 3.4 Notes on the fixed rows

- SD-021: a minor report carries over as a plain person hold (`held_by = 'safety_carryover'`). A staff lift
  of the rejoined member ends it, and the minor flag does not come back. The case history is not carried
  over (the commit names this as the separate evidence or erasure defect), so staff lift without seeing
  that the hold came from a minor report. The model accepts the lift as the staff decision.
- SD-022: the other apps' members are held at their next unit or tick, not in the same transaction. The
  model treats a covered member as out of matching at once, because matching runs in the tick after
  `personHold`.
- SD-220: the code takes the member's newest done 1:1 date in the window. The model lets a member disclose
  only when one such date is in the window. A disclosure about an older date, with a newer date in the
  window, is not modelled.

## 4. New findings

These findings are reported, not fixed: they are not in the task list, and each needs a decision on the
wanted behaviour.

- **NEW-2: a held reporter's standing resets.** The SD-072 fix reads the reporter's trust level. Two paths
  reset it. (a) A reporter on hold leaves the app: `forget` blanks `reporterId`, `trust.level("")` is "ok",
  and the report holds its subject again (`new2HeldReporterLeavesTest`: `bookDate`, `staffHold(ben)`,
  `report(ben -> ana)`, `leave(slop, ben)` -> ana is out of matching). (b) Staff lift a banned member's hold
  (`liftHold` does not check the ban): the banned member's report holds its subject (the simulator found
  `ban(ana)`, `liftHold(ana@slop)`, `report(ana -> cy)`). The value `reporterStandingKept` keeps this rule.
  A fix needs the report to keep the reporter's standing when it is filed or at the leave, or `liftHold` to
  refuse a banned member. Not fixed here: it is a new defect, not in the task list.
- **NEW-3: a block inside a plan calls it off for everyone.** When two members who are both going to a
  plan of three block each other, `callOffPair` closes the plan, and the third member loses it
  (`new3BlockInPlanTest`). PRD F23 says a block "only affects the pair", and `bookPlan` drops one member of
  a blocked pair so that "one block cannot collapse the quorum". SD-045 covers only a blocker who is not
  going. The value `blockLeavesOthersPlan` keeps the strict rule. It needs a decision on what a block in a
  booked plan does (drop one member, or call it off).

The liveness item of the plan ("every hold reaches a staff decision") is not checked: the simulator and
Apalache check state invariants only.

## 5. Wave 4

Plan: [docs/research/2026-11-07-state-machines.md](../2026-11-07-state-machines.md) section 9.6 (`safety_trust`, P0,
19 items). The model now follows the code at e4f0a32. File and line references below are at e4f0a32. This
section is hand-written; the traces are the model's `run` tests (`quint test`, seed `0x5eed`).

### 5.1 What changed in the model

| Item | Kind | What the model does now |
|---|---|---|
| W3-218 | defect (confirmed) | `disclose(k, app, p, meant, kind, pronoun)` takes the member's NEWEST done 1:1 date in the 7-day window (network.ts:2859-2862) and files against its other person. Ghost `meant` is the person the member talks about. New rule `reportSubjectMeant` (in `safety`): fails. Trace `w3_218LateDisclosureNewestDateTest`. |
| W3-219 | defect (confirmed) | The gate is `pronoun or names the partner` (ABOUT_SOMEONE, network.ts:346, 2867); the reader of the later text is free. `meant = "boss"` (not a member) still files. `checkInReportIntended` fails. Trace `w3_219VentingTest`. |
| W3-220 | defect (confirmed) | The routed app of a disclosure and of the answer to "Who do you mean?" is an oracle over the member's apps (service.ts:1085-1135: only block/report texts use safetyTargetAt). New actions: the `discloseLost` branch of `disclose`, and `answerWhoElsewhere`. `everyMetReportFiled` fails. Traces `w3_220DisclosureRoutedElsewhereTest`, `w3_220WhoAnswerRoutedElsewhereTest`. |
| W3-221 | defect (confirmed) | `leave` is two steps: `leaveStart` (readState(safetyHeld) and the carry-over row) and `leaveFinish` (forgetMember), service.ts:921-930. `urgentMetReportBlocksMatchingInApp` fails. Trace `w3_221LeaveRaceTest`. The atomic `leave` stays for the old run tests only. |
| W3-223 | defect (confirmed) | `ban` is `banStart` (ban rows) and one `banApply` unit per app, with `crash` between them and a retry when a member is not restricted (service.ts:2014-2046). New rule `bannedNeverMatchable` (in `safety`): fails. Trace `w3_223BanStoppedTest`. |
| W3-224 | model error | The late path has a free reader and a free "meant" person, and no `inWindow == Set(k)` guard, so `checkInReportIntended` can fail (it does, `w3_219VentingTest`). The direct check-in answer keeps the reader assumption as the named `checkInReaderSound` (the corpus gate checks it, SD-067). |
| W3-225 | model error | Slot: the record has the New York hour and the slot that slotOf reads in UTC (`slotUTC`); `slotFromMeeting` compares it with `slotNY` and fails for 8 pm and 2 pm (`w3_237SlotZoneTest`). Notice kind: `holdNoticeKind` calls `outboundKind` (decisions.ts:109). Mutation: without the `safetyMeta` branch, `sd475HoldNoticeKindTest` fails (`safetyNoticeImmediate` is false). No-show: the record's `by` comes from `recordOf`; a mutation that names the other person was run (5.3). |
| W3-226 | model error | `staffHeldP` is a set of (person, "*" or app). A lift removes (p, app); a lift by safety@* staff turns (p, "*") into the other apps; a lift by staff of one app never removes (p, "*"). `staffHoldFollowsPerson` checks each scope. |
| W3-228 | model error | Already in the model: the lift ends the case as "lifted" (`liftUnitOf`). No change. |
| W3-229 | gap | `invitedBy` (cy@slop was invited by ana@slop) and `invitesBlockedUntil`. `addPts` adds `invitee_held` (+1, 30 days without invites) to the inviter when the invitee reaches hold (network.ts:1266-1272). `noSingleActorHold` still passes across the chain (`w3_229InviterTest`). The model has one link; production never writes `invited_by` (runtime.ts:588). |
| W3-230 | gap | `Trust.blocksMade` and the 14-day window of trust.ts:99-106; +2 fires each time the window holds exactly 3; credibility comes back after 14 days (`credibleT(t, now)`). `w3_230BlockWindowTest`. |
| W3-231 | gap | `staffHoldBy(m, scope, onlyRep)`: per-app staff write (p, app) and hold one app; a hold with a report id marks only that report (network.ts:1421-1427). After a lift the other open urgent report still holds the member (`w3_231ReportIdHoldTest`): over-holding, not a safety defect. `liftHold` is three steps (5.2). A `not_on_hold` lift still deletes the rows: the staff wanted the lift, so the model treats the transaction as the staff decision. |
| W3-232 | gap | Crash points: `crash` now stops a ban loop, a clear-minor loop (`clearMinorStart`/`clearMinorApply`, service.ts:1977-2003), a leave and a lift. A probing stage: `bookDateAt(..., probe = true)` and `confirm`; `dropOpps` and `callOffPair` close probing items (network.ts:482, 1532-1545, 2756-2778); `blockClosesAllApps` covers probing items (`w3_232ProbingBlockTest`). Relay `ageSignal`: `relaySend(..., ageSig)` keeps the ghost `ageSignals`; nothing reads the flag. New rule `relayAgeSignalReachesAgePolicy` (in `safety`): fails (`w3_232RelayAgeSignalTest`). Relay holds write no case: they go to the staff relay queue, so the model keeps no rule for them. |
| W3-234 | carve-out (NEW-2) | Re-checked: network.ts:999 still blanks `reporterId` on forget, and service.ts:1797 `liftHold` still does not read the ban. In scope (security). `reporterStandingKept` moved into `safety`: fails (`new2HeldReporterLeavesTest`, `w3_234BannedReporterLiftedTest`). |
| W3-235 | carve-out (SD-027) | The visibility part and the stranger-block part are in scope. `engineHoldVisible` moved into `safety`, and the new `strangersCannotEngineHold` (trust_review by blocks needs two blockers who met the member; profile.ts:277 counts every block) is in `safety`. Both fail (`sd027TrustReviewTest`). `staffDecisionEndsEngineHold` stays out (the staff exit needs the founder). |
| W3-236 | carve-out (SD-074) | The minor part is founder decision 1 (age is person-level, minors never matched in any app). `minorSignalFollowsPerson` moved into `safety`: fails (`sd074MinorReportOneAppTest`). `autoHoldFollowsPerson` and `urgentMetReportBlocksMatching` stay out (founder decision). |
| W3-237 | carve-out | SD-442 remainder: modelled (W3-225), `slotFromMeeting` fails. SD-254 remainder: the relay ageSignal part is modelled (W3-232). SD-253 (`pastContactsToldOfBan`, new member copy) and NEW-3 (`blockLeavesOthersPlan`, which member leaves a booked plan) still need the founder and stay out of `safety`. |
| W3-435 | gap | The lift writes one row per other live app before it deletes "*" (`liftTxOf`). A held person's member on another app reads a covering row until staff of that app lift it (`w3_435LiftKeepsOtherAppsTest`, `staffHoldFollowsPerson`). |
| W3-644 | defect (confirmed) | `liftStart` reads the "*" row and checks the role, `liftTx` deletes (p, app) and (p, "*") and writes the per-app rows only from the old read, `liftUnit` lifts. `staffHoldFollowsPerson` fails. Trace `w3_644LiftRaceTest`. |

### 5.2 Counterexamples (code defects)

Each trace is a `run` test in the model. Members: ana, ben, cy; `@slop`, `@peon`; `g1` is a rejoin.

1. **W3-218** (network.ts:2859-2871). `bookDate(o1, slop, ana, cy)`, `meet(o1)`, `checkIn(o1, ana, fine)`, `tick(1)`,
   `bookDate(o2, slop, ana, ben)`, `meet(o2)`, `checkIn(o2, ana, fine)`, `disclose(o2, slop, ana, meant = cy,
   harassment, pronoun)` -> a check-in report ana -> ben, a person block (ana, ben), ben out of matching; cy
   matchable. `reportSubjectMeant` and `everyMetReportFiled` are false.
2. **W3-219** (network.ts:346, 2867). A done date ana-ben, `checkIn(fine)`, `tick(1)`, `disclose(o1, slop, ana,
   meant = boss, harassment, pronoun)` -> report ana -> ben (harassment, met), block, ben held.
   `checkInReportIntended` is false.
3. **W3-644** (service.ts:1800-1812). `staffHoldBy(ana@slop, slop)`, `liftStart(ana@slop, slop)` (no "*" row),
   `staffHoldBy(ana@peon, *)`, `staffHoldApply(ana@slop)`, `liftTx` (deletes (ana, *) with no per-app rows),
   `liftUnit` -> ana@slop is ok and matchable, no person_holds row for ana. `staffHoldFollowsPerson` is false.
4. **W3-221** (service.ts:921-930). `bookDate(o1, slop, ana, ben)`, `leaveStart(slop, ben)` (safetyHeld = false),
   `report(ana -> ben, harassment)`, `leaveFinish(ben@slop)`, `join(slop, ben)` -> ben@slop g1 matchable, not
   covered. `urgentMetReportBlocksMatchingInApp` is false.
5. **W3-223** (service.ts:2014-2046). `banStart(ben)`, `banApply(ben@slop)`, `crash` -> ben@peon live, ok, not
   restricted, not covered: matchable. `bannedNeverMatchable` is false until the staff retry.
6. **W3-234 / NEW-2** (network.ts:999, network.ts:1365-1367, service.ts:1797). (a) `new2HeldReporterLeavesTest`;
   (b) `bookDate(o1, slop, ana, ben)`, `ban(ana)`, `liftHold(ana@slop)`, `report(ana -> ben, harassment)` -> ben
   out of matching. `reporterStandingKept` is false.
7. **W3-220** (service.ts:1113-1131). (A) a done date ana-ben on slop, `checkIn(fine)`, `tick(1)`,
   `disclose(o1, peon, ana, ben, harassment)` -> `discloseLost`, nothing filed. (B) `report(ana, slop, ben,
   report, ambiguous)`, `answerWhoElsewhere(ana@slop, peon)`, `tick(6)` -> the ask lapsed, nothing filed.
   `everyMetReportFiled` is false.
8. **W3-236 / SD-074 minor part** (network.ts:1656-1666, service.ts:1977). `sd074MinorReportOneAppTest`: ben@peon
   matchable after a minor report on slop. `minorSignalFollowsPerson` is false.
9. **W3-235 / SD-027** (engine slop profile.ts:277, rules.ts:46). `sd027TrustReviewTest`: two strangers block
   ben; ben is in trust_review with no case. `engineHoldVisible` and `strangersCannotEngineHold` are false.
10. **W3-237 / SD-442 remainder** (engine slop profile.ts:224-230). `bookDateAt(o1, slop, ana, ben, 20)`,
    `meet`, `checkIn(fine)` -> the record's slot is -1 (00:00 UTC Tuesday) for a Monday 8 pm date.
    `slotFromMeeting` is false.
11. **W3-232 / W3-237 relay ageSignal** (engine relay.ts:355; network.ts relay desk and the service read no
    `ageSignal`). `bookDate(o1, slop, ana, ben)`, `relaySend(o1, ben@slop, hold, ageSig)` -> ben matchable.
    `relayAgeSignalReachesAgePolicy` is false.

No new defect ids (Q-safety_trust-W4-n): every counterexample above is an existing item.

### 5.3 Mutations (vacuity checks)

Each mutation was made in a copy of the model outside the repository, then deleted.

| Rule | Mutation | Result |
|---|---|---|
| `safetyNoticeImmediate` | `outboundKind` without the `safetyMeta` branch | `sd475HoldNoticeKindTest` fails (the notice is "transactional") |
| `noShowCountsAbsentOnly` | `recordOf` writes the other person as `by` | `sd222SelfNoShowTest` fails (ana is charged the no-show) |
| `checkInReportIntended` | none needed | fails on the unchanged model (`w3_219VentingTest`) |
| `slotFromMeeting` | none needed | fails on the unchanged model (`w3_237SlotZoneTest`) |

### 5.4 Check results

See the table below (filled from `bun run quint:check quint/safety_trust.qnt`).

| Check | Result |
|---|---|
| `quint typecheck` | ok |
| `quint test` (29 earlier and 17 new `run` tests, seed `0x5eed`) | ok: 46 passing |
| `safety` simulation | expected to fail: the rules of 5.2 fail on the code (counterexamples 1-11) |
| witnesses (11 earlier, 6 new) | the `bun run quint:check` run had not finished when this was written; the new witnesses (banStopped, liftInFlight, leaveInFlight, probingClosed, oneAppHold, inviteeHeld) are each reached by a `run` test |

`quint/drift.json` was not stamped (a later stage stamps after the merge). No `docs/formal-coverage.md` row was added:
this is an extension of an existing model, not a new model.
