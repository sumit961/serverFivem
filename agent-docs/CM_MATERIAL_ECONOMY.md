# CM Material Economy / Production Catalog (v1)

Status: V1 foundation, 2026-10-03. **Nothing in this catalog is live yet.** No gathering job produces these items, no consumer uses them, no station exists.
Read this one document to answer: *"Which material should this system use, what is it worth, and who may produce or consume it?"*
Companion: `agent-docs/CM_ECONOMY_STANDARD.md` (economy anchor), `resources/[core]/cm-materials/` (code), `resources/[core]/cm-inventory/docs/CRAFT_SETTLEMENT.md`, `resources/[core]/cm-crafting/docs/README.md`.

## 1. Ownership (architecture: MIXED)

| Concern | Owner | Notes |
|---|---|---|
| Item identity, label, weight, stack, metadata schema | **cm-items** (`shared/items.lua`) | 5 items added, 2 existing reused. Category `material`. |
| Custody, quantities, capacity, atomic settlement | **cm-inventory** | unchanged |
| Recipe engine, sessions, timers, idempotency | **cm-crafting** | unchanged; no second engine |
| Material economic metadata, production graph, recipe **definitions**, validation | **cm-materials** (new, read-only) | code-owned data, no DB, no mutation API, no client surface |
| Physical gathering/processing sites, jobs, stations, UI | **Agent 3 resources** (cm-mining, cm-lumber, cm-recycling, cm-construction, cm-warehouse, cm-trucking) | consume this catalog |

Why a new resource and not "just cm-items + cm-crafting": a runtime API is genuinely needed (Agent 3 must read values, ceilings, sinks and recipe definitions, and the economy rules must be validated at start),
and cm-items must not hold economic metadata. cm-materials holds **no item definitions**; it references cm-items ids and refuses to validate if one is missing or is not a stackable, non-unique, non-usable commodity.

**Recipe registration owner (decision):** cm-crafting pins a recipe to the resource that registers it, and only that resource may run crafts of it. So cm-materials owns the *definitions* and the
resource that **owns the station** registers them under its own name. cm-materials has no cm-crafting trust and no write path.

```lua
-- in the station-owning resource (add its name to cm-crafting Config.TrustedOwners first); on start AND on 'cm-crafting:server:registryReady'
local defs = exports['cm-materials']:GetProcessingRecipes('furnace')       -- nil if cm-materials is invalid/stopped
for _, def in ipairs(defs or {}) do exports['cm-crafting']:RegisterCraftRecipe(def) end
exports['cm-crafting']:RegisterCraftStation({ id = 'mining_furnace_1', type = 'furnace', coords = <server-owned>, radius = 3.0 })   -- site/coords belong to the world owner
```

## 2. Catalog (V1: 7 materials, 3 recipes)

Stages used: **raw** and **processed**. The `component` stage is defined but unused (nothing consumes components yet). Max planned depth is 3.

| Material (cm-items id) | Stage | Category | Source (owner) | Process | Sink (owner) | Ref value | Weight | Direct sale | Status |
|---|---|---|---|---|---|---|---|---|---|
| `iron_ore` (new) | raw | mineral | cm-mining | `materials:smelt_iron` @ furnace | processing only | 100 | 300 g | none | DEFINED_NOT_SOURCED |
| `iron_ingot` (new) | processed | mineral | smelting | - | cm-construction (INTEGRATION REQUIRED); cm-mechanic (DEFERRED) | 350 | 500 g | none | DEFINED_NOT_SOURCED |
| `log` (new) | raw | wood | cm-lumber | `materials:saw_timber` @ sawmill | processing only | 120 | 800 g | none | DEFINED_NOT_SOURCED |
| `timber` (new) | processed | wood | sawing | - | cm-construction (INTEGRATION REQUIRED) | 90 | 600 g | none | DEFINED_NOT_SOURCED |
| `metal_scrap` (existing) | raw | reclaimed | cm-recycling | `materials:reclaim_metal` @ recycling_processor | processing only | 40 | 120 g | none | DEFINED_NOT_SOURCED |
| `reclaimed_metal` (new) | processed | reclaimed | reclaiming | - | cm-construction (INTEGRATION REQUIRED); cm-mechanic (DEFERRED) | 180 | 300 g | none | DEFINED_NOT_SOURCED |
| `plastic` (existing) | raw | reclaimed | cm-recycling (**DEFERRED**) | none | none exists | 25 | 40 g | none | **DEFERRED** |

Item policy for all: `stack = true`, `unique = false`, `usable = false`, no metadata, no serials, `category = 'material'`, `worldModel = prop_boxpile_04a` (existing material convention),
`image = placeholder.png` (**art needed**). Existing `plastic`/`metal_scrap` definitions were not changed. Trade eligibility: cm-items has no tradeability flag; cm-trade item support stays disabled.
**Not added (no sink): copper, aluminium, stone/aggregate, plastic components, metal parts, planks.** Add them only through section 9.

