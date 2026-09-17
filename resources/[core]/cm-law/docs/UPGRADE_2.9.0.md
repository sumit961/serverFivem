# CM Law 2.9.0

## Overview

- Reorganized the Overview into a clear hierarchy: member identity, four key metrics, readiness, shared custody, and expandable activity.
- Kept detailed rosters, capabilities, and logs out of the primary reading path.

## Unified booking

- Police and every other legal organization now open the same charge-based booking review panel.
- Sentence totals are previewed for the officer but recalculated and validated server-side.
- Booking stays tied to the single `cm-prison` intake, spawn pool, and release authority.

## Daily objectives

- Added server-verified daily/weekly progress for on-duty minutes, confirmed bookings, and resolved dispatch calls.
- Existing private checklist and notes remain available and are not replaced.

## Recovery

- On resource restart, stale `processing` custody rows return to `cuffed` and unfinished booking journal rows are marked failed with `server_restart`.
- Officers can retry after the shared prison is ready without a duplicate phantom sentence.
