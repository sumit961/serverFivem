# CM Economy Database Export

Generated 2026-10-02 by `tools/cm-economy-export/export.py` (SELECT-only, session READ ONLY).
Source: local development database (MariaDB, localhost). Catalog/config data only; no player-owned rows or credentials.
Time conversions are **gross, rough model**: price / income rate. Support-only = 37,500/h; active-work = 87,500/h (beginner band) or 137,500/h (skilled band, midpoint of 500-600k per 4h). They ignore survival costs, operating costs and RNG.

## Vehicles (`cm_vehicle_catalog`, PK `id`, UNIQUE `model`; owned rows live in `cm_owned_vehicles`, not here)

Total 1555 rows: 19 player-purchasable (available_store/available_server, not retired), 9 fleet-only (EMS/police), 1527 hidden/unpublished (suggested class price only, `available_*`=0).

Sale back to state: `cm-vehicles` pays 30% of catalog price (100% only for permanently removed models).

### Player-purchasable (full list)

| ID | Model | Label | Category | Price | Store | Server | Support h | Active h (beg) | Active h (skilled) | Flag |
|---|---|---|---|---|---|---|---|---|---|---|
| 49 | revolter | Übermacht Revolter | Sports | 300,000 | 1 | 1 | 8.0 | 3.43 | 2.18 |  |
| 51 | schlagen | Benefactor Schlagen GT | Sports | 260,000 | 1 | 1 | 6.93 | 2.97 | 1.89 |  |
| 23 | neo | Vysser Neo | Sports | 230,000 | 1 | 1 | 6.13 | 2.63 | 1.67 |  |
| 45 | komoda | Lampadati Komoda | Sports | 202,000 | 1 | 1 | 5.39 | 2.31 | 1.47 |  |
| 4 | buccaneer2 | Albany Buccaneer Lux | Muscle | 200,000 | 0 | 1 | 5.33 | 2.29 | 1.45 |  |
| 28 | flashgt | Vapid Flash GT | Coupes | 160,000 | 1 | 1 | 4.27 | 1.83 | 1.16 |  |
| 36 | dubsta2 | Benefactor Dubsta | SUV | 150,000 | 1 | 1 | 4.0 | 1.71 | 1.09 |  |
| 47 | rocoto | Obey Rocoto | SUV | 130,000 | 1 | 1 | 3.47 | 1.49 | 0.95 |  |
| 7 | dominator3 | Vapid Dominator GTX | Muscle | 70,000 | 1 | 1 | 1.87 | 0.8 | 0.51 |  |
| 26 | windsor | Enus Windsor | Coupes | 70,000 | 1 | 1 | 1.87 | 0.8 | 0.51 |  |
| 38 | bf400 | Nagasaki BF400 | Motorcycles | 22,000 | 1 | 1 | 0.59 | 0.25 | 0.16 |  |
| 2 | sandking | Vapid Sandking XL | Off Road | 1,500 | 1 | 1 | 0.04 | 0.02 | 0.01 | NEAR-FREE |
| 1 | vstr | Albany V-STR | Sedans | 200 | 1 | 1 | 0.01 | 0.0 | 0.0 | NEAR-FREE |
| 40 | jester | Dinka Jester | Sports | 0 | 1 | 1 | 0 | 0 | 0 | FREE (price 0) |
| 53 | hycignus | Hycignus | Super | 0 | 1 | 1 | 0 | 0 | 0 | FREE (price 0) |
| 60 | draftvmark | Draftvmark | Emergency | 0 | 1 | 1 | 0 | 0 | 0 | FREE (price 0) |
| 632 | polmav | Police Maverick | Helicopters | 0 | 1 | 1 | 0 | 0 | 0 | FREE (price 0) |
| 635 | frogger | Frogger | Helicopters | 0 | 1 | 1 | 0 | 0 | 0 | FREE (price 0) |
| 938 | havok | Havok | Helicopters | 0 | 1 | 1 | 0 | 0 | 0 | FREE (price 0) |

### Fleet-only vehicles

| ID | Model | Category | Price | EMS | Police |
|---|---|---|---|---|---|
| 62 | ambulance_dodge_ram | Emergency | 0 | 1 | 0 |
| 64 | ambulance1 | Emergency | 0 | 1 | 0 |
| 66 | amrvan | Emergency | 0 | 1 | 0 |
| 68 | audirs6emsfire | Emergency | 0 | 1 | 0 |
| 70 | bmw-x5_medic | Emergency | 0 | 1 | 0 |
| 72 | royalg30medic | Emergency | 0 | 1 | 0 |
| 74 | polsilverado19 | Emergency | 0 | 0 | 1 |
| 431 | police3 | Emergency | 0 | 0 | 1 |
| 1185 | towtruck4 | Utility | 45,000 | 0 | 1 |

### Hidden / unpublished catalog price by category (class defaults; **not purchasable today**)

