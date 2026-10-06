from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[4]
RESOURCE_DIR = ROOT / 'resources/[core]/cm-garbage'
CONFIG_PATH = RESOURCE_DIR / 'shared/config.lua'
SERVER_PATH = RESOURCE_DIR / 'server/main.lua'
CLIENT_MAIN_PATH = RESOURCE_DIR / 'client/main.lua'
CLIENT_NPC_PATH = RESOURCE_DIR / 'client/npc.lua'
UI_HTML_PATH = RESOURCE_DIR / 'ui/index.html'
UI_CSS_PATH = RESOURCE_DIR / 'ui/style.css'
UI_JS_PATH = RESOURCE_DIR / 'ui/app.js'
MANIFEST_PATH = RESOURCE_DIR / 'fxmanifest.lua'


class CMGarbageContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = CONFIG_PATH.read_text(encoding='utf-8')
        cls.server = SERVER_PATH.read_text(encoding='utf-8')
        cls.client_main = CLIENT_MAIN_PATH.read_text(encoding='utf-8')
        cls.client_npc = CLIENT_NPC_PATH.read_text(encoding='utf-8')
        cls.ui_html = UI_HTML_PATH.read_text(encoding='utf-8')
        cls.ui_css = UI_CSS_PATH.read_text(encoding='utf-8')
        cls.ui_js = UI_JS_PATH.read_text(encoding='utf-8')
        cls.manifest = MANIFEST_PATH.read_text(encoding='utf-8')

    def test_fxmanifest_structure(self):
        """Manifest declares cerulean fx_version, lua54, scripts, UI page and web files."""
        self.assertIn("fx_version 'cerulean'", self.manifest)
        self.assertIn("game 'gta5'", self.manifest)
        self.assertIn("lua54 'yes'", self.manifest)
        self.assertIn("'shared/config.lua'", self.manifest)
        self.assertIn("'client/main.lua'", self.manifest)
        self.assertIn("'client/npc.lua'", self.manifest)
        self.assertIn("'server/main.lua'", self.manifest)
        self.assertIn("ui_page 'ui/index.html'", self.manifest)

    def test_route_and_capacity_consistency(self):
        """Route stop count, bag counts, and capacity are fully aligned."""
        self.assertIn("maxBags = 16", self.config)
        self.assertIn("bagsPerStop = 2", self.config)
        self.assertIn("totalStops = 8", self.config)

        # Confirm 8 concrete route stops exist
        for stop_id in range(1, 9):
            self.assertIn(f"id = {stop_id}", self.config)
            self.assertIn("truckCoords = vector3(", self.config)
            self.assertIn("binCoords = vector3(", self.config)

        # Confirm depot coordinates
        self.assertIn("s_m_y_garbage", self.config)
        self.assertIn("vector4(-321.75, -1545.92, 31.02, 268.5)", self.config) # Foreman
        self.assertIn("vector3(-347.12, -1558.34, 27.50)", self.config)         # Tipping pit

    def test_economy_formula_conforms_to_standard(self):
        """Calculates rewards from expected active work time and fits Beginner Legal band (50k-62.5k)."""
        per_bag_match = re.search(r'perBag\s*=\s*(\d+)', self.config)
        depot_bonus_match = re.search(r'depotBonus\s*=\s*(\d+)', self.config)

        self.assertIsNotNone(per_bag_match, "perBag reward not found in config")
        self.assertIsNotNone(depot_bonus_match, "depotBonus reward not found in config")

        per_bag = int(per_bag_match.group(1))
        depot_bonus = int(depot_bonus_match.group(1))

        # 16 bags per route
        gross_per_route = (per_bag * 16) + depot_bonus
        self.assertEqual(gross_per_route, 7800, "Gross reward per route must equal $7,800")

        # Route duration is ~500s (~8.33 min) = ~7.2 completions per hour
        hourly_rate = gross_per_route * 7.2
        self.assertGreaterEqual(hourly_rate, 50000.0, "Hourly rate must meet Beginner Legal minimum of $50,000/hr")
        self.assertLessEqual(hourly_rate, 62500.0, "Hourly rate must not exceed Beginner Legal ceiling of $62,500/hr")

    def test_server_authority_and_proximity_checks(self):
        """Server enforces bin proximity, hopper proximity, truck proximity to stop, and sequence tokens."""
        # Pickup validation
        self.assertIn("RegisterNetEvent('cm-garbage:server:pickupBag'", self.server)
        self.assertIn("session.activeBagToken ~= nil", self.server)
        self.assertIn("session.totalBagsInTruck >= Config.Capacity.maxBags", self.server)
        self.assertIn("Config.Security.binDistance", self.server)
        self.assertIn("Config.Security.truckMaxDistance", self.server)
        self.assertIn("activeBagToken = token", self.server)

        # Deposit validation
        self.assertIn("RegisterNetEvent('cm-garbage:server:depositBag'", self.server)
        self.assertIn("token ~= session.activeBagToken", self.server)
        self.assertIn("Config.Security.hopperDistance", self.server)
        self.assertIn("session.activeBagToken = nil", self.server)
        self.assertIn("session.stopBagsCollected + 1", self.server)
        self.assertIn("session.totalBagsInTruck + 1", self.server)

        # Unload validation & idempotency lock
        self.assertIn("RegisterNetEvent('cm-garbage:server:unloadTruck'", self.server)
        self.assertIn("Config.Security.unloadDistance", self.server)
        self.assertIn("payoutLocks[src] = true", self.server)
        self.assertIn("session.unloading = true", self.server)
        self.assertIn("payoutLocks[src] = nil", self.server)

    def test_payout_rejection_keeps_load_and_is_retryable(self):
        """When cm-payday rejects, load is NOT cleared, route is NOT advanced, and it is safely retryable."""
        self.assertIn("exports[PAYDAY]:AddPendingCash(src, 'garbage'", self.server)
        self.assertNotIn("addCash(src, totalEarnings", self.server) # No instant cash fallback

        # Check that load clear is inside paydayOk block ONLY
        self.assertIn("if paydayOk then", self.server)
        success_block = self.server.split("if paydayOk then", 1)[1].split("else", 1)[0]
        self.assertIn("session.totalBagsInTruck = 0", success_block)

        # Check else block keeps the load and tells client unload failed
        failure_block = self.server.split("if paydayOk then", 1)[1].split("else", 1)[1].split("end\n    end)", 1)[0]
        self.assertNotIn("session.totalBagsInTruck = 0", failure_block)
        self.assertIn("cm-garbage:client:unloadFailed", failure_block)
        self.assertIn("Payroll registration missing", failure_block)

    def test_clockout_blocked_when_unpaid_load_present(self):
        """Clock-out must refuse if truck contains an unpaid load to prevent silent forfeiture."""
        self.assertIn("session.totalBagsInTruck > 0", self.server)
        cancel_block = self.server.split("RegisterNetEvent('cm-garbage:server:cancelShift'", 1)[1].split("endShift(src", 1)[0]
        self.assertIn("Cannot clock out: your truck has an unpaid load", cancel_block)

    def test_multi_source_and_multi_character_shift_lock(self):
        """Prevents duplicate active shifts for the same source or character ID."""
        start_block = self.server.split("RegisterNetEvent('cm-garbage:server:startShift'", 1)[1].split("Sessions[src] =", 1)[0]
        self.assertIn("Sessions[src]", start_block)
        self.assertIn("otherSession.charId == charId", start_block)

    def test_progression_uses_character_metadata_not_source(self):
        """Progression writes cmGarbageBags and cmGarbageRuns to character metadata."""
        self.assertIn("getMeta(src, 'cmGarbageBags'", self.server)
        self.assertIn("setMeta(src, 'cmGarbageBags'", self.server)
        self.assertIn("setMeta(src, 'cmGarbageRuns'", self.server)
        self.assertIn("api:SetMetadataDetailed", self.server)

    def test_ui_theme_compliance_no_backdrop_filter(self):
        """Strict adherence to CM UI rule: absolutely no backdrop-filter anywhere in CSS."""
        self.assertNotIn('backdrop-filter', self.ui_css.lower())
        self.assertNotIn('-webkit-backdrop-filter', self.ui_css.lower())
        self.assertIn('#00e5ff', self.ui_css) # CM cyan accent
        self.assertIn("nui://cm-ui/web/cm-theme.css", self.ui_html)

    def test_cleanup_idempotency(self):
        """All lifecycle events cleanly terminate shift and delete assigned vehicle."""
        for event_name in ('playerDropped', 'characterUnloaded', 'deathStateChanged', 'onResourceStop'):
            self.assertIn(event_name, self.server)
        self.assertIn('deleteJobVehicle(src)', self.server)
        self.assertIn('DeleteAdminVehicle', self.server)


if __name__ == '__main__':
    unittest.main()

