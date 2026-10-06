# CM Economy Job Timing Protocol

Purpose: replace the MEASURE assumptions in `CM_ECONOMY_AUDIT.md` with measured gross/net hourly income per job.
Status: **prepared, not executed.** No timed run has been performed (Electrician, Fishing, Farming, Taxi, cm-payday carry uncommitted edits by Agent 1).

## 0. Pre-flight (mandatory before every run; never time stale logic)

1. `git status` — the job resource and `cm-payday` must have no uncommitted changes from another agent (or Agent 1 confirms it is finished).
2. Read the resource's current reward config/code (not this document's numbers) and record: reward constants, cooldowns, level thresholds, payout path.
3. Restart only that resource (`tools/cm-runtime`), read the fresh console, confirm no errors.
4. Dev server only (`developmentOnly=true`). Use a dedicated test character; record Character ID (never source ID) in the log.
5. Snapshot start state: cash, bank, pending payday cash/XP (read through cm-payday's safe server contract), job level/XP, inventory.
6. Log which build was timed: `git rev-parse HEAD` plus a hash of the job's config file.

## 1. Common measurements (all jobs)

Record per session in a CSV (one row per action) plus a summary row:

| Field | Notes |
|---|---|
| session_start/end, wall minutes | Excludes AFK/pauses; pause the clock for any out-of-band stop |
| setup_min | Start job, uniform/vehicle/rental, buying tools, travel to first task |
| active_min | Hands-on task time (holds, casts, planting, driving with fare) |
| travel_min | Moving between tasks without doing a task |
| wait_min | Cooldowns, bite waits, grow timers, fare waits |
| successes / failures | Failures by type (shock, failed skill check, escaped fish, failed fare) |
| consumables, rental, fuel cost | Real debits observed in `economy_transactions` |
| gross_reward | Cash credited **or** pending in cm-payday (include held cash), plus sale proceeds |
| net_reward | gross − consumables − rental − fuel − fees |
| xp, level changes | Note level-up mid-session and split the sample there |

Derived: `gross/h = gross × 60 / session_min`, `cost/h`, `net/h = gross/h − cost/h`, `completions/h`, `avg seconds/completion`.
Compare `net/h` to the band in `CM_ECONOMY_STANDARD.md` §2 (entry 50–62.5k, established 62.5–87.5k, skilled 87.5–112.5k activity income per hour) and report the
multiplier needed to reach target: `target_mid / measured_net_h`.

Use real player pacing: no scripted teleporting, no skipped timers. cm-qa may be used for state snapshots only, not to accelerate the job.

## 2. Electrician

| Tier | State | Session |
|---|---|---|
| Entry | Level 1, on shift, walking/no vehicle (rental unlocks at Level 2) | 45 min |
| Mid | Level 2 with rented utility truck | 45 min |
| High | Level 3 (plates + outages unlocked) with truck | 60 min |

Measure per task type: panel, plate, outage. Capture seconds from assignment → completion (travel vs 3s/3s/15s holds), shock count, retries, outage frequency
(configured wait 2–5 min), truck rental cost, and reward per type. Pending cash is held by cm-payday: read `pending cash` before and after, do not wait for the hourly tick.
If a level threshold (50 panels, 500 plates) would not be reached in the session, test the upper tier by creating the state through the owner's QA/admin contract
that Agent 1 is building — not by editing metadata directly. Run entry ×2 sessions (different panel clusters) to estimate map variance.

## 3. Fishing

| Tier | State | Session |
|---|---|---|
| Entry | Level 0, Basic Rod, Worms, shallow water | 2 × 45 min |
| Mid | Level 2–3, Rod 2/3, Common Bait, medium water | 2 × 45 min |
| High | Level 5, Rod 3, Artificial Bait, deep water / boat rental | 3 × 60 min (RNG-heavy) |

Count casts, bites, catches by rarity, skill-check failures, heavy-fish / shark events, rod breaks, bait used (incl. saveChance), boat rental cost and time, and
sale proceeds at the NPC. Report catches/hour **and** EV per catch by rarity; flag Legend/Mythic sample sizes (expect < 5 per run — pool all runs and
also compute theoretical EV from the weight table so one lucky Legend does not set the price). Time the selling trip (walk or vehicle) once and amortise.

## 4. Farming

| Tier | State | Session |
|---|---|---|
| Entry | Level 0, Wheat/Pumpkin, watering can bought | 45 min |
| Mid | Level 1, Rose/Green Bean/Daisy/Poppy | 45 min |
| High | Level 2+, Melon/Watermelon, max simultaneous plots | 60 min |

Measure seconds per plot for plant / water / harvest, growth time (config `growTimeSec`), plots simultaneously managed, harvest quantity, seed and tool cost,
sale price/NPC trip time, and idle time between harvests. Run **one active** session (continuously planting) and **one passive** session (plant, leave,
return) to quantify passive vs active income; passive income must not exceed the active-skilled job band. Include dairy (feed/milk) as a separate small sample.

## 5. Taxi

| Tier | State | Session |
|---|---|---|
| Entry | Level 1, rented Classic Taxi | 60 min |
| High | Level 3, Huracan rental | 60 min |

Measure fares/hour, distance and time per fare, empty-driving time between fares, wait for new fares (`NewFareIntervalMs` 60s), tips awarded (clean/prompt rides),
vehicle rental and fuel cost (use a fixed-length run to measure real fuel consumption, then multiply), payout path (pending cash). Do not time against
`resources/outside/OT_taxi` (legacy, backdoored; not authoritative).

## 6. Output

For each job/tier, append to `CM_ECONOMY_AUDIT.md`: sessions, build hash, gross/h, cost/h, net/h, completions/h, band, required multiplier, confidence
(sample size, variance). Only then propose final reward values via `reward = target_hourly / completions_per_hour` (Standard §5).

## 7. Resources intentionally NOT timed in this phase

cm-electrician, cm-fishing, cm-farming, cm-taxi (Agent 1 active), cm-payday (Agent 1 active; also required for pending-cash reads).