| Category | Count | Min | Median | Max | Zero-price rows |
|---|---|---|---|---|---|
| Planes | 46 | 0 | 0 | 0 | 46 |
| Boats | 27 | 0 | 0 | 0 | 27 |
| Helicopters | 33 | 0 | 0 | 0 | 33 |
| Emergency | 87 | 0 | 0 | 0 | 87 |
| Military | 17 | 0 | 0 | 0 | 17 |
| Rail | 10 | 0 | 0 | 0 | 10 |
| Bicycles | 9 | 1,500 | 1,500 | 1,500 | 0 |
| Compacts | 36 | 18,000 | 18,000 | 18,000 | 0 |
| Motorcycles | 83 | 28,500 | 35,000 | 35,000 | 0 |
| Sedans | 98 | 35,000 | 35,000 | 35,000 | 0 |
| Utility | 56 | 45,000 | 45,000 | 45,000 | 0 |
| Service | 13 | 50,000 | 50,000 | 50,000 | 0 |
| Vans | 56 | 50,000 | 50,000 | 50,000 | 0 |
| SUVs | 110 | 55,000 | 55,000 | 55,000 | 0 |
| Coupes | 69 | 60,000 | 60,000 | 60,000 | 0 |
| Off Road | 85 | 65,000 | 65,000 | 65,000 | 0 |
| Muscle | 162 | 70,000 | 70,000 | 70,000 | 0 |
| Sports Classics | 51 | 85,000 | 85,000 | 85,000 | 0 |
| Industrial | 11 | 90,000 | 90,000 | 90,000 | 0 |
| Commercial | 30 | 95,000 | 95,000 | 95,000 | 0 |
| Sports | 275 | 110,000 | 125,000 | 200,000 | 0 |
| Super | 163 | 0 | 350,000 | 350,000 | 1 |

Published price distribution: n=19 min=0 p25=0 median=70,000 avg=94,511 p75=200,000 p90=260,000 max=300,000


## Clothing (`clothing_catalog`, PK `id`, UNIQUE gender+component+drawable+texture; org restrictions in `clothing_catalog_organizations`)

140 rows; 87 published (enabled, not temp-disabled); 14 org-restricted. Price distribution (all): n=140 min=10 p25=20 median=20 avg=78 p75=50 p90=50 max=3,500

| Category | Count | Min | Median | Max | Support minutes (median) |
|---|---|---|---|---|---|
| armor | 2 | 3500 | 3500 | 3500 | 5.6 |
| bags | 13 | 20 | 20 | 20 | 0.03 |
| chains | 4 | 30 | 30 | 30 | 0.05 |
| earrings | 2 | 30 | 30 | 30 | 0.05 |
| glasses | 9 | 10 | 10 | 10 | 0.02 |
| hat | 13 | 20 | 20 | 20 | 0.03 |
| pants | 25 | 15 | 15 | 15 | 0.02 |
| shoes | 25 | 20 | 20 | 20 | 0.03 |
| torso | 43 | 50 | 50 | 50 | 0.08 |
| watches | 4 | 40 | 40 | 40 | 0.06 |

Price frequency: 10 x9, 15 x25, 20 x51, 30 x6, 40 x4, 50 x43, 3,500 x2

Shops: clothes=125, org_police=4, org_ems=3, org_army=7, armor=1
Organization access rows: police=11, ems=3, army=7, fib=7, sahp=7, sheriff=7

Clothing stores: 14 rows, 0 owned, tier(s) ['normal'], stock ~2500.


## Houses (`cm_houses` = definition + ownership in the same row via `owner_cid`; `cm_house_pricing` = price-add table)

| ID | Type | Garden | Pool | Heli | Stars | Garage | Price | Gov value (80%) | Insurance (3%) | Daily cost (0.1%) | For sale | Owned | Support h | Active h (beg) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 13 | villa | 1 | 1 | 1 | 2 | 10 | 1,230,000 | 984,000 | 36,900 | 1,230 | 0 | 1 | 32.8 | 14.06 |
| 14 | villa | 1 | 1 | 0 | 2 | 10 | 830,000 | 664,000 | 24,900 | 830 | 0 | 1 | 22.13 | 9.49 |
| 15 | mansion | 0 | 0 | 0 | 3 | 24 | 2,400,000 | 1,920,000 | 72,000 | 2,400 | 0 | 1 | 64.0 | 27.43 |

`cm_house_pricing` feature add-ons:

| Feature | Price add | Stars |
|---|---|---|
| type_trailer | 40,000 | 0 |
| type_apartment | 120,000 | 0 |
| type_house | 250,000 | 1 |
| type_villa | 600,000 | 2 |
| type_mansion | 1,200,000 | 3 |
| garden | 80,000 | 0 |
| pool | 150,000 | 0 |
| helipad | 400,000 | 0 |

Interior templates: #8 Motel Room with only 1 storage, #9 Motel Room, #10 Medium End Apartment 1S, #11 2133 Mad Wayne Thunder 1S1G. Garage templates: #8 10 space (10), #10 24 space (24)


## Businesses

Ownership rows (DB) are unowned across the board in dev; purchase price/tax/restock live in resource config (see table).

