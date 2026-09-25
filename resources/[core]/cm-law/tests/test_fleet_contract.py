from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[4]
LAW = ROOT / 'resources/[core]/cm-law/server/vehicles.lua'
POLICE = ROOT / 'resources/[core]/cm-law/embedded/police/server/vehicles.lua'
SPAWN = ROOT / 'resources/[core]/cm-vehicles/server/spawn.lua'
MAIN = ROOT / 'resources/[core]/cm-vehicles/server/main.lua'

class PersistentFleetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.law = LAW.read_text(encoding='utf-8')
        cls.police = POLICE.read_text(encoding='utf-8')
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
        self.assertIn('actor.isLeader or actor.permissions[\'law.fleet\'] == true', self.law)
        self.assertIn("PoliceLegacyDbBoolean(actor.is_leader) or has(actor, 'police.manage_vehicles')", self.police)
        self.assertIn("lib.callback.register('cm-law:server:spawnFleetVehicle'", self.law)
        self.assertIn('Fleet vehicles are already parked', self.law)
        self.assertIn("lib.callback.register('cm-police:server:spawnFleetVehicle'", self.police)
        self.assertIn('Police fleet vehicles are already parked', self.police)


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
