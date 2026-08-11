local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1
L0_1 = {}
L0_1.rcore_prison = true
L0_1.rcore_prison_accounts = true
L0_1.rcore_prison_accounts_log = true
L0_1.rcore_prison_coms = true
L0_1.rcore_prison_coms_sessions = true
L0_1.rcore_prison_stash = true
L0_1.rcore_prison_logs = true
L1_1 = {}
L1_1.rcore_prison_coms = true
L1_1.rcore_prison_coms_sessions = true
L2_1 = 0
L3_1 = table
L3_1 = L3_1.size
L4_1 = L1_1
L3_1 = L3_1(L4_1)
L4_1 = 0
L5_1 = table
L5_1 = L5_1.size
L6_1 = L0_1
L5_1 = L5_1(L6_1)
L6_1 = 0
L7_1 = false
L8_1 = {}
L8_1[1] = [[
        CREATE TABLE IF NOT EXISTS `rcore_prison` (
            `prisoner_id` INT(11) NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(80) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `solitary_time` DATETIME NULL DEFAULT NULL,
            `jail_time` DATETIME NULL DEFAULT NULL,
            `data` LONGTEXT NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `createdAt` TIMESTAMP NULL DEFAULT current_timestamp(),
            `updatedAt` TIMESTAMP NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`prisoner_id`) USING BTREE,
            INDEX `owner` (`owner`) USING BTREE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
L8_1[2] = [[
        CREATE TABLE IF NOT EXISTS `rcore_prison_accounts` (
            `account_id` INT(11) NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(80) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `balance` BIGINT(20) NULL DEFAULT '0',
            `giftstate` TINYINT(4) NULL DEFAULT '0',
            `createdAt` TIMESTAMP NULL DEFAULT current_timestamp(),
            `updatedAt` TIMESTAMP NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`account_id`) USING BTREE,
            INDEX `owner` (`owner`) USING BTREE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
L8_1[3] = [[
        CREATE TABLE IF NOT EXISTS `rcore_prison_coms_sessions` (
            `zoneId` BIGINT(10) NOT NULL,
            `verticesTarget` BIGINT(10) NOT NULL,
            `verticesDone` BIGINT(10) NOT NULL DEFAULT '0',
            PRIMARY KEY (`zoneId`),
            INDEX `zoneId_index` (`zoneId`) USING BTREE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
L8_1[4] = [[
        CREATE TABLE IF NOT EXISTS `rcore_prison_coms` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(80) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `zoneId` BIGINT(10) NULL DEFAULT NULL,
            `state` ENUM('IDLE','SWEEPING','RETURN') NOT NULL COLLATE 'utf8mb4_unicode_ci',
            `perollAmount` INT(10) NULL DEFAULT '0',
            `perollTarget` INT(10) NULL DEFAULT '0',
            `createdAt` TIMESTAMP NULL DEFAULT current_timestamp(),
            `name` VARCHAR(60) NOT NULL COLLATE 'utf8mb4_unicode_ci',
            PRIMARY KEY (`id`) USING BTREE,
            INDEX `owner` (`owner`) USING BTREE,
            INDEX `zoneId` (`zoneId`) USING BTREE,
            CONSTRAINT `FK_Q27L` FOREIGN KEY (`zoneId`) REFERENCES `rcore_prison_coms_sessions` (`zoneId`) ON UPDATE RESTRICT ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
L8_1[5] = [[
        CREATE TABLE IF NOT EXISTS `rcore_prison_stash` (
            `owner` VARCHAR(255) NOT NULL,
            `stash` LONGTEXT NOT NULL COLLATE 'utf8mb4_unicode_ci',
            PRIMARY KEY (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
L8_1[6] = [[
        CREATE TABLE IF NOT EXISTS `rcore_prison_logs` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `action` VARCHAR(50) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `desc` VARCHAR(255) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `charId` VARCHAR(70) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `officer_name` VARCHAR(70) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `citizen_name` VARCHAR(70) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `created_at` DATETIME NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
L8_1[7] = [[
        CREATE TABLE `rcore_prison_accounts_log` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `action` VARCHAR(50) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `desc` VARCHAR(300) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `charId` VARCHAR(50) NULL DEFAULT NULL COLLATE 'utf8mb4_unicode_ci',
            `amount` INT(11) NULL DEFAULT NULL,
            `created_at` DATETIME NULL DEFAULT NULL,
            PRIMARY KEY (`id`) USING BTREE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
IS_DATABASE_READY = false
function L9_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2
  L0_2 = promise
  L0_2 = L0_2.new
  L0_2 = L0_2()
  L1_2 = 0
  L2_2 = false
  L3_2 = pairs
  L4_2 = L0_1
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = db
    L9_2 = L9_2.DoesTableExist
    L10_2 = L7_2
    L9_2 = L9_2(L10_2)
    L10_2 = L0_1
    L10_2 = L10_2[L7_2]
    if L10_2 and L9_2 then
      L10_2 = L4_1
      L10_2 = L10_2 + 1
      L4_1 = L10_2
    elseif not L9_2 then
      L10_2 = L6_1
      L10_2 = L10_2 + 1
      L6_1 = L10_2
    end
    L10_2 = L1_1
    L10_2 = L10_2[L7_2]
    if L10_2 and not L9_2 then
      L10_2 = L2_1
      L10_2 = L10_2 + 1
      L2_1 = L10_2
      L10_2 = L2_1
      L11_2 = L3_1
      if L10_2 >= L11_2 then
        L10_2 = true
        L7_1 = L10_2
      end
    end
    L1_2 = L1_2 + 1
    L10_2 = L5_1
    if L1_2 >= L10_2 then
      L11_2 = L0_2
      L10_2 = L0_2.resolve
      L10_2(L11_2)
    end
  end
  L3_2 = Citizen
  L3_2 = L3_2.Await
  L4_2 = L0_2
  L3_2(L4_2)
  L3_2 = MySQL
  L3_2 = L3_2.Sync
  L3_2 = L3_2.fetchSingle
  L4_2 = [[
        SELECT COUNT(*)
        AS table_count
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'rcore_prison'
        AND TABLE_SCHEMA = DATABASE()
    ]]
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L4_2 = L3_2.table_count
    if L4_2 > 0 then
      L4_2 = MySQL
      L4_2 = L4_2.Sync
      L4_2 = L4_2.fetchSingle
      L5_2 = [[
            SELECT COUNT(*)
            AS column_count
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'rcore_prison'
            AND COLUMN_NAME = 'solitary_time'
            AND TABLE_SCHEMA = DATABASE()
        ]]
      L4_2 = L4_2(L5_2)
      if L4_2 then
        L5_2 = L4_2.column_count
        if 0 == L5_2 then
          L5_2 = dbg
          L5_2 = L5_2.debug
          L6_2 = "Adding column `solitary_time` to `rcore_prison` table."
          L5_2(L6_2)
          L5_2 = MySQL
          L5_2 = L5_2.Sync
          L5_2 = L5_2.execute
          L6_2 = [[
                ALTER TABLE `rcore_prison`
                ADD COLUMN `solitary_time` DATETIME NULL DEFAULT current_timestamp() AFTER `owner`;
            ]]
          L5_2(L6_2)
        end
      end
    end
  end
  L4_2 = L6_1
  L5_2 = L5_1
  if L4_2 <= L5_2 then
    L4_2 = L6_1
    if 0 ~= L4_2 then
      L4_2 = dbg
      L4_2 = L4_2.bridge
      L5_2 = "Database tables are not defined, creating tables! %s %s"
      L6_2 = L6_1
      L7_2 = L5_1
      L4_2(L5_2, L6_2, L7_2)
      L4_2 = 0
      L5_2 = promise
      L5_2 = L5_2.new
      L5_2 = L5_2()
      L6_2 = db
      L6_2 = L6_2.Queries
      L6_2 = L6_2.CREATE_STRUCTURE
      L6_2 = #L6_2
      L7_2 = ipairs
      L8_2 = L8_1
      L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
      for L11_2, L12_2 in L7_2, L8_2, L9_2, L10_2 do
        L13_2 = db
        L13_2 = L13_2.DoesTableExist
        L14_2 = L11_2
        L13_2 = L13_2(L14_2)
        if not L13_2 then
          L13_2 = MySQL
          L13_2 = L13_2.Sync
          L13_2 = L13_2.execute
          L14_2 = L12_2
          L15_2 = {}
          L13_2 = L13_2(L14_2, L15_2)
          if L13_2 then
            L14_2 = dbg
            L14_2 = L14_2.debug
            L15_2 = "Table with ID %s created!"
            L16_2 = L11_2
            L14_2(L15_2, L16_2)
          end
        end
        L4_2 = L4_2 + 1
        if L6_2 <= L4_2 then
          L14_2 = L5_2
          L13_2 = L5_2.resolve
          L13_2(L14_2)
        end
      end
      L7_2 = Citizen
      L7_2 = L7_2.Await
      L8_2 = L5_2
      L7_2(L8_2)
      L2_2 = true
  end
  else
    L4_2 = L7_1
    if L4_2 then
      L4_2 = dbg
      L4_2 = L4_2.bridge
      L5_2 = "You are running older version of rcore_prison, perfoming automatic migration and adding new columns to db!"
      L4_2(L5_2)
      L4_2 = tprint
      L5_2 = L1_1
      L4_2(L5_2)
      L4_2 = [[
            SELECT
                JSON_EXTRACT(data, '$.prisonerName') AS prisonerName,
                JSON_EXTRACT(data, '$.jail_time') AS jail_time,
                OWNER AS owner
            FROM
                rcore_prison
            WHERE
                JSON_EXTRACT(data, '$.state') != 'jailed';
        ]]
      L5_2 = MySQL
      L5_2 = L5_2.Sync
      L5_2 = L5_2.fetchAll
      L6_2 = "SELECT * FROM rcore_prison_transactions"
      L7_2 = {}
      L5_2 = L5_2(L6_2, L7_2)
      if L5_2 then
        L6_2 = next
        L7_2 = L5_2
        L6_2 = L6_2(L7_2)
        if L6_2 then
          L6_2 = pairs
          L7_2 = L5_2
          L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
          for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
            L12_2 = MySQL
            L12_2 = L12_2.Sync
            L12_2 = L12_2.fetchSingle
            L13_2 = "SELECT owner FROM rcore_prison_accounts WHERE account_id = @account_id"
            L14_2 = {}
            L15_2 = L11_2.account_id
            L14_2["@account_id"] = L15_2
            L12_2 = L12_2(L13_2, L14_2)
            if L12_2 then
              L13_2 = LogService
              L13_2 = L13_2.RegisterTransaction
              L14_2 = L11_2.transaction_name
              L15_2 = L11_2.message
              L16_2 = L12_2.owner
              L17_2 = "-"
              L18_2 = "-"
              L13_2 = L13_2(L14_2, L15_2, L16_2, L17_2, L18_2)
              if L13_2 then
                L14_2 = MySQL
                L14_2 = L14_2.Sync
                L14_2 = L14_2.execute
                L15_2 = "DELETE FROM rcore_prison_transactions WHERE transaction_id = @transaction_id"
                L16_2 = {}
                L17_2 = L11_2.transaction_id
                L16_2["@transaction_id"] = L17_2
                L14_2(L15_2, L16_2)
              end
            end
          end
        end
      end
      L6_2 = MySQL
      L6_2 = L6_2.Sync
      L6_2 = L6_2.fetchAll
      L7_2 = L4_2
      L8_2 = {}
      L6_2 = L6_2(L7_2, L8_2)
      if L6_2 then
        L7_2 = next
        L8_2 = L6_2
        L7_2 = L7_2(L8_2)
        if L7_2 then
          L7_2 = pairs
          L8_2 = L6_2
          L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
          for L11_2, L12_2 in L7_2, L8_2, L9_2, L10_2 do
            L13_2 = db
            L13_2 = L13_2.CreateCitizenPeroll
            L14_2 = L12_2.owner
            L15_2 = "IDLE"
            L16_2 = L12_2.jail_time
            L17_2 = L12_2.prisonerName
            L13_2 = L13_2(L14_2, L15_2, L16_2, L17_2)
            if L13_2 then
              L14_2 = db
              L14_2 = L14_2.RemovePerollByOwner
              L15_2 = L12_2.owner
              L14_2(L15_2)
            end
          end
        end
      end
      L7_2 = MySQL
      L7_2 = L7_2.Sync
      L7_2 = L7_2.fetchSingle
      L8_2 = [[
            SELECT COUNT(*)
            AS column_count
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'rcore_prison'
            AND COLUMN_NAME = 'solitary_time'
            AND TABLE_SCHEMA = DATABASE()
        ]]
      L7_2 = L7_2(L8_2)
      if L7_2 then
        L8_2 = L7_2.column_count
        if 0 == L8_2 then
          L8_2 = dbg
          L8_2 = L8_2.bridge
          L9_2 = "Adding column `solitary_time` to `rcore_prison` table."
          L8_2(L9_2)
          L8_2 = MySQL
          L8_2 = L8_2.Sync
          L8_2 = L8_2.execute
          L9_2 = [[
                ALTER TABLE `rcore_prison`
                ADD COLUMN `solitary_time` DATETIME NULL DEFAULT current_timestamp() AFTER `owner`;
            ]]
          L8_2(L9_2)
        end
      end
      L2_2 = true
    else
      L4_2 = L4_1
      L5_2 = L5_1
      if L4_2 >= L5_2 then
        L4_2 = dbg
        L4_2 = L4_2.bridge
        L5_2 = "Database tables are defined, loading data into cache."
        L4_2(L5_2)
        L2_2 = true
      end
    end
  end
  return L2_2
end
IsDatabaseReady = L9_1
L9_1 = CreateThread
function L10_1()
  local L0_2, L1_2
  L0_2 = IsDatabaseReady
  L0_2 = L0_2()
  if L0_2 then
    IS_DATABASE_READY = true
    L1_2 = BridgeLoadedHeartbeat
    L1_2()
  end
end
L11_1 = "sv-migration code name: Phoenix"
L9_1(L10_1, L11_1)
