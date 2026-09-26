"""Source-contract checks for the v3.5.0 enforcement trust boundaries."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class VehicleEnforcementContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.enforcement = source("server/enforcement.lua")
        cls.bolo = source("server/bolo.lua")
        cls.alpr = source("embedded/police/server/alpr.lua")
        cls.clamp_client = source("embedded/police/client/clamp.lua")
        cls.radar = source("embedded/police/client/radar.lua")
        cls.scanner = source("client/vehicle_scanner.lua")
        cls.vehicles = (ROOT.parents[0] / "cm-vehicles/server/main.lua").read_text(encoding="utf-8")

    def test_server_enforcement_authority_includes_duty_capability_permission(self):
        main = source("server/main.lua")
        self.assertIn("authorize(src, 'radar', 'law.radar')", self.enforcement)
        self.assertIn("member.suspended", main)
        self.assertIn("not member.onDuty", main)
        self.assertIn("LawCapabilityEnabled(member.organizationId, capability)", main)
        self.assertIn("member.permissions[tostring(permission or '')] ~= true", main)

    def test_scanner_requires_authoritative_fleet_state_and_access(self):
        self.assertIn("state.cmPoliceFleet", self.bolo)
        self.assertIn("state.cmLegalFleet", self.bolo)
        self.assertIn("CanUseVehicle(src, vehicleId, 'vehicle.drive')", self.bolo)
        self.assertIn("LawAuthorizeEnforcement(src, 'alpr', 'law.alpr')", self.bolo)
        self.assertNotIn("GetDisplayNameFromVehicleModel", self.bolo)

    def test_plate_normalization_and_cached_multi_bolo_lookup(self):
        shared = source("shared/enforcement.lua")
        self.assertIn("function LawNormalizePlate", shared)
        self.assertIn("gsub('%s+', '')", shared)
        self.assertIn("function LawGetActiveBoloMatches", self.bolo)
        self.assertIn("boloCache.generic", self.bolo)
        self.assertIn("boloCache.police", self.bolo)
        self.assertIn("LawRefreshActiveBoloCache()", self.bolo)
        self.assertIn("LawRefreshActiveBoloCache()", source("embedded/police/server/alpr.lua"))

    def test_fixed_alpr_uses_cache_normalizes_and_suppresses_repeat_hits(self):
        self.assertIn("LawNormalizePlate(GetVehicleNumberPlateText(vehicle))", self.alpr)
        self.assertIn("local matches = plate and BoloPlateCache[plate]", self.alpr)
        self.assertIn("local key = tostring(camera.id) .. '|' .. plate .. '|'", self.alpr)
        self.assertIn("AlertCooldownMs", self.alpr)

    def test_clamp_requires_persistent_civilian_and_empty_vehicle(self):
        self.assertIn("state.cmLegalFleet", self.enforcement)
        self.assertIn("state.cmPoliceFleet", self.enforcement)
        self.assertIn("state.cmEmsFleet", self.enforcement)
        self.assertIn("row.owner_type or '') ~= 'character'", self.enforcement)
        self.assertIn("Vehicle must be empty.", self.enforcement)
        self.assertIn("GetEntityRoutingBucket(ped) ~= GetEntityRoutingBucket(vehicle)", self.enforcement)
        self.assertIn("GetSpawnedVehicleInfo(persistentId)", self.enforcement)
        self.assertIn("clampStates[persistentId]", self.enforcement)

    def test_vehicle_identity_stays_id_while_public_registration_resolves_separately(self):
        self.assertIn("function CMVehicles.Server.GetVehicleByLicenseNumber", self.vehicles)
        self.assertIn("WHERE license_number = ?", self.vehicles)
        self.assertIn("vehicleId = tonumber(row.id)", source("server/mdt.lua"))
        self.assertIn("state.cmVehicleId", self.bolo)

    def test_lifecycle_cleanup_contracts_exist(self):
        self.assertIn("onResourceStop", self.radar)
        self.assertIn("characterUnloaded", self.radar)
        self.assertIn("forceDutyCleanup", self.radar)
        self.assertIn("onResourceStop", self.scanner)
        self.assertIn("characterUnloaded", self.scanner)
        self.assertIn("onResourceStop", self.clamp_client)
        self.assertIn("record.vehicle", self.clamp_client)
        self.assertIn("onResourceStop", self.enforcement)


if __name__ == "__main__":
    unittest.main()
