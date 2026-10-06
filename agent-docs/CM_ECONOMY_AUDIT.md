# CM Economy Audit (Phase 1–2)

Date: 2026-10-02. Read-only discovery; **no gameplay values changed yet**. Conventions: MEASURE = needs a live timing run;
HOLD = owner resource has uncommitted work by another agent (electrician, fishing, farming, taxi, payday, license, house were
dirty in `git status`), so proposals are documented, not applied. Confidence: H/M/L.

## A. Findings

- **City Support does not exist.** `cm-payday` (`shared/config.lua`, `server/main.lua`) banks job pay hourly and tracks playtime
  (`cmPaydayPlaytimeSeconds`) but pays no base income. Recommended home: extend cm-payday's hourly tick, paying 37,500 per eligible hour
  (150k / 4h) from the existing per-character playtime; one connected character per account at a time already limits multi-character farming.
  HOLD (cm-payday dirty).
- **Mixed scale already.** Weapons (2.5k–28k), tuning (12k/level), fuel (8/% = 800 tank), vehicle class defaults (18k–350k), licences (0.5k–5k)
  are at a plausible scale. Jobs, fish, crops, bait, food and EMS/doctor items are at the old tiny scale (3 to 180 per unit).
  Multiplying globally would be wrong: gun/fuel/tuning would become absurd.
- **Clean-ownership note:** vehicle, clothing and house prices are DB rows; the repo cannot show actual values. Needs a DB query before rebalancing.

## B. Dangerous loops / conflicts

| ID | Finding | Evidence | Action |
|---|---|---|---|
| L1 | Fishing rods and bait priced in **two places** (cm-store `shared/config.lua` and cm-fishing `shared/config.lua`), same values today | rods 50/100/150, bait 5/10/15 | Keep identical when rebalancing; ideally one reads the other. HOLD |
| L2 | Store restock is a flat 6/unit (8 overstock) regardless of item value; cigarettes 450, lottery 10,000, map 1,450 | cm-store Ownership | Owner can fill stock at 6 and sell 10k items at 80% share => very high margin; fix before any business-price change. MEASURE which items drive revenue |
| L3 | Gas station restock 4/unit vs fuel 8/% (and 11 high tier) | cm-gasstations Ownership | Margin ~2x; acceptable, re-check after fuel rescale |
| L4 | Fish sells at fixed `RaritySellPrice`; rods break only on heavy catches | cm-fishing | No buy/sell loop found; value must follow job band |
| L5 | Taxi rental of Huracan (5,000) vs fare ~100–300 | cm-taxi config | Rental > hours of fare income today; after fare rescale re-check |

## C. Job hourly model (assumptions; MEASURE all)

| Job | Current est. $/h | Assumption | Target | Proposed change (HOLD, not applied) |
|---|---|---|---|---|
| Electrician L1 | ~1.3k (30/panel x ~45/h) | 3s hold + ~80s travel/panel, 8% shock retry | 50–60k | perPanel 30 -> **1,200** |
| Electrician L3 | ~2-4k | panels ~20/h, plates ~20/h, ~3 outages/h | 95–110k | perPlate 300 -> **1,900**, perOutageFix 1,000 -> **15,000**, RentVehicle cost 500 -> **6,000** |
| Fishing L0 | ~1.6k (commons 15) | ~90 casts/h (3–9s bite, skillcheck, cooldown) | 50k | Common 15 -> **450** (x30) |
| Fishing L5 | ~8-12k | Legend weights 1–5 (rare) | 100–120k | Rare 35 -> 1,050, Epic 60 -> 1,800, Mythic 100 -> 3,000, Legend 180 -> 5,400; bait worms 5->25... see rows. MEASURE catch rate before applying |
| Farming L0 | ~1.5k | ~100 plots/h action-limited, wheat 3x14 | 50k | crop sell x12, seed x12 (wheat 6/14 -> 70/170); milk 50–100 -> 600–1,200 |
| Taxi L1 | ~3-4k | ~11 fares/h, ~2.5km each (8 m/s) | 55k | FareMin/Max 10/15 -> **160/240**, FuelBonus 5 -> **60**, ServiceTipMax 25 -> **450** |
| Taxi L3 | same x skill | Huracan | 90-100k | rent 1,000/5,000 -> **8,000/25,000**, L3 bonus 3,000 -> **30,000** |

