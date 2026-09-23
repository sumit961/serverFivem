-- cm-taxi driver progression (xp/level per character).
-- Created automatically by server/progression.lua on resource start;
-- kept here for reference / manual provisioning.
CREATE TABLE IF NOT EXISTS `cm_taxi_drivers` (
    `charid` VARCHAR(64) NOT NULL PRIMARY KEY,
    `xp` INT NOT NULL DEFAULT 0,
    `level` INT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS `cm_taxi_route_history` (
    `route_key` VARCHAR(128) NOT NULL PRIMARY KEY,
    `available_after` BIGINT NOT NULL
);
