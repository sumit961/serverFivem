# CM Characters fixed character ID

This version creates permanent RP character IDs in `characters.id`.

- First created character: `0`
- Second created character: `1`
- Third created character: `2`

This ID is different from the FiveM server/source ID. FiveM source changes every relog; `characters.id` must be used for inventory, store, money, jobs, phone, keys, and all saved data.

## Database

The resource creates this helper table automatically:

```sql
CREATE TABLE IF NOT EXISTS cm_character_id_counter (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

The allocated character ID is `AUTO_INCREMENT - 1`, so the first ID is `0`.

## Important

If you already have old characters with IDs like `1780799251_7449`, they will still exist. New characters created after installing this version will use numeric IDs like `0`, `1`, `2`.

If you want a fully clean test, delete old character rows and related inventory rows first, then restart the resource and create a new character.
