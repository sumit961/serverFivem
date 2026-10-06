"""Read-only CM economy catalog export.

Writes agent-docs/CM_ECONOMY_DATABASE_EXPORT.md and agent-docs/economy-export/*.csv.
Catalog/config data only: no player-owned rows, no credentials. SELECT-only via ro.py.
Run: python tools/cm-economy-export/export.py
"""
import csv, statistics as st, pathlib, datetime
from collections import Counter, defaultdict
from ro import connect, q, ROOT

SUPPORT_H = 37_500          # City Support value of 1 hour
ACTIVE_BEGINNER_H = 87_500  # 350k / 4h
ACTIVE_SKILLED_H = 137_500  # 550k / 4h

OUT = ROOT / 'agent-docs'
CSV = OUT / 'economy-export'
CSV.mkdir(exist_ok=True)


def hrs(price, rate):
    return round(price / rate, 2) if price else 0


def dist(vals):
    v = sorted(vals)
    if not v:
        return 'n=0'
    n = len(v)
    return f"n={n} min={v[0]:,} p25={v[n // 4]:,} median={v[n // 2]:,} avg={round(sum(v) / n):,} p75={v[3 * n // 4]:,} p90={v[int(n * .9)]:,} max={v[-1]:,}"


def write_csv(name, rows):
    if not rows:
        return
    with open(CSV / name, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def md_table(headers, rows):
    out = ['| ' + ' | '.join(headers) + ' |', '|' + '---|' * len(headers)]
    out += ['| ' + ' | '.join(str(c) for c in r) + ' |' for r in rows]
    return '\n'.join(out)


c = connect()
md = []
md.append('# CM Economy Database Export\n')
md.append(f"Generated {datetime.date.today()} by `tools/cm-economy-export/export.py` (SELECT-only, session READ ONLY).\n"
          "Source: local development database (MariaDB, localhost). Catalog/config data only; no player-owned rows or credentials.\n"
          "Time conversions are **gross, rough model**: price / income rate. Support-only = 37,500/h; active-work = 87,500/h (beginner band) "
          "or 137,500/h (skilled band, midpoint of 500-600k per 4h). They ignore survival costs, operating costs and RNG.\n")

# ---------------- vehicles
veh = q(c, """SELECT id, model, label, category, price, available_store, available_server, available_ems,
              available_police, legal_org, gang_id, retired, vehicle_type FROM cm_vehicle_catalog""")
pub = [r for r in veh if (r['available_store'] or r['available_server']) and not r['retired']]
fleet = [r for r in veh if (r['available_ems'] or r['available_police']) and not (r['available_store'] or r['available_server'])]
hidden = [r for r in veh if not (r['available_store'] or r['available_server'] or r['available_ems'] or r['available_police'])]
md.append('## Vehicles (`cm_vehicle_catalog`, PK `id`, UNIQUE `model`; owned rows live in `cm_owned_vehicles`, not here)\n')
md.append(f"Total {len(veh)} rows: {len(pub)} player-purchasable (available_store/available_server, not retired), {len(fleet)} fleet-only (EMS/police), "
          f"{len(hidden)} hidden/unpublished (suggested class price only, `available_*`=0).\n")
md.append('Sale back to state: `cm-vehicles` pays 30% of catalog price (100% only for permanently removed models).\n')
md.append('### Player-purchasable (full list)\n')
rows = sorted(pub, key=lambda r: -r['price'])
md.append(md_table(['ID', 'Model', 'Label', 'Category', 'Price', 'Store', 'Server', 'Support h', 'Active h (beg)', 'Active h (skilled)', 'Flag'],
    [(r['id'], r['model'], r['label'], r['category'], f"{r['price']:,}", r['available_store'], r['available_server'],
      hrs(r['price'], SUPPORT_H), hrs(r['price'], ACTIVE_BEGINNER_H), hrs(r['price'], ACTIVE_SKILLED_H),
      'FREE (price 0)' if r['price'] == 0 else ('NEAR-FREE' if r['price'] < 5000 else '')) for r in rows]))
md.append('\n### Fleet-only vehicles\n')
md.append(md_table(['ID', 'Model', 'Category', 'Price', 'EMS', 'Police'],
    [(r['id'], r['model'], r['category'], f"{r['price']:,}", r['available_ems'], r['available_police']) for r in fleet]))
md.append('\n### Hidden / unpublished catalog price by category (class defaults; **not purchasable today**)\n')
cat = defaultdict(list)
for r in hidden:
    cat[r['category']].append(r['price'])
md.append(md_table(['Category', 'Count', 'Min', 'Median', 'Max', 'Zero-price rows'],
    [(k, len(v), f"{min(v):,}", f"{int(st.median(v)):,}", f"{max(v):,}", sum(1 for x in v if x == 0))
     for k, v in sorted(cat.items(), key=lambda kv: st.median(kv[1]))]))
md.append(f"\nPublished price distribution: {dist([r['price'] for r in pub])}\n")
write_csv('vehicles_all.csv', [{k: r[k] for k in ('id', 'model', 'label', 'category', 'price', 'available_store', 'available_server',
                                                  'available_ems', 'available_police', 'retired', 'vehicle_type')} for r in veh])

# ---------------- clothing
cl = q(c, """SELECT id, gender, component_type, label, price, category, shop, enabled, temp_disabled, sell_category, collection
             FROM clothing_catalog""")
orgs = defaultdict(list)
for r in q(c, "SELECT clothing_id, organization_id FROM clothing_catalog_organizations"):
    orgs[r['clothing_id']].append(r['organization_id'])
md.append('\n## Clothing (`clothing_catalog`, PK `id`, UNIQUE gender+component+drawable+texture; org restrictions in `clothing_catalog_organizations`)\n')
live = [r for r in cl if r['enabled'] and not r['temp_disabled']]
md.append(f"{len(cl)} rows; {len(live)} published (enabled, not temp-disabled); {sum(1 for r in cl if r['id'] in orgs)} org-restricted. "
          f"Price distribution (all): {dist([r['price'] for r in cl])}\n")
bycat = defaultdict(list)
for r in cl:
    bycat[r['category'] or r['sell_category'] or r['component_type']].append(r['price'])
md.append(md_table(['Category', 'Count', 'Min', 'Median', 'Max', 'Support minutes (median)'],
    [(k, len(v), v and min(v), int(st.median(v)), max(v), round(st.median(v) / SUPPORT_H * 60, 2)) for k, v in sorted(bycat.items())]))
md.append('\nPrice frequency: ' + ', '.join(f"{p:,} x{n}" for p, n in sorted(Counter(r['price'] for r in cl).items())))
md.append('\nShops: ' + ', '.join(f"{k}={v}" for k, v in Counter(r['shop'] for r in cl).items()))
md.append('Organization access rows: ' + ', '.join(f"{o}={n}" for o, n in Counter(o for v in orgs.values() for o in v).items()))
store = q(c, "SELECT shop_id, owner_character_id IS NOT NULL owned, price_tier, stock, business_balance, weekly_income FROM cm_clothing_stores")
md.append(f"\nClothing stores: {len(store)} rows, {sum(1 for s in store if s['owned'])} owned, tier(s) {sorted({s['price_tier'] for s in store})}, stock ~{sorted({s['stock'] for s in store})[-1]}.\n")
write_csv('clothing_catalog.csv', [dict(r, orgs=';'.join(orgs.get(r['id'], []))) for r in cl])

# ---------------- houses
hs = q(c, """SELECT id, house_number, label, house_type, has_garden, has_pool, has_helipad, star_rating, garage_slots, price, gov_value,
             insurance, daily_cost, for_sale, status, owner_cid IS NOT NULL owned FROM cm_houses""")
md.append('\n## Houses (`cm_houses` = definition + ownership in the same row via `owner_cid`; `cm_house_pricing` = price-add table)\n')
md.append(md_table(['ID', 'Type', 'Garden', 'Pool', 'Heli', 'Stars', 'Garage', 'Price', 'Gov value (80%)', 'Insurance (3%)', 'Daily cost (0.1%)', 'For sale', 'Owned', 'Support h', 'Active h (beg)'],
    [(r['id'], r['house_type'], r['has_garden'], r['has_pool'], r['has_helipad'], r['star_rating'], r['garage_slots'], f"{r['price']:,}",
      f"{r['gov_value']:,}", f"{r['insurance']:,}", f"{r['daily_cost']:,}", r['for_sale'], r['owned'],
      hrs(r['price'], SUPPORT_H), hrs(r['price'], ACTIVE_BEGINNER_H)) for r in hs]))
md.append('\n`cm_house_pricing` feature add-ons:\n')
md.append(md_table(['Feature', 'Price add', 'Stars'], [(r['feature_key'], f"{r['price_add']:,}", r['star_add']) for r in q(c, "SELECT * FROM cm_house_pricing")]))
md.append('\nInterior templates: ' + ', '.join(f"#{r['id']} {r['label']}" for r in q(c, "SELECT id,label FROM cm_house_interior_templates"))
          + '. Garage templates: ' + ', '.join(f"#{r['id']} {r['label']} ({r['capacity']})" for r in q(c, "SELECT id,label,capacity FROM cm_house_garage_templates")))
write_csv('houses.csv', hs)

# ---------------- businesses
md.append('\n\n## Businesses\n')
md.append('Ownership rows (DB) are unowned across the board in dev; purchase price/tax/restock live in resource config (see table).\n')
biz_db = []
for t, k, kind in [('cm_stores', 'store_id', 'convenience store'), ('cm_gas_stations', 'station_id', 'gas station'),
                   ('cm_clothing_stores', 'shop_id', 'clothing store'), ('cm_barber_shops', 'shop_id', 'barber shop')]:
    rows = q(c, f"SELECT {k} id, owner_character_id IS NOT NULL owned, price_tier, stock, business_balance FROM {t}")
    biz_db.append((kind, t, len(rows), sum(1 for r in rows if r['owned']), sorted({r['price_tier'] for r in rows}), sorted({r['stock'] for r in rows})))
md.append(md_table(['Type', 'Table', 'Rows', 'Owned', 'Tiers', 'Stock values'], biz_db))
CFG = [  # kind, price, tax/7d, restock/unit, batch, owner%, source
    ('convenience store (cm-store)', 200_000, 12_000, 6, 500, 80, 'cm-store/shared/config.lua'),
    ('gas station (cm-gasstations)', 250_000, 15_000, 4, 1000, 80, 'cm-gasstations/shared/config.lua'),
    ('clothing store (nv_cloth)', 250_000, 15_000, 10, 500, 80, 'nv_cloth/shared/config.lua'),
    ('barber shop (cm-characters)', 200_000, 12_000, 8, 250, 80, 'cm-characters/config.lua'),
    ('parking (cm-parking-v2)', 250_000, None, None, None, 80, 'cm-parking-v2/adapter.lua'),
    ('ATM (cm-bank)', 15_000, None, None, None, None, 'cm-bank/shared/config.lua'),
]
md.append('\n### Business purchase economics (config; gross)\n')
md.append(md_table(['Business', 'Purchase', 'Tax/7d', 'Restock/unit', 'Batch', 'Owner %', 'Support h to buy', 'Active h (beg)', 'Source'],
    [(n, f"{p:,}", f"{t:,}" if t else '-', u or '-', b or '-', o or '-', hrs(p, SUPPORT_H), hrs(p, ACTIVE_BEGINNER_H), s) for n, p, t, u, b, o, s in CFG]))

md.append('\n### cm-store restock imbalance (normal tier, owner share 80%, restock 6/unit, 1 unit of stock consumed per item bought)\n')
ITEMS = [('Worms (bait)', 5), ('Common Bait', 10), ('Water', 15), ('Artificial Bait', 15), ('Sandwich', 25), ('Basic Fishing Rod', 50),
         ('Fishing Rod L3', 150), ('Cigarettes', 450), ('Crowbar', 1500), ('Level 2 Pickaxe', 10000), ('Lottery Ticket', 10000), ('Big Fireworks', 7500)]
rows = []
for n, p in ITEMS:
    for tier, mult in (('low', .85), ('normal', 1.0), ('high', 1.25)):
        pass
    own = int(p * .8)
    rows.append((n, p, own, own - 6, f"{(own - 6) / 6:+.0%}", f"{(int(-(-p * 1.25 // 1)) * .8 - 6):,.1f}"))
md.append(md_table(['Item', 'Retail', 'Owner share (80%)', 'Profit per stock unit', 'Return on restock cost', 'Profit at HIGH tier'], rows))
md.append('\nBreak-even sketch (convenience store, price 200,000, tax 12,000/wk): weekly tax alone = 12,000 / 6 profit-per-water = 2,000 waters/week; '
          'the same tax is covered by 2 lottery tickets. Purchase break-even is ~33,000 waters vs ~25 lottery tickets. '
          'Real volume is unknown (dev DB has no owned business): MEASURE.\n')

# ---------------- weapons / licences / medical
g = q(c, "SELECT item_name, item_type, price, enabled FROM cm_gun_catalog")
md.append('\n## Weapons (`cm_gun_catalog` = gunstore authority; `cm_weapon_catalog.price` is 0 for 59/61 rows and is not the shop price)\n')
for t in ('weapon', 'ammo', 'armor'):
    vals = [r['price'] for r in g if r['item_type'] == t and r['enabled']]
    md.append(f"- {t}: {dist(vals)}")
md.append('\n## Licences (`cm_license_types`)\n')
md.append(md_table(['Type', 'Price', 'Valid days'], [(r['license_type'], f"{r['price']:,}", r['valid_days']) for r in q(c, "SELECT * FROM cm_license_types")]))

# ---------------- observed money flow (aggregates only)
md.append('\n## Observed dev money flow (`economy_transactions`, aggregate by resource/action; dev data, 2 characters, NOT representative)\n')
flow = q(c, """SELECT resource_name, action, COUNT(*) n, SUM(amount) total FROM economy_transactions
               GROUP BY resource_name, action ORDER BY ABS(SUM(amount)) DESC LIMIT 15""")
md.append(md_table(['Resource', 'Action', 'Rows', 'Net amount'], [(r['resource_name'], r['action'], r['n'], f"{int(r['total']):,}") for r in flow]))

(OUT / 'CM_ECONOMY_DATABASE_EXPORT.md').write_text('\n'.join(md) + '\n', encoding='utf-8')
print('written', OUT / 'CM_ECONOMY_DATABASE_EXPORT.md')