Payout paths: taxi/fishing/electrician/farming all bank via cm-payday (`Jobs` table), delayed until the hourly payday.

## D. Audit table

| Resource | System | Item/Action | Current | Proposed | Src/Sink | Time value | Reason | Conf | MEASURE |
|---|---|---|---|---|---|---|---|---|---|
| cm-payday | City Support | base income | none | 37,500 / eligible h | Source | 1 h | baseline | H | NO |
| cm-electrician | Earnings | perPanel | 30 | 1,200 | Source | ~80s | band | M | YES |
| cm-electrician | Earnings | perPlate | 300 | 1,900 | Source | ~90s | band | M | YES |
| cm-electrician | Earnings | perOutageFix | 1,000 | 15,000 | Source | ~15 min incl. wait | band | L | YES |
| cm-electrician | Rental | utility truck | 500 | 6,000 | Sink | ~6 min | operating cost | M | NO |
| cm-fishing | Sales | Common..Legend | 15/35/60/100/180 | 450/1,050/1,800/3,000/5,400 | Source | per catch | band | L | YES |
| cm-fishing / cm-store | Rods | basic/2/3 | 50/100/150 | 2.5k/25k/75k | Sink | 0.03–0.9 h | rod_2/3 raise earn rate | M | NO |
| cm-fishing / cm-store | Bait | worms/common/artificial | 5/10/15 | 25/60/120 | Sink | ~5–8% of catch value | consumable | M | NO |
| cm-fishing | Boat rental | seashark/dinghy/suntrap | 500/1,000/1,500 | 6k/12k/18k | Sink | per rental | depends on duration | L | YES |
| cm-farming | Crops | wheat seed/sell | 6/14 | 70/170 | Both | 4 min grow | x12 | M | YES |
| cm-farming | Crops | pumpkin/melon/watermelon sell | 24/26/28 | 290/310/340 | Source | 7 min grow | x12, per-time parity | M | YES |
| cm-farming | Tools | watering can / tablet | 35 / 120 | 1,500 / 4,000 | Sink | 0.02–0.05 h | entry tools | M | NO |
| cm-taxi | Fare | FareMin/Max | 10/15 | 160/240 | Source | ~5 min/fare | band | M | YES |
| cm-taxi | Rental | taxi / Huracan | 1,000 / 5,000 | 8,000 / 25,000 | Sink | | operating cost | M | NO |
| cm-store | Ownership | purchasePrice | 200,000 | 5,000,000 (small business) | Sink | ~60 active h | break-even, after L2 fix | L | YES |
| cm-store | Ownership | taxAmount (7d) | 12,000 | 100,000 | Sink | | ~10% of weekly profit | L | YES |
| cm-store | Ownership | restockUnitPrice | 6 / 8 | scale with item price | Sink | | loop L2 | M | NO |
| cm-gasstations | Ownership | purchasePrice / tax | 250,000 / 15,000 | 8,000,000 / 150,000 | Sink | ~90 h | larger volume | L | YES |
| cm-store | Survival | water / sandwich | 15 / 25 | 120 / 250 | Sink | survival | keep << 15% CS | M | NO |
| cm-store | Tools | crowbar / pickaxe 1/2 | 1.5k / 2.5k / 10k | 15k / 25k / 100k | Sink | | tools unlock earning | L | NO |
| cm-gasstations | Fuel | per % / full tank | 8 / 800 | keep | Sink | ~2%/h | survival OK | H | NO |
| cm-gasstations | Kits | fuel can / repair / wash | 350 / 1,200 / 250 | keep | Sink | | OK | M | NO |
| cm-carwash | Wash | price | 150 | 400 | Sink | | survival | M | NO |
| cm-tuning | Parts | engine/level etc. | 12k/level... | keep (4 levels = 48k engine) | Sink | 0.5 h | fits ladder; recheck vs vehicle prices | M | NO |
| cm-gunstore | Weapons | pistol / SMG / rifle | 2.5k–3.5k / 12k / 28k | keep | Sink | | do not cheapen; revisit upward once incomes scale | M | NO |
| cm-gunstore | Ammo | 9mm .. 308 | 30–160 | keep | Sink | | scale later with rifle prices | L | NO |
| cm-license | Licences | driver/boat/air | 500/1,000/5,000 | 2,500/6,000/25,000 | Sink | | progression, HOLD (license dirty) | M | NO |
| cm-law | Fines | speeding..resisting | 100–750 | x6 (600–4,500) | Sink | | must matter; HOLD review | L | NO |
| cm-ems / cm-doctor | Treatment | bandage..medikit; fees 150/250 | 25–350 | x8 | Sink | | survival ceiling | L | NO |
| rn-vehicleshop | Class defaults | cat 0 / 6 / 7 | 18k / 125k / 350k | see Standard §4 ladder | Sink | | DB rows decide real values | L | YES (query DB) |
| nv_cloth | Catalog | per item | DB rows | bands Standard §4 | Sink | | metadata.price is authoritative | L | YES (query DB) |
| cm-house | Property | pool feature 150,000 etc. | DB rows | ladder §4 | Sink | | query DB | L | YES |
| cm-family | Upgrade | cost 150,000 | | review | Sink | | not audited | L | YES |

