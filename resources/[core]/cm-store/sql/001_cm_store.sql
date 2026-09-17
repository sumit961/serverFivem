-- cm-store: Store ownership and business management table
CREATE TABLE IF NOT EXISTS cm_stores (
    store_id INT NOT NULL PRIMARY KEY,
    owner_character_id BIGINT NULL,
    owner_name VARCHAR(120) NULL,
    price_tier VARCHAR(12) NOT NULL DEFAULT 'normal',
    stock INT NOT NULL DEFAULT 1000,
    business_balance BIGINT NOT NULL DEFAULT 0,
    daily_income BIGINT NOT NULL DEFAULT 0,
    weekly_income BIGINT NOT NULL DEFAULT 0,
    tax_due_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

