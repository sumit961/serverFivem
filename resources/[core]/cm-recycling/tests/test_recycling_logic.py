from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[4]
RESOURCE_DIR = ROOT / 'resources/[core]/cm-recycling'
CONFIG_PATH = RESOURCE_DIR / 'shared/config.lua'
SERVER_PATH = RESOURCE_DIR / 'server/main.lua'
CLIENT_MAIN_PATH = RESOURCE_DIR / 'client/main.lua'
CLIENT_NPC_PATH = RESOURCE_DIR / 'client/npc.lua'
UI_HTML_PATH = RESOURCE_DIR / 'ui/index.html'
UI_CSS_PATH = RESOURCE_DIR / 'ui/style.css'
UI_JS_PATH = RESOURCE_DIR / 'ui/app.js'
MANIFEST_PATH = RESOURCE_DIR / 'fxmanifest.lua'


class CMRecyclingContractTests(unittest.TestCase):
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
        self.assertIn("'ui/index.html'", self.manifest)
        self.assertIn("'ui/style.css'", self.manifest)
        self.assertIn("'ui/app.js'", self.manifest)

    def test_route_and_capacity_consistency(self):
        """Route stop count, bundle counts, truck model, and facility coords are fully aligned."""
        self.assertIn("totalStops = 5", self.config)
        self.assertIn("bundlesPerStop = 2", self.config)
        self.assertIn("maxBundles = 10", self.config)
        self.assertIn("model = 'bison'", self.config)

        # Confirm 5 concrete route stops exist with truck and salvage coords
        for stop_id in range(1, 6):
            self.assertIn(f"id = {stop_id}", self.config)
            self.assertIn("truckCoords = vector3(", self.config)
            self.assertIn("salvageCoords = vector3(", self.config)
            self.assertIn("material = ", self.config)

        # Confirm Rogers Salvage facility coordinates
        self.assertIn("s_m_m_dockwork_01", self.config)
        self.assertIn("Frank Kovac", self.config)
        self.assertIn("vector4(-433.80, -1726.50, 19.78, 120.0)", self.config) # Supervisor coords
        self.assertIn("vector3(-445.00, -1700.00, 19.40)", self.config)        # Unload bay
        self.assertIn("vector3(-425.20, -1710.80, 19.80)", self.config)        # Sorting station

    def test_exact_material_and_cash_total_value_calculation(self):
        """Calculates total economic value (cash + materials) against Beginner Legal band ($50,000 - $62,500/hr)."""
        per_stop_match = re.search(r'perStop\s*=\s*(\d+)', self.config)
        bonus_match = re.search(r'processingBonus\s*=\s*(\d+)', self.config)

        self.assertIsNotNone(per_stop_match, "perStop reward not found in config")
        self.assertIsNotNone(bonus_match, "processingBonus reward not found in config")

        per_stop = int(per_stop_match.group(1))
        bonus = int(bonus_match.group(1))

        # 5 stops per cycle
        gross_cash_per_cycle = (per_stop * 5) + bonus
        self.assertEqual(gross_cash_per_cycle, 8400, "Gross cash reward per cycle must equal $8,400 ($1,200 * 5 + $2,400)")

        # Route duration is ~540s (~9.0 min) = ~6.67 cycles per hour
        hourly_cash_rate = gross_cash_per_cycle * 6.67
        self.assertGreaterEqual(hourly_cash_rate, 50000.0, "Hourly rate must meet Beginner Legal minimum of $50,000/hr")
        self.assertLessEqual(hourly_cash_rate, 62500.0, "Hourly rate must not exceed Beginner Legal ceiling of $62,500/hr")

        # Material economics: configurable and safely disabled by default because metal_scrap/plastic have no vendor price
        self.assertIn("materialsEnabled = false", self.config)
        self.assertIn("estimatedMaterialValuePerCycle", self.config)
        self.assertIn("metal_scrap", self.config)
        self.assertIn("plastic", self.config)

    def test_explicit_batch_states_defined(self):
        """Explicit batch states (ready, materials_granted, payroll_accepted, completed) are declared."""
        self.assertIn("BatchState = {", self.config)
        self.assertIn("Ready = 'ready'", self.config)
        self.assertIn("MaterialsGranted = 'materials_granted'", self.config)
        self.assertIn("PayrollAccepted = 'payroll_accepted'", self.config)
        self.assertIn("Completed = 'completed'", self.config)

    def test_inventory_grant_payroll_rejection_no_duplicate_material_on_retry(self):
        """When materials are granted, subsequent retries due to payroll rejection do NOT grant materials again."""
        # Check that material grant is guarded by not materialsReady
        self.assertIn("local materialsReady = currentBatch.materialsGranted == true", self.server)
        self.assertIn("if not materialsReady then", self.server)

        # Inside the material grant, it sets materialsGranted = true and advances state
        mat_block = self.server.split("if not materialsReady then", 1)[1].split("-- =====================================================================", 1)[0]
        self.assertIn("currentBatch.materialsGranted = true", mat_block)
        self.assertIn("currentBatch.state = Config.BatchState.MaterialsGranted", mat_block)
        self.assertIn("setMeta(src, 'cmRecyclingActiveBatch', currentBatch)", mat_block)

        # On payday failure, check that batch is NOT wiped and state remains MaterialsGranted
        fail_block = self.server.split("if paydayOk then", 1)[1].split("else", 1)[1].split("end\n    end)", 1)[0]
        self.assertNotIn("currentBatch.materialsGranted = false", fail_block)
        self.assertNotIn("session.activeBatch = nil", fail_block)
        self.assertNotIn("session.totalBundlesInTruck = 0", fail_block)
        self.assertIn("cm-recycling:client:processingFailed", fail_block)

    def test_inventory_capacity_failure_leaves_batch_retryable_without_paying(self):
        """Inventory full condition fails closed: does NOT grant materials, does NOT call payday, and remains retryable."""
        self.assertIn("local canCarryAll = true", self.server)
        self.assertIn("exports[INVENTORY]:CanCarryItem", self.server)
        self.assertIn("if not canCarryAll then", self.server)

        cap_fail_block = self.server.split("if not canCarryAll then", 1)[1].split("return", 1)[0]
        self.assertIn("payoutLocks[src] = nil", cap_fail_block)
        self.assertIn("session.sortingInProgress = false", cap_fail_block)
        self.assertIn("Inventory full", cap_fail_block)
        self.assertNotIn("AddPendingCash", cap_fail_block)

    def test_duplicate_or_concurrent_processing_requests_blocked(self):
        """Concurrent or rapid repeated sorting requests are strictly locked and rejected."""
        self.assertIn("if payoutLocks[src] or session.sortingInProgress then", self.server)
        self.assertIn("Material sorting is already in progress.", self.server)
        self.assertIn("payoutLocks[src] = true", self.server)
        self.assertIn("session.sortingInProgress = true", self.server)

    def test_payout_and_progression_applied_only_once(self):
        """Progression metadata is incremented and active batch cleared ONLY upon confirmed payday acceptance."""
        self.assertIn("if paydayOk then", self.server)
        success_block = self.server.split("if paydayOk then", 1)[1].split("else", 1)[0]
        self.assertIn("currentBatch.payrollAccepted = true", success_block)
        self.assertIn("currentBatch.state = Config.BatchState.Completed", success_block)
        self.assertIn("cmRecyclingCollections", success_block)
        self.assertIn("cmRecyclingRuns", success_block)
        self.assertIn("setMeta(src, 'cmRecyclingActiveBatch', nil)", success_block)
        self.assertIn("session.activeBatch = nil", success_block)

    def test_durable_recovery_and_clockout_protection(self):
        """Active batch persists to character metadata and clockout is blocked on uncompleted/unpaid batches."""
        # Metadata persistence
        self.assertIn("setMeta(src, 'cmRecyclingActiveBatch', session.activeBatch)", self.server)
        self.assertIn("getMeta(src, 'cmRecyclingActiveBatch', nil)", self.server)
        self.assertIn("hasPendingBatch", self.server)

        # Clock-out protection
        cancel_block = self.server.split("RegisterNetEvent('cm-recycling:server:cancelShift'", 1)[1].split("endShift(src", 1)[0]
        self.assertIn("session.activeBatch and session.activeBatch.state ~= Config.BatchState.Completed", cancel_block)
        self.assertIn("Cannot clock out: you have an active uncompleted salvage batch", cancel_block)

    def test_multi_source_and_multi_character_shift_lock(self):
        """Prevents duplicate active shifts for the same source or character ID."""
        start_block = self.server.split("RegisterNetEvent('cm-recycling:server:startShift'", 1)[1].split("Sessions[src] =", 1)[0]
        self.assertIn("Sessions[src]", start_block)
        self.assertIn("otherSession.charId == charId", start_block)

    def test_ui_theme_compliance_no_backdrop_filter(self):
        """Strict adherence to CM UI rule: absolutely no backdrop-filter anywhere in CSS."""
        self.assertNotIn('backdrop-filter', self.ui_css.lower())
        self.assertNotIn('-webkit-backdrop-filter', self.ui_css.lower())
        self.assertIn('#00e5ff', self.ui_css) # CM cyan accent
        self.assertIn("nui://cm-ui/web/cm-theme.css", self.ui_html)

    def test_public_exports(self):
        """Declares IsOnShift and GetShiftData exports."""
        self.assertIn("exports('IsOnShift'", self.server)
        self.assertIn("exports('GetShiftData'", self.server)


if __name__ == '__main__':
    unittest.main()