## 3. Production graph

```
mining    -> iron_ore  --smelt_iron (3:1, 15 s, furnace)-->  iron_ingot  --> construction [REQUIRED] / mechanic parts [DEFERRED]
lumber    -> log       --saw_timber (2:3, 10 s, sawmill)-->  timber       --> construction [REQUIRED]
recycling -> metal_scrap --reclaim_metal (4:1, 12 s, recycling_processor)--> reclaimed_metal --> construction [REQUIRED] / mechanic parts [DEFERRED]
recycling -> plastic   (DEFERRED: no consumer; must not be granted)
```
Machine-readable: `CMMaterials.Items`, `CMMaterials.Recipes`, `exports['cm-materials']:GetProductionGraph()`.

## 4. Production recipes (`materials:` namespace; registered by the station owner)

| Recipe | Input | Output | Duration/unit | Station type | Registering owner (proposed) | Enabled |
|---|---|---|---|---|---|---|
| `materials:smelt_iron` | 3 iron_ore | 1 iron_ingot | 15 s | furnace | cm-mining | definition enabled; no station exists |
| `materials:saw_timber` | 2 log | 3 timber | 10 s | sawmill | cm-lumber | definition enabled; no station exists |
| `materials:reclaim_metal` | 4 metal_scrap | 1 reclaimed_metal | 12 s | recycling_processor | cm-recycling | definition enabled; no station exists |

All use real cm-crafting + real cm-inventory atomic settlement. Batch 1-10. `handcraft = false` so nothing is craftable anywhere by omission. cm-crafting's `test:` recipes remain test-only.

## 5. Economy model

Anchor: City Support 150,000 / 4 h = **37,500/h**; beginner active-work hour = **87,500** (37.5k + ~50k activity). Gathering jobs sit in the beginner band (activity 50,000-62,500/h).

- **Reference value** = internal balance anchor, not a price. Whole, x5 numbers. Raw values: ore 100, log 120, scrap 40 (small, bulky/cheap items), plastic 25.
- **Processed value** = input value + a small processing premium justified by time: allowance = `duration x 5/s` (semi-passive wait, ~20% of an active hour) + 10% of input value. Validated by code (`G.validate`).
- **Gathering budget:** a gathering job may award materials worth at most **40% of the 50,000 band floor = 20,000 reference value/hour**; the remainder is cash (via cm-payday) and XP. This gives a hard **quantity ceiling per hour**:
  `iron_ore 200/h, log 166/h, metal_scrap 500/h` (`GetMaterialQuantityCeiling`). Pay `cash/h = target band value - material value - tool/rental cost`; never full wage + full-value materials.
- **Value flow** (per batch; `created` = output - input):

| Recipe | Input value | Output value | Created | Allowance | Created/h running back-to-back |
|---|---|---|---|---|---|
| smelt_iron | 300 | 350 | 50 | 105 | 12,000 |
| saw_timber | 240 | 270 | 30 | 74 | 10,800 |
| reclaim_metal | 160 | 180 | 20 | 76 | 6,000 |

Back-to-back is a theoretical maximum (needs unlimited input); it is capped at 17,500/h (20% of an active hour) by validation. Conversion loss is expressed through the ratios (3:1, 4:1), not through destroyed value.
- **Timing:** all gathering rates are **GAMEPLAY TIMING REQUIRED** (cm-mining/cm-lumber have no code; cm-recycling cycle time is a configuration estimate of 540 s = 6.67 cycles/h). Do not invent rates; start at <= 50% of the ceiling and measure per `CM_ECONOMY_TIMING_PROTOCOL.md`.

## 6. Anti-arbitrage / exploit audit

| Risk | Finding | Outcome |
|---|---|---|
| Value creation by transformation | Every recipe creates <= its time/premium allowance; acyclic graph | validated + tested |
| Positive-value loop / reverse recipe | No A->B + B->A, no cycle; mutation tests prove the validator catches them | prevented |
| NPC buy -> craft -> sell | No store/vendor buys or sells any of these items (searched all CM resources; `cm-recycling` comments confirm no sale paths). `directSale = false` for all; if ever enabled, price <= 50% of reference | none today; rule enforced |
| Dismantle / reverse | No recipe consumes processed material to give raw | none |
| Job + craft double reward | Not applicable yet (no job pays materials). Rule for Agent 3: total = cash + material reference value inside the band; ceilings above | **Agent 3 must obey** |
| Contract double reward | cm-trucking supports only `business_supply`; `bulk_material_transport` has no publisher. Delivery pay must not also credit the worker the destination's materials | open for future contracts |
| Business stock duplication | Materials never enter the retail stock counter. The material balance is credited only inside one transaction that follows a committed cm-inventory item-sink debit (idempotent references, unique journals) | prevented by design + tests |
| Inflation by flooding | Ceilings above; a raw material is never enabled before a sink exists | gate |
| Plastic flood | cm-recycling lists plastic in `Earnings.materials`; it has no sink | keep `materialsEnabled = false` or remove plastic |