## E. Not applied and why (updated 2026-10-02)

1. electrician/fishing/farming/taxi/payday/license/house have uncommitted work by another agent: no gameplay values are changed in this phase.
2. Business prices need measured customer volume (dev DB has zero owned businesses) and loop L2 must be fixed first.
3. Vehicle/clothing/house prices are now known (section G, `CM_ECONOMY_DATABASE_EXPORT.md`); this phase is evidence only, no rebalance authorised.
4. Job timing is prepared in `CM_ECONOMY_TIMING_PROTOCOL.md` and not executed.

## F. Suggested order of work (updated)

1. ~~Read-only DB export~~ done (`tools/cm-economy-export/export.py`).
2. Agent 1 stabilises job resources, then run the timing protocol.
3. Fix the store restock/stock model (section H), data-fix the zero/near-zero published vehicles, then reprice catalogs via the admin tools.
4. Implement City Support after cm-payday stabilises (section J); add cm-qa economy invariants.

## G. Database-backed values (verified 2026-10-02, local dev DB `grandrp`, read-only)

Full tables: `CM_ECONOMY_DATABASE_EXPORT.md`; machine-readable: `agent-docs/economy-export/*.csv`. Time = gross, rough model (price / 37.5k support-h, / 87.5k beginner active-h).

| Resource | System | Item/Action | Current Value | Proposed Value/Band | Source/Sink | Time Value | Confidence | Live Measurement Required |
|---|---|---|---|---|---|---|---|---|
| rn-vehicleshop | `cm_vehicle_catalog` (1,555 rows) | purchasable set | 19 rows (`available_store/server`); 9 fleet; 1,527 hidden | publish only after pricing | Sink | - | H | NO |
| rn-vehicleshop | published prices | min / median / avg / max | 0 / 70,000 / 94,511 / 300,000 | starter 200k–300k, commuter 450k–600k, sedan/SUV 0.9–1.2M, performance 2.0–2.5M, sports 4–5M, super 8–10M | Sink | 0.7–8 support-h today | M | NO |
| rn-vehicleshop | free vehicles (price 0, store+server): Jester (Sports), Hycignus (Super), Draftvmark (Emergency), Police Maverick, Frogger, Havok | 0 | unpublish or price; Super >= 8M, aircraft per air tier | Sink (missing) | free | H | NO |
| rn-vehicleshop | near-free: Albany V-STR (Sedan) / Sandking XL (Off Road) | 200 / 1,500 | 450k–600k / 1.0M–1.3M | Sink | <0.04 h | H | NO |
| rn-vehicleshop | ordering | Sports 202k–300k above SUV 130–150k, Coupe 70–160k, Muscle 70k | ordering acceptable; absolute level is far below Standard §4 | - | - | M | NO |
| rn-vehicleshop | hidden class defaults | Compacts 18k … Sports 110–200k, Super 350k | scale to the ladder before publishing (x~8–12) | Sink | - | M | NO |
| cm-vehicles | resale to state | 30% of catalog price (100% if model permanently removed) | keep; 70% loss is a healthy sink | Source/Sink | - | H | NO |
| nv_cloth | `clothing_catalog` (140 rows; 87 published, 14 org-restricted; 116 female / 24 male) | price | 10–50 per piece (flat per category), armor 3,500; median 20 | Basic 600–1,500, Standard 2,500–4,500, Premium 15k–60k, Luxury 100k–500k, armor 25k–60k | Sink | median = 0.03 support-min | H | NO |
| nv_cloth | price authority | `clothing_catalog.price`, else `Config.Prices[category]` | correct | keep DB row authoritative | - | - | H | NO |
| nv_cloth | `Config.Economy` (hourlyEarn 12,500; storePrices 200–3,000; addonPrices 6k–45k) | no consumers outside config | stale anchor (3x below 37.5k/h) | update or delete | - | - | H | NO |
| cm-house | `cm_houses` (3 rows, all owned, none for sale) | price | 0.83M villa / 1.23M villa+heli / 2.4M mansion | normal 6–8M, luxury 20M+ | Sink | 22–64 support-h; 9.5–27 active-h | H | NO |
| cm-house | `cm_house_pricing` add-ons | trailer 40k, apartment 120k, house 250k, villa 600k, mansion 1.2M; garden 80k, pool 150k, helipad 400k | multiply x~5–8 | Sink | - | M | NO |
| cm-house | derived fees | gov_value 80%, insurance 3%, daily cost 0.1% of price (code, `sv_admin.lua`) | keep ratios; daily cost on 7M = 7,000 | Sink | - | M | YES |
| cm-store | ownership | 200,000; tax 12,000 / 7d | see §H | Sink | 5.3 support-h to buy | L | YES |
| cm-gasstations | ownership | 250,000; tax 15,000 / 7d | 6.7 support-h to buy | Sink | | L | YES |
| nv_cloth / cm-characters / cm-parking-v2 / cm-bank | ownership | clothing store 250k, barber 200k, parking 250k, ATM 15k (80% owner share) | review after §H | Sink | all < 7 support-h; ATM 0.4 h | Sink | | L | YES |
| cm-gunstore | `cm_gun_catalog` weapon (n=58) | median 15,000; max 70,000 (minigun 250,000) | keep, review after incomes rise | Sink | | M | NO |
| cm-gunstore | ammo / armor | 30–160 / 1,000–3,500 | keep; armor 1,000 outlier | Sink | | M | NO |
| cm-license | `cm_license_types` | driver 500 / boat 1,000 / air 5,000 | 2.5k / 6k / 25k | Sink | | M | NO |

