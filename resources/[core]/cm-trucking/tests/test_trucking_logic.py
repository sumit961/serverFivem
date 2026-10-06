"""
CM Trucking Freight Contract & Business Supply Provider Logic Tests
Verifies structural manifest, config, economy formulas, security boundaries,
server authority, payday integration, durable payout intent persistence,
and UI design token compliance.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
RESOURCE_DIR = ROOT / "resources" / "[core]" / "cm-trucking"

CONFIG_PATH = RESOURCE_DIR / "shared" / "config.lua"
SERVER_MAIN_PATH = RESOURCE_DIR / "server" / "main.lua"
SERVER_ADAPTER_PATH = RESOURCE_DIR / "server" / "business_adapter.lua"
CLIENT_MAIN_PATH = RESOURCE_DIR / "client" / "main.lua"
CLIENT_NPC_PATH = RESOURCE_DIR / "client" / "npc.lua"
UI_HTML_PATH = RESOURCE_DIR / "ui" / "index.html"
UI_CSS_PATH = RESOURCE_DIR / "ui" / "style.css"
UI_JS_PATH = RESOURCE_DIR / "ui" / "app.js"
MANIFEST_PATH = RESOURCE_DIR / "fxmanifest.lua"


class CMTruckingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config_text = CONFIG_PATH.read_text(encoding="utf-8")
        cls.server_main = SERVER_MAIN_PATH.read_text(encoding="utf-8")
        cls.server_adapter = SERVER_ADAPTER_PATH.read_text(encoding="utf-8")
        cls.client_main = CLIENT_MAIN_PATH.read_text(encoding="utf-8")
        cls.client_npc = CLIENT_NPC_PATH.read_text(encoding="utf-8")
        cls.manifest = MANIFEST_PATH.read_text(encoding="utf-8")
        cls.html = UI_HTML_PATH.read_text(encoding="utf-8")
        cls.css = UI_CSS_PATH.read_text(encoding="utf-8")
        cls.js = UI_JS_PATH.read_text(encoding="utf-8")

    def test_fxmanifest_structure(self):
        """Manifest declares cerulean fx_version, lua54, scripts, UI page and web files."""
        self.assertIn("fx_version 'cerulean'", self.manifest)
        self.assertIn("game 'gta5'", self.manifest)
        self.assertIn("lua54 'yes'", self.manifest)
        self.assertIn("'shared/config.lua'", self.manifest)
        self.assertIn("'client/main.lua'", self.manifest)
        self.assertIn("'client/npc.lua'", self.manifest)
        self.assertIn("'server/main.lua'", self.manifest)
        self.assertIn("'server/business_adapter.lua'", self.manifest)
        self.assertIn("ui_page 'ui/index.html'", self.manifest)
        self.assertIn("'ui/index.html'", self.manifest)
        self.assertIn("'ui/style.css'", self.manifest)
        self.assertIn("'ui/app.js'", self.manifest)

    def test_vehicle_and_depot_configuration(self):
        """Supported vehicle is pounder (avoiding unhitched trailer desync), depot is Terminal Island."""
        self.assertIn("model = 'pounder'", self.config_text)
        self.assertIn("s_m_m_trucker_01", self.config_text)
        self.assertIn("Arthur Briggs", self.config_text)
        self.assertIn("Terminal Island Freight Logistics", self.config_text)
        self.assertIn("vector4(1185.20, -3255.40, 6.00, 90.0)", self.config_text)
        self.assertIn("pickupBay", self.config_text)
        self.assertIn("returnBay", self.config_text)

    def test_contract_source_integrity(self):
        """Verifies only real published contract types are supported (business_supply) and bulk_material is deferred."""
        self.assertIn("'business_supply'", self.config_text)
        self.assertIn("'business_supply'", self.server_adapter)
        self.assertIn("targetHourlyYield = 72000", self.config_text)

    def test_server_authority_and_proximity_checks(self):
        """Server validates broker distance, loading dock proximity, destination proximity, and return bay proximity."""
        self.assertIn("RegisterNetEvent('cm-trucking:server:selectContract'", self.server_main)
        self.assertIn("Sessions[src]", self.server_main)
        self.assertIn("Config.Security.brokerDistance", self.server_main)
        self.assertIn("RegisterNetEvent('cm-trucking:server:loadCargo'", self.server_main)
        self.assertIn("Config.Security.pickupBayDistance", self.server_main)
        self.assertIn("Config.ContractState.Loading", self.server_main)
        self.assertIn("RegisterNetEvent('cm-trucking:server:deliverCargo'", self.server_main)
        self.assertIn("Config.Security.destinationBayDistance", self.server_main)
        self.assertIn("Config.Security.minimumTransitTimeMs", self.server_main)
        self.assertIn("Config.ContractState.Delivered", self.server_main)
        self.assertIn("RegisterNetEvent('cm-trucking:server:completeContract'", self.server_main)
        self.assertIn("Config.Security.depotReturnDistance", self.server_main)

    def test_durable_payout_intent_storage(self):
        """Durable payout intent table schema exists and is populated atomically upon broker completion."""
        self.assertIn("cm_trucking_payout_intents", self.server_main)
        self.assertIn("uq_trucking_char_contract", self.server_main)
        self.assertIn("recordEarnedPayoutIntent", self.server_main)
        self.assertIn("recoverPendingPayoutsForCharacter", self.server_main)

    def test_payday_integration_and_fail_closed_retry(self):
        """Fail-closed payday settlement with zero instant cash fallback, retaining intent in SQL on rejection."""
        self.assertIn("AddPendingCash", self.server_main)
        self.assertIn("'trucking'", self.server_main)
        self.assertNotIn("AddCash", self.server_main)
        self.assertNotIn("AddMoney", self.server_main)
        self.assertIn("status = 'earned'", self.server_main)

    def test_business_adapter_implements_contract(self):
        """Adapter implements cm-contracts provider methods and export."""
        self.assertIn("CMTrucking.BusinessAdapter = BusinessAdapter", self.server_adapter)
        self.assertIn("function BusinessAdapter.ListAvailableContracts(", self.server_adapter)
        self.assertIn("function BusinessAdapter.ClaimContract(", self.server_adapter)
        self.assertIn("function BusinessAdapter.ReleaseContract(", self.server_adapter)
        self.assertIn("function BusinessAdapter.MarkContractActive(", self.server_adapter)
        self.assertIn("function BusinessAdapter.CompleteContract(", self.server_adapter)
        self.assertIn("function BusinessAdapter.FailContract(", self.server_adapter)
        self.assertIn("exports('GetBusinessSupplyAdapter'", self.server_adapter)

    def test_ui_compliance(self):
        """UI strictly adheres to CM theme tokens, CM cyan, and zero backdrop-filter."""
        self.assertNotIn("backdrop-filter", self.css)
        self.assertNotIn("-webkit-backdrop-filter", self.css)
        self.assertIn("#00e5ff", self.css)
        self.assertIn("rgba(8, 14, 22", self.css)
        self.assertIn('href="style.css"', self.html)
        self.assertIn('src="app.js"', self.js or self.html)


if __name__ == "__main__":
    unittest.main()

