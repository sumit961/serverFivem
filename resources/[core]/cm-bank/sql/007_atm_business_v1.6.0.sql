-- cm-bank v1.6.0 — ATM Business & Cash Reserve System
--
-- Turns owned ATMs into a small business: a physical cash reserve that
-- withdrawals actually consume (separate from the withdrawal fee), owner
-- restocking, an ATM-scoped business history/analytics table, and a
-- documented, exploit-safe accounting rule for what an owner recovers when
-- selling a machine.
--
-- Safe to run on an existing v1.5 database: every column add is
-- IF NOT EXISTS, no table is dropped, no ownership/pending-earnings/history/
-- verified-status data is ever touched or deleted. `cash_capacity` defaults
-- to 0 as a one-time "never initialized" sentinel — server/main.lua detects
-- that on boot and fills in the correct default once per row (100000 for an
-- owned ATM, 250000 full for a public one), after which capacity is always
-- > 0 and this can never re-trigger. Running this file by hand is optional;
-- server/main.lua applies the same statements automatically at boot.

ALTER TABLE bank_atm_locations
    ADD COLUMN IF NOT EXISTS cash_reserve INT NOT NULL DEFAULT 0;

ALTER TABLE bank_atm_locations
    ADD COLUMN IF NOT EXISTS cash_capacity INT NOT NULL DEFAULT 0;

ALTER TABLE bank_atm_locations
    ADD COLUMN IF NOT EXISTS owner_reserve_contribution INT NOT NULL DEFAULT 0;
    -- Tracks only cash the OWNER personally restocked (never player deposits
    -- or the government starting reserve). Recoverable on sale, capped at
    -- min(owner_reserve_contribution, cash_reserve) — see CHANGELOG_v1.6.0.md
    -- for the full sale formula and the exploit this prevents.

-- ATM-scoped business activity: withdrawals/deposits by any player at an
-- owned machine, plus that owner's own restock/earnings-withdrawal/
-- purchase/sale events. Deliberately separate from bank_transactions (which
-- is character-scoped for personal statements, character_id NOT NULL) so an
-- owner's dashboard can show other players' activity at their machine
-- without polluting anyone's personal statement. No index beyond
-- (atm_id, created_at) is added — it already covers both the paginated
-- history view and the range-filtered analytics aggregate.
CREATE TABLE IF NOT EXISTS bank_atm_activity (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    atm_id BIGINT NOT NULL,
    transaction_id VARCHAR(64) NULL,
    kind VARCHAR(24) NOT NULL,
    actor_character_id INT NULL,
    amount INT NOT NULL DEFAULT 0,
    fee_amount INT NOT NULL DEFAULT 0,
    reserve_after INT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_atm_created (atm_id, created_at)
);