Findings of note:
- Only 19 vehicles are purchasable today; there is no full catalog to price yet, so vehicle pricing is a curation task, not only a number change.
- Six published vehicles are free, and `rn-vehicleshop/server/server.lua` (~line 1679) only rejects `price < 0`, so price 0 is purchasable.
- Clothing is effectively free: a median piece is ~0.03 support-minutes; even armor (3,500) is 5.6 support-minutes.
- Houses are 22–64 support-hours (~9–27 active-hours): below the Standard ladder (normal 80 h, luxury 250 h) but the closest category to target.
- All businesses cost 5–7 support-hours; none are owned in dev, so there is no revenue data.
- Dev `economy_transactions` (1,002 rows, 2 characters) is dominated by admin grants (5.6M); non-representative.

## H. cm-store restock analysis (no change applied)

Logic (`cm-store/server/main.lua`):
- Purchase (`processCheckout`): server resolves `entry.price * tier multiplier` (low 0.85, normal 1.0, high 1.25, `math.ceil`), requires `stock >= total units`, charges, delivers, then
  `UPDATE cm_stores SET stock = GREATEST(0, stock - deliveredUnits), business_balance += floor(actualPaid * 80%)`. **Every item consumes exactly 1 stock unit regardless of price.**
- Owner restock: `stock += 500` for `500 * 6 = 3,000` bank (overstock 8/unit up to 8,000). City cut = 20% of sales (a sink); owner pays tax 12,000/7d.
- `cm-commercial-ownership` implements the same pattern generically (stock/tax/forfeiture), but cm-store keeps its own copy; nv_cloth and cm-characters (barber) use the shared engine with different flat unit prices.

