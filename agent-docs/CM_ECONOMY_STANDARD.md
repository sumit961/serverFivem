# CM Economy Standard

Status: DRAFT v1 (2026-10-02). Contract for every CM resource that creates or removes money.
Companion: `agent-docs/CM_ECONOMY_AUDIT.md` (per-value audit and proposals).

## 1. Baseline

- **City Support: 150,000 per 4 eligible hours** (no job required).
- **1 baseline player-hour = 37,500.**
- Eligible hour = connected, spawned character, not in character selector/loading. Tracked per **character ID**
  (never source ID). Prefer extending `cm-payday` (`cmPaydayPlaytimeSeconds` metadata already accrues real seconds
  per character) rather than creating a second payday system. Status: **not implemented** (see audit §A).

## 2. Income bands (total per ~4h, including City Support)

| Band | Total / 4h | Activity component / hour | Examples |
|---|---|---|---|
| No job | 150k | 0 | idle RP |
| Beginner legal | 350–400k | 50.0–62.5k | Taxi L1, Fishing L0-1, Farming L0, Electrician L1 |
| Established | 400–500k | 62.5–87.5k | mid-level jobs |
| Skilled / progression | 500–600k | 87.5–112.5k | Electrician L3, Fishing L4-5, Taxi L3 |
| Difficult / high-risk | 600–750k+ | 112.5–150k+ | illegal/high-risk, must carry loss risk |

Do not default everything to the top of a band. Net of rentals, consumables and failure.

## 3. Cost classes

1. **Survival** (food, drink, basic fuel, basic clothes, small services): all daily survival combined <= ~15% of City Support
   (<= ~5.6k per hour). Never a progression wall. Full tank 800 (~2% of an hour) is acceptable.
2. **Progression** (vehicles, upgrades, tools, licences, premium clothing, business entry): priced in *active-work hours*.
3. **Prestige / endgame** (supercars, luxury property, major business, rare cosmetics): City Support alone must need weeks.

**Active-work hour** (beginner) = 37.5k support + ~50k job = **~87.5k**. Price progression by hours of this unit.

## 4. Progression price ladder (active-work hours @ ~87.5k)

| Tier | Hours | Approx price |
|---|---|---|
| Consumable / small | 0.01–0.2 | 1k–18k |
| Standard clothing outfit | 0.1–0.4 | 8k–35k |
| Premium outfit | 0.5–2 | 45k–175k |
| Tool that raises earning rate | 0.3–3 | 25k–260k |
| Starter vehicle | 3 | ~260k |
| Commuter vehicle | 6 | ~525k |
| Good sedan / SUV | 12 | ~1.05M |
| Performance car | 25 | ~2.2M |
| Sports car | 50 | ~4.4M |
| Super car | 100 | ~8.75M |
| Ultra / prestige vehicle | 200 | ~17.5M |
| Apartment / small house | 40 | ~3.5M |
| Normal house | 80 | ~7M |
| Luxury house | 250 | ~22M |
| Small business | 60 | ~5M |
| Major business | 200 | ~17.5M |

Clothing bands: Basic <= 1.5k, Standard 3.5k, Premium 15k–60k, Luxury/rare 100k–500k.
Clothing/vehicle/house prices are **database rows** (`clothing_catalog`, `cm_vehicle_catalog`, house tables); the repo only owns
defaults (`rn-vehicleshop` `classPrices`, `nv_cloth` `Config.Prices`). Change data via the admin tools, not by adding second price tables.

## 5. Reward calculation method

`reward_per_action = target_hourly_activity_income / expected_completions_per_hour`, where completions/hour includes travel, setup,
cooldowns, failure rate and availability. Subtract recurring costs (rental, bait, seeds, fuel) to get net/hour.
Anything that cannot be established statically is marked **MEASURE** in the audit and must be timed in a live run before final values.

## 6. Business rules

- Purchase price = operating-hours-to-break-even target x measured owner profit/hour; never below ~40 active-work hours.
- Break-even target 30–60 operating hours of normal trade for small, 100+ for major; weekly tax <= ~10% of weekly gross owner profit.
- Stock units must be priced by value, not as flat per-unit: restock cost per unit must scale with the item's sale price
  (see audit loop L2; currently a 450 cigarette and a 15 water cost the same 6 to restock).
- Owner revenue share (80%) applies to price actually paid; city share is a sink.

## 7. Inflation rules

- Every new source (reward, sale, refund) needs a matching sink or cap and an hourly rate on the audit table.
- No buy-low/sell-high loop between any two CM systems. Sale value of any produced good <= its input cost + labour-time value.
- Refunds return what was paid exactly once (idempotent); never more.
- All amounts resolved server-side; client sends item/quantity only.

## 8. Requirements for future resources

Document: hourly income at each level, setup/recurring costs, payout path (`cm-payday` vs immediate), band, and add rows to the audit.
Payouts for repeatable jobs go through `cm-payday` pending cash unless there is a documented reason.