## 7. Integration contracts (Agent 3)

**Do not enable any of these until the sink exists and the status table is updated.**

| Owner | Today | Status | Contract |
|---|---|---|---|
| cm-mining | all files 0 bytes, not in server.cfg | **AGENT 3 INTEGRATION REQUIRED - cm-mining** | award `iron_ore` only; <= 200/h ceiling, start <= 100/h (10,000 value/h), cash = band target - material value - tool cost; own a `furnace` station (register `GetProcessingRecipes('furnace')`); award via cm-inventory server-side only |
| cm-lumber | all files 0 bytes, not in server.cfg | **AGENT 3 INTEGRATION REQUIRED - cm-lumber** | award `log` only; <= 166/h ceiling, start <= 80/h (9,600 value/h); own a `sawmill` station |
| cm-recycling | working code, not in server.cfg, `materialsEnabled = false` | **DEFERRED until a sink exists** (catalog prerequisites met: item, value, processing recipe, quantity target) | when enabled: grant `metal_scrap` only (suggest 6/cycle = 240 value/cycle = 1,600 value/h at 6.67 cycles/h), set `estimatedMaterialValuePerCycle = 240` and let cash subsidy fall to 8,160; remove `plastic` from `Earnings.materials`; register `GetProcessingRecipes('recycling_processor')` at the sorting station |
| cm-construction | all files 0 bytes | **AGENT 3 INTEGRATION REQUIRED - cm-construction** | needs a server-side material-consumption API: consume `timber`/`iron_ingot`/`reclaimed_metal` from the character via cm-inventory (never by cash), per task, idempotent by task reference; do not credit stock without consuming |
| cm-warehouse | all files 0 bytes | DEFERRED | physical logistics owner only; must not mint or own materials |
| cm-trucking | `business_supply` only | **AGENT 3 INTEGRATION READY** (business side) for `bulk_material_transport` | a publisher now exists (cm-commercial-ownership material demand); trucking must add the type and call `DeliverBusinessMaterials` after its own physical validation, then pay labour only; never mints |

## 8. Sinks

| Consumer | State | Authoritative owner |
|---|---|---|
| Construction | **INTEGRATION REQUIRED** (empty scaffold) | cm-construction consumes via cm-inventory |
| Mechanic | **DEFERRED**: cm-mechanic prices repairs in cash and has no parts/storage; no mechanic-part items were created | cm-mechanic (+ future parts system) |
| Business / commercial ownership | **FOUNDATION BUILT (2026-10-03), not live**: a business material balance + demand + player->business delivery saga exist in `cm-commercial-ownership` (docs/MATERIALS.md; retail product stock is untouched). No gathering feeds it yet, no business creates demand yet | cm-commercial-ownership; player custody via the cm-inventory item sink |
| Warehouse / trucking | DEFERRED | logistics owners; custody stays with inventory/storage owners |
| cm-contracts | routes work only | does not own materials |

## 9. Rules for adding or changing materials

1. A material needs a **source, a sink and a processing path** (or is `DEFERRED`). Add the cm-items definition, the catalog entry, and keep `lua tests/selftest.lua` green.
2. Prefer reusing an existing cm-items item. Never create `iron` next to `iron_ingot`.
3. **Never silently rename or repurpose an item id** once players can own it. Deprecate instead: keep the item readable, set the catalog status `DEFERRED`, migrate with an explicit script.
4. Changing a recipe ratio never rewrites inventories (recipes are not stored); keep old ids stable and add `materials:<name>_v2` if semantics change.
5. Reference values are whole x5 numbers; direct NPC sale (if ever justified) <= 50% of reference and needs its own audit row in `CM_ECONOMY_AUDIT.md`.
6. No universal "sell all materials" NPC, no commodity exchange, no dynamic pricing, no new currency.
7. A status becomes `ACTIVE` only when every listed source and sink link is `active` and the owner resource is integrated.

## 10. Runtime API (cm-materials, server exports, read-only, deep copies, fail closed if the catalog is invalid)

`IsMaterial(id)`, `GetMaterial(id)`, `GetMaterialReferenceValue(id)`, `GetMaterialSources(id)`, `GetMaterialSinks(id)`, `GetMaterialQuantityCeiling(id)`,
`GetProductionGraph()`, `GetProcessingRecipes(stationType)`. Console: `cm_materials_status`. No client event, NUI callback or mutation exists; clients cannot supply or alter values, tiers, conversions, sources or sinks.

## 11. Tests

`lua tests/selftest.lua` (catalog/graph/economy/recipes + validator mutation tests, real cm-items definitions, real cm-crafting registry), `lua tests/integration_crafting.lua`
(production recipes through real cm-crafting and the real cm-inventory craft settlement over a SQL double). Live gameplay is untested by instruction.