Imbalance (normal tier): profit per stock unit = 0.8 x retail − 6. Water +6, sandwich +14, cigarettes +354, crowbar +1,194, lottery ticket / Level 2 pickaxe +7,994.
Worms and common bait are loss/near-zero. 3,000 buys 500 units that could all be lottery tickets worth 4.0M gross to the owner's 80%. A 12,000 weekly tax is covered by 2 lottery tickets and the 200,000 purchase by ~25, so break-even cannot be tuned with a flat per-unit cost.

Other observations:
- Self-purchase: an owner buying from their own store pays 100% and receives 80% (net −20%): not a mint.
- Refund path (`refundPlayer`) is per failed delivery and stock is reduced only by delivered units: no duplication seen. Orders lock per source (`OrderLocks[src]`), not per store, so two simultaneous buyers can both pass the stock check and oversell (stock floors at 0 via `GREATEST`). Low severity; include in the fix.
- Restock charges the full batch even when capped by `maxStock` (owner overpays; not a mint).
- Gas stations: 1 stock per fuel percent; retail 8/% (tiers 6/8/11) vs restock 4, so a full tank earns the owner ~240 at normal; tax 15,000 = ~62 full tanks. Consistent, no imbalance.
- nv_cloth: 1 stock per item; restock 10 vs median retail 20 (owner share 16) but armor 3,500 (share 2,800).
- Barber: restock 8/unit with a 100 base service cost.

Recommended model (not applied): **hybrid wholesale = max(category floor, wholesale% x catalog base price)** per catalog item, with `wholesale% ~ 55–65%` so the owner's 80% share leaves ~15–25% margin at normal and ~40% at HIGH tier,
and floors per category so cheap items never run at a loss. It keeps the existing 80/20 split and price tiers, keeps survival items profitable at a small margin, and removes the lottery/pickaxe arbitrage.
Lightest implementation (no per-item stock UI): **value-weighted stock** — each purchase consumes `ceil(base_price / unit_value)` stock units with a per-category `unit_value`, and restock cost stays flat per unit. Implement once in
`cm-commercial-ownership`, have cm-store consume it, and add cm-qa invariants (server price deducted, restock charged at wholesale, refund mints nothing, concurrent buyers cannot oversell).

## I. Duplicate price authority

