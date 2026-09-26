"""Source-level security contracts for the shared Law impound workflow."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "embedded/police/server/impound.lua").read_text(encoding="utf-8")
CLIENT = (ROOT / "embedded/police/client/impound.lua").read_text(encoding="utf-8")
QUICKMENU = (ROOT / "embedded/police/client/quickmenu.lua").read_text(encoding="utf-8")
LAW = (ROOT / "server/main.lua").read_text(encoding="utf-8")
VEHICLE_MDT = (ROOT / "server/mdt.lua").read_text(encoding="utf-8")


class ImpoundContractTests(unittest.TestCase):
    def test_shared_law_authority_is_used(self):
        self.assertIn("AuthorizeEnforcement(src, 'impound', 'law.impound')", SERVER)
        self.assertIn("member.permissions[tostring(permission or '')] ~= true", LAW)
        self.assertIn("member.onDuty", LAW)
        self.assertIn("member.suspended", LAW)
        self.assertIn("LawCapabilityEnabled(member.organizationId, capability)", LAW)

    def test_persistent_vehicle_identity_is_authoritative(self):
        self.assertIn("state.cmVehicleId", SERVER)
        self.assertIn("GetVehicleById(stateVehicleId)", SERVER)
        self.assertIn("GetSpawnedVehicleInfo(stateVehicleId)", SERVER)
        self.assertNotIn("GetVehicleByPlate(plate)", SERVER)

    def test_tow_session_binds_actor_org_and_both_vehicle_ids(self):
        self.assertIn("actorCid = actorCid, organizationId = organizationId, towVehicleId = towVehicleId", SERVER)
        self.assertIn("vehicleId = tonumber(targetRow.id)", SERVER)
        self.assertIn("session.vehicleId", SERVER)
        self.assertIn("session.towVehicleId", SERVER)
        self.assertIn("TowSessionTtl", SERVER)
        self.assertIn("cancelTow", SERVER)

    def test_completion_lock_active_record_and_occupants_are_checked(self):
        self.assertIn("local ImpoundLocks = {}", SERVER)
        self.assertIn("ImpoundLocks[session.vehicleId]", SERVER)
        self.assertIn("released_at IS NULL LIMIT 1", SERVER)
        self.assertIn("rowOccupied(veh)", SERVER)

    def test_release_checks_owner_and_serializes_payment(self):
        self.assertIn("local ReleaseLocks = {}", SERVER)
        self.assertIn("ReleaseLocks[vehicleId]", SERVER)
        self.assertIn("row.owner_character_id", SERVER)
        self.assertIn("TransitionVehicleLocation(vehicleId, 'STORED'", SERVER)
        self.assertIn("vehicle_impound_release_refund", SERVER)

    def test_fleet_targets_and_tow_vehicle_access_fail_closed(self):
        self.assertIn("cmPoliceFleet", SERVER)
        self.assertIn("cmLegalFleet", SERVER)
        self.assertIn("cmEmsFleet", SERVER)
        self.assertIn("CanUseVehicle(src, towVehicleId, 'vehicle.drive')", SERVER)
        self.assertIn("owner_type or ''):lower() ~= 'organization'", SERVER)

    def test_j_menu_calls_shared_function_not_chat_command(self):
        self.assertIn("onSelect = PoliceToggleTow", QUICKMENU)
        self.assertNotIn("ExecuteCommand('policetow')", QUICKMENU)
        self.assertNotIn("ExecuteCommand('policeimpound')", CLIENT)
        self.assertIn("RegisterCommand('policetow', PoliceToggleTow", CLIENT)
        self.assertIn("RegisterCommand('policeimpound', PoliceDeliverImpound", CLIENT)

    def test_dropoff_requires_matching_organization(self):
        self.assertIn("location.organizationId or '') == tostring(organizationId)", SERVER)
        self.assertIn("nearDropoff(veh, organizationId)", SERVER)
        self.assertIn("GetFacilityLocation(orgId, 'impound')", SERVER)

    def test_generic_mdt_reads_shared_ledger_and_evidence(self):
        self.assertIn("cm_police_impound_evidence", VEHICLE_MDT)
        self.assertIn("i.organization_id", VEHICLE_MDT)
        self.assertIn("organizationId = tostring(impound.organization_id", VEHICLE_MDT)


if __name__ == "__main__":
    unittest.main()