| Type | Table | Rows | Owned | Tiers | Stock values |
|---|---|---|---|---|---|
| convenience store | cm_stores | 5 | 0 | ['normal'] | [999, 1000] |
| gas station | cm_gas_stations | 26 | 0 | ['normal'] | [5000] |
| clothing store | cm_clothing_stores | 14 | 0 | ['normal'] | [2499, 2500] |
| barber shop | cm_barber_shops | 7 | 0 | ['normal'] | [999, 1000] |

### Business purchase economics (config; gross)

| Business | Purchase | Tax/7d | Restock/unit | Batch | Owner % | Support h to buy | Active h (beg) | Source |
|---|---|---|---|---|---|---|---|---|
| convenience store (cm-store) | 200,000 | 12,000 | 6 | 500 | 80 | 5.33 | 2.29 | cm-store/shared/config.lua |
| gas station (cm-gasstations) | 250,000 | 15,000 | 4 | 1000 | 80 | 6.67 | 2.86 | cm-gasstations/shared/config.lua |
| clothing store (nv_cloth) | 250,000 | 15,000 | 10 | 500 | 80 | 6.67 | 2.86 | nv_cloth/shared/config.lua |
| barber shop (cm-characters) | 200,000 | 12,000 | 8 | 250 | 80 | 5.33 | 2.29 | cm-characters/config.lua |
| parking (cm-parking-v2) | 250,000 | - | - | - | 80 | 6.67 | 2.86 | cm-parking-v2/adapter.lua |
| ATM (cm-bank) | 15,000 | - | - | - | - | 0.4 | 0.17 | cm-bank/shared/config.lua |

### cm-store restock imbalance (normal tier, owner share 80%, restock 6/unit, 1 unit of stock consumed per item bought)

| Item | Retail | Owner share (80%) | Profit per stock unit | Return on restock cost | Profit at HIGH tier |
|---|---|---|---|---|---|
| Worms (bait) | 5 | 4 | -2 | -33% | -0.4 |
| Common Bait | 10 | 8 | 2 | +33% | 4.4 |
| Water | 15 | 12 | 6 | +100% | 9.2 |
| Artificial Bait | 15 | 12 | 6 | +100% | 9.2 |
| Sandwich | 25 | 20 | 14 | +233% | 19.6 |
| Basic Fishing Rod | 50 | 40 | 34 | +567% | 44.4 |
| Fishing Rod L3 | 150 | 120 | 114 | +1900% | 144.4 |
| Cigarettes | 450 | 360 | 354 | +5900% | 444.4 |
| Crowbar | 1500 | 1200 | 1194 | +19900% | 1,494.0 |
| Level 2 Pickaxe | 10000 | 8000 | 7994 | +133233% | 9,994.0 |
| Lottery Ticket | 10000 | 8000 | 7994 | +133233% | 9,994.0 |
| Big Fireworks | 7500 | 6000 | 5994 | +99900% | 7,494.0 |

Break-even sketch (convenience store, price 200,000, tax 12,000/wk): weekly tax alone = 12,000 / 6 profit-per-water = 2,000 waters/week; the same tax is covered by 2 lottery tickets. Purchase break-even is ~33,000 waters vs ~25 lottery tickets. Real volume is unknown (dev DB has no owned business): MEASURE.


## Weapons (`cm_gun_catalog` = gunstore authority; `cm_weapon_catalog.price` is 0 for 59/61 rows and is not the shop price)

- weapon: n=58 min=1,800 p25=8,500 median=15,000 avg=22,560 p75=28,000 p90=55,000 max=70,000
- ammo: n=7 min=30 p25=40 median=80 avg=83 p75=110 p90=160 max=160
- armor: n=2 min=1,000 p25=1,000 median=3,500 avg=2,250 p75=3,500 p90=3,500 max=3,500

## Licences (`cm_license_types`)

| Type | Price | Valid days |
|---|---|---|
| boat | 1,000 | 30 |
| air | 5,000 | 30 |
| driver | 500 | 30 |

## Observed dev money flow (`economy_transactions`, aggregate by resource/action; dev data, 2 characters, NOT representative)

| Resource | Action | Rows | Net amount |
|---|---|---|---|
| cm-house | remove | 11 | -10,350,000 |
| rn-vehicleshop | remove | 40 | -5,905,050 |
| cm-admin | add | 13 | 5,602,000 |
| cm-house | add | 7 | 3,848,000 |
| rn-vehicleshop | add | 11 | 3,100,000 |
| cm-tuning | remove | 38 | -2,146,000 |
| oxmysql | add | 12 | 1,131,101 |
| cm-bank | remove | 9 | -1,129,755 |
| cm-parking-v2 | remove | 63 | -744,500 |
| cm-gunstore | remove | 57 | -467,910 |
| cm-commercial-ownership | remove | 2 | -400,000 |
| cm-gasstations | remove | 44 | -300,230 |
| cm-parking-v2 | add | 57 | 232,500 |
| cm-store | remove | 5 | -200,865 |
| cm-license | remove | 39 | -102,500 |