| # | Duplicate | Class | Recommended owner |
|---|---|---|---|
| 1 | Fishing rods 50/100/150 and bait 5/10/15 in cm-store config and cm-fishing config (both sell) | actual conflicting authority (equal today) | cm-fishing owns; cm-store reads it (export) or drops the rows |
| 2 | Armor: `clothing_catalog` (3,500 x2), `cm_gun_catalog` (1,000 / 3,500 x2), nv_cloth `Config.Prices.armor` fallback 3,500 | conflicting (two sellers, one 1,000 outlier) | cm-gunstore for sold armor; nv_cloth only fits/publishes appearance |
| 3 | `cm_weapon_catalog.price` (cm-weapons, 59/61 rows = 0) vs `cm_gun_catalog.price` (shop) | legacy/presentation | cm-gunstore; cm-weapons price is only non-zero for rpg 250k and grenade launcher 150k |
| 4 | Licence price: `cm-license/config.lua` seeded into `cm_license_types` with `ON DUPLICATE KEY UPDATE price=VALUES(price)` (`server/database.lua`) | actual conflict: config overwrites an admin-edited DB price on restart (file is dirty; re-verify) | DB owns after first seed; seed with INSERT IGNORE |
| 5 | Medicine: cm-ems (bandage 40 … medikit 350) vs cm-doctor (25 … 120) | intentional channel pricing, undocumented | one price table with a per-channel multiplier |
| 6 | Vehicle: `classPrices` (rn-vehicleshop config) vs `cm_vehicle_catalog.price` | suggestion vs authority | DB row (already) |
| 7 | House: `cm_houses.price` vs `cm_house_pricing` calculator; `gov_value/insurance/daily_cost` derived in code | derived (intentional) | `cm_houses.price`; keep ratios in one constant |
| 8 | nv_cloth `Config.Prices` (10–50) and `Config.Economy` (200–45,000, no consumers) | fallback / dead documentation | `clothing_catalog.price`; delete or update the dead tables |
| 9 | Ownership constants (200k/250k, 12k/15k, 80%) repeated in cm-store, cm-gasstations, nv_cloth, cm-characters, cm-parking-v2, plus duplicated stock logic in cm-store | duplicated config and logic | cm-commercial-ownership engine; per-business config only for values |
| 10 | Taxi: cm-taxi vs legacy `outside/OT_taxi` | legacy reference only | cm-taxi (OT_taxi is not authoritative) |

## J. City Support design (not implemented)

State of `cm-payday` (the working tree holds ~450 lines of uncommitted change by Agent 1; re-check after it lands):
- Hourly wall-clock tick (`hourKey()`), per-character pending cash/XP in cm-playerdata metadata, per-character payout locks, an idempotent payout marker, and recovery via `economy_transactions` reason lookup.
- Playtime already accrues per character in real seconds (`cmPaydayPlaytimeSeconds`, flushed every 5 min and on unload/drop/stop).

Recommended design:
1. Reuse, do not add a payday system: a `Support` section in `CMPayday.Config` (`perHour = 37500`, `maxCatchUpHours = 4`).
2. A separate eligible-seconds accumulator (new metadata key, e.g. `cmPaydaySupportSeconds`) advanced inside `flushPlaytime` for eligible time only; total playtime stays untouched for other consumers.
3. Accrual, not clock amounts: at each tick and on logout/flush credit `floor(supportSeconds / 3600) x 37,500` as pending cash under a distinct source key `support` (not a job); subtract the consumed seconds. Payout then uses the existing journalled `payCash`, so it coexists with delayed job pay and survives a crash. 4 eligible hours = 150,000.
4. Eligibility (conservative): character loaded and spawned, not in the selector/loading, not admin-blocked. Optional soft AFK gate: count a window only if the server saw a position change or any server-validated action in the last N minutes; no input or screen monitoring. Add stricter rules only after abuse is seen.
5. Identity: keyed by character ID; source ID only locates the live session. One loaded character per source already limits multi-character farming; add a per-account rolling 4 h cap only if multi-boxing appears.
6. Ledger: reason `CM City Support <payoutId>`, `resource_name='cm-payday'`, distinct from `CM Payday <id>` wages; the payslip lists City Support separately. Admin grants (cm-admin), refunds (`*_refund`), business revenue (`business_balance` withdrawal) and job pay (`cashByJob`) keep their own reasons/resources so sources can be summed by reason prefix.
7. Safeguards: reuse `payoutLocks[charId]`, the persisted payout marker and transaction recovery; cap `maxCatchUpHours` so a long idle session cannot be redeemed at once; never add seconds during an in-flight payout.
8. cm-qa invariants: one credit per eligible hour, none while ineligible, recovery after a simulated crash between AddCash and marker clear, no double pay after a resource restart.

Prerequisite: Agent 1 finishes the current cm-payday changes.
