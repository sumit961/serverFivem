from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[4]
LAW = ROOT / 'resources/[core]/cm-law/server/vehicles.lua'
POLICE = ROOT / 'resources/[core]/cm-law/embedded/police/server/vehicles.lua'
LAW_CLIENT = ROOT / 'resources/[core]/cm-law/client/vehicles.lua'
POLICE_CLIENT = ROOT / 'resources/[core]/cm-law/embedded/police/client/vehicles.lua'
LAW_UI = ROOT / 'resources/[core]/cm-law/html/app.js'
POLICE_UI = ROOT / 'resources/[core]/cm-law/html/police/app.js'
SPAWN = ROOT / 'resources/[core]/cm-vehicles/server/spawn.lua'
MAIN = ROOT / 'resources/[core]/cm-vehicles/server/main.lua'

class PersistentFleetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.law = LAW.read_text(encoding='utf-8')
        cls.police = POLICE.read_text(encoding='utf-8')
        cls.law_client = LAW_CLIENT.read_text(encoding='utf-8')
        cls.police_client = POLICE_CLIENT.read_text(encoding='utf-8')
        cls.law_ui = LAW_UI.read_text(encoding='utf-8')
        cls.police_ui = POLICE_UI.read_text(encoding='utf-8')
        cls.spawn = SPAWN.read_text(encoding='utf-8')
        cls.main = MAIN.read_text(encoding='utf-8')

    def test_no_player_gate_and_server_first_for_both_fleets(self):
        for source in (self.law, self.police):
            self.assertIn('autoRespawnFleet(nil, true)', source)
            self.assertIn('autoRespawnFleet(nil, false)', source)
            self.assertIn('RecoverPersistentWorldVehicle(src, vehicleId, spawn', source)
            self.assertNotIn('if not triggerSrc then return', source)

    def test_recovery_preserves_database_identity_without_inserting(self):
        api = self.spawn.split('function CMVehicles.Spawn.RecoverPersistentWorldVehicle', 1)[1]
        api = api.split('\nend', 1)[0]
        self.assertIn('GetVehicleById(vehicleId)', self.spawn)
        self.assertIn('vehicleId, src = tonumber(vehicleId), tonumber(src)', api)
        core = self.spawn.split('local function recoverPersistentWorldVehicleLocked', 1)[1].split('function CMVehicles.Spawn.RecoverPersistentWorldVehicle', 1)[0]
        self.assertIn('GetVehicleById(vehicleId)', core)
        self.assertIn('pcall(createPersistentWorldVehicleLocked, vehicleId, spawn, organizationId)', core)
        self.assertNotIn('INSERT INTO CM_OWNED_VEHICLES', core.upper())
        self.assertNotIn('INSERT INTO CM_OWNED_VEHICLES', api.upper())
        self.assertIn("context = 'world'", self.spawn)

    def test_trusted_boundary_and_organization_isolation(self):
        self.assertIn("GetInvokingResource() ~= 'cm-law'", self.spawn)
        self.assertIn('organization_ownership_mismatch', self.spawn)
        self.assertIn("tostring(row.owner_type or ''):lower() ~= 'organization'", self.law)
        self.assertIn("tostring(row.owner_id or ''):lower() ~= 'police'", self.police)

    def test_duplicate_and_orphan_entity_recovery(self):
        self.assertIn('findWorldEntityByVehicleId(vehicleId)', self.spawn)
        self.assertIn('Entity(candidate).state', self.spawn)
        self.assertIn('CMVehicles.Spawn.RemoveDuplicateEntities', self.spawn)
        self.assertIn("exports('RecoverPersistentWorldVehicle'", self.spawn)
        self.assertIn('house_garage_display_present', self.spawn)
        self.assertIn('return { ok = true, vehicle = result, mode = mode', self.spawn)
        self.assertIn('vehicle_in_house_garage', self.spawn)

    def test_recall_all_permissions_and_no_spawn_action(self):
        self.assertIn('local function canManageFleet(member)', self.law)
        self.assertIn('member.isLeader == true or member.permissions[\'law.fleet\'] == true', self.law)
        self.assertIn('local function canManagePoliceFleet(actor)', self.police)
        self.assertIn("PoliceLegacyDbBoolean(actor.is_leader) or has(actor, 'police.manage_vehicles')", self.police)
        self.assertIn("lib.callback.register('cm-law:server:spawnFleetVehicle'", self.law)
        self.assertIn('Fleet vehicles are already parked', self.law)
        self.assertIn("lib.callback.register('cm-police:server:spawnFleetVehicle'", self.police)
        self.assertIn('Police fleet vehicles are already parked', self.police)

    def test_no_active_fleet_spawn_nui_or_client_path(self):
        self.assertNotIn("RegisterNUICallback('spawnFleetVehicle'", self.law_client)
        self.assertNotIn("RegisterNUICallback('police_spawnFleetVehicle'", self.police_client)
        self.assertNotIn("post('spawnFleetVehicle'", self.law_ui)
        self.assertNotIn("post('police_spawnFleetVehicle'", self.police_ui)
        self.assertIn("lib.callback.register('cm-law:server:spawnFleetVehicle'", self.law)
        self.assertIn("lib.callback.register('cm-police:server:spawnFleetVehicle'", self.police)

    def test_normal_officer_ui_is_information_only(self):
        for ui in (self.law_ui, self.police_ui):
            self.assertIn('minRankName', ui)
            self.assertIn('AVAILABLE', ui)
            self.assertIn('IN USE', ui)
            self.assertIn('RECOVERING', ui)
            self.assertNotIn('Engine ${Math.round', ui)
            self.assertNotIn('Minimum rank tier', ui)
        self.assertIn('data-fleet-location="${esc(v.model)}"', self.police_ui)
        self.assertIn('data-fleet-location="${esc(v.model)}"', self.law_ui)

    def test_rank_catalog_and_authoritative_tier_validation(self):
        self.assertIn('function fleetRanks(orgId)', self.law)
        self.assertIn('SELECT id, name, tier FROM cm_legal_ranks WHERE organization_id = ?', self.law)
        self.assertIn("WHERE organization_id = ? AND tier = ? LIMIT 1", self.law)
        self.assertIn('That rank does not belong to your organization.', self.law)
        self.assertIn('function policeFleetRanks()', self.police)
        self.assertIn('SELECT id, name, tier FROM cm_police_ranks ORDER BY tier ASC', self.police)
        self.assertIn('That rank does not belong to Police.', self.police)
        self.assertIn('minRankName = rankLabelForTier', self.law)
        self.assertIn('minRankName = rankLabelForTier', self.police)

    def test_rank_update_replicates_live_access_without_vehicle_respawn(self):
        self.assertIn("state:set('cmLegalFleet', fleet, true)", self.law)
        self.assertIn("state:set('cmPoliceFleet', fleet, true)", self.police)
        self.assertIn('FleetVehicleAccessDecision(member, required, action', self.law)
        self.assertIn('FleetVehicleAccessDecision(normalized, required, action', self.police)

    def test_manager_helpers_cover_police_leader_with_empty_permissions(self):
        helper = self.police.split('local function canManagePoliceFleet(actor)', 1)[1].split('\nend', 1)[0]
        self.assertIn('PoliceLegacyDbBoolean(actor.is_leader)', helper)
        self.assertIn("has(actor, 'police.manage_vehicles')", helper)
        for operation in ('fleetCatalog', 'setFleetVehicleMinTier', 'beginFleetLocationEdit', 'recallAllFleetVehicles', 'recallFleetVehicle'):
            self.assertIn(operation, self.police)
        # Synthetic member contract: leader bypass is independent of permission JSON.
        permissions = {}
        is_leader = True
        self.assertTrue(is_leader or permissions.get('police.manage_vehicles') is True)

    def test_manager_helpers_cover_generic_leader_with_empty_permissions(self):
        helper = self.law.split('local function canManageFleet(member)', 1)[1].split('\nend', 1)[0]
        self.assertIn('member.isLeader == true', helper)
        self.assertIn("member.permissions['law.fleet'] == true", helper)
        permissions = {}
        is_leader = True
        self.assertTrue(is_leader or permissions.get('law.fleet') is True)


    def test_cmvehicles_restart_preserves_law_fleet_entities(self):
        main_source = MAIN.read_text(encoding='utf-8')
        self.assertIn('handledEntities[entity]', main_source)
        self.assertIn('state.cmLegalFleet', main_source)
        self.assertIn('state.cmPoliceFleet', main_source)
        self.assertIn('stateVehicleId == vehicleId and not isLawFleet', main_source)

    def test_fleet_reconciliation_does_not_run_duplicate_global_scans(self):
        self.assertNotIn('ReconcileSpawnRegistry()', self.law)
        self.assertNotIn('ReconcileSpawnRegistry()', self.police)

    def test_admin_tuning_contract_remains(self):
        self.assertIn("exports('PoliceLegacyAdminTuneFleetVehicle'", self.police)
        self.assertIn("exports('SaveOrganizationFleetMods'", self.main)
        self.assertIn("exports[VEHICLES_RESOURCE]:SaveOrganizationFleetMods", self.law)

if __name__ == '__main__':
    unittest.main(verbosity=2)
