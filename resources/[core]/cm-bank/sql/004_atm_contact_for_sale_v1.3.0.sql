-- cm-bank: owner contact info + admin for-sale toggle for ATMs. Applied
-- automatically at resource start via ALTER TABLE ... ADD COLUMN IF NOT
-- EXISTS in server/main.lua. Run manually only if the DB user lacks ALTER
-- privileges.

ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS contact VARCHAR(100) NULL;
ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS for_sale TINYINT(1) NOT NULL DEFAULT 1;
