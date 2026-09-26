from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[4]
LAW = ROOT / 'resources/[core]/cm-law/server/main.lua'
LAW_CONFIG = ROOT / 'resources/[core]/cm-law/shared/config.lua'
POLICE = ROOT / 'resources/[core]/cm-law/embedded/police/server/main.lua'
POLICE_CONFIG = ROOT / 'resources/[core]/cm-law/embedded/police/shared/config.lua'
ADMIN_ORGS = ROOT / 'resources/[core]/cm-admin/server/organizations.lua'
ADMIN_MAIN = ROOT / 'resources/[core]/cm-admin/server/main.lua'
ADMIN_UI = ROOT / 'resources/[core]/cm-admin/ui/main.js'


class AdminOrganizationRegistrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.law = LAW.read_text(encoding='utf-8')
        cls.law_config = LAW_CONFIG.read_text(encoding='utf-8')
        cls.police = POLICE.read_text(encoding='utf-8')
        cls.police_config = POLICE_CONFIG.read_text(encoding='utf-8')
        cls.admin_orgs = ADMIN_ORGS.read_text(encoding='utf-8')
        cls.admin_main = ADMIN_MAIN.read_text(encoding='utf-8')
        cls.admin_ui = ADMIN_UI.read_text(encoding='utf-8')

    def test_generic_law_registers_when_ready_and_when_admin_starts(self):
        helper = self.law.split('local function registerCentralOrganizations()', 1)[1]
        helper = helper.split('\nend', 1)[0]
        self.assertIn('if not ready then', helper)
        self.assertIn("GetResourceState(Config.AdminResource) ~= 'started'", helper)
        self.assertIn('for orgId, org in pairs(Config.Organizations) do', helper)
        self.assertIn("RegisterOrganization({", helper)
        self.assertIn('if resource == Config.AdminResource then', self.law)
        self.assertIn('SetTimeout(250, registerCentralOrganizations)', self.law)
        manifest = (ROOT / 'resources/[core]/cm-law/fxmanifest.lua').read_text(encoding='utf-8')
        dependencies = manifest.split('dependencies {', 1)[1].split('}', 1)[0]
        self.assertNotIn("'cm-admin'", dependencies)
        prison_manifest = (ROOT / 'resources/[core]/cm-prison/fxmanifest.lua').read_text(encoding='utf-8')
        prison_dependencies = prison_manifest.split('dependencies {', 1)[1].split('}', 1)[0]
        self.assertNotIn("'cm-admin'", prison_dependencies)
        self.assertIn('registerCentralOrganizations()', self.law.split('CreateThread(function()', 1)[-1])
        for org_id in ('sahp', 'sheriff', 'fib', 'army'):
            self.assertIn(f'{org_id} = {{', self.law_config)

    def test_police_registration_is_ready_gated_and_repeats_on_admin_start(self):
        helper = self.police.split('registerPoliceCentralOrganization = function()', 1)[1]
        helper = helper.split('\nend', 1)[0]
        self.assertIn('not ready', helper)
        self.assertIn("GetResourceState(PoliceConfig.AdminResource) ~= 'started'", helper)
        self.assertIn('id = PoliceConfig.OrganizationId', helper)
        self.assertIn("PoliceConfig.OrganizationId = 'police'", self.police_config)
        self.assertIn('if resource == PoliceConfig.AdminResource then', self.police)
        self.assertIn('SetTimeout(250, function()', self.police)
        self.assertIn("if GetResourceState(PoliceConfig.AdminResource) ~= 'started' then return nil, false end", self.police)
        self.assertIn('registerPoliceCentralOrganization()', self.police)
        self.assertIn("print('[cm-law] registered Police with cm-admin')", helper)

    def test_police_central_api_mapping_and_canonical_ids(self):
        expected = (
            'summary = \'PoliceLegacyGetOrganizationSummary\'',
            'assignLeader = \'PoliceCentralAdminAssignLeader\'',
            'removeLeader = \'PoliceCentralAdminRemoveLeader\'',
            'getFleet = \'PoliceLegacyAdminGetFleet\'',
            'configureFleet = \'PoliceLegacyAdminConfigureFleetVehicle\'',
            'resetFleet = \'PoliceLegacyAdminResetFleetLocation\'',
            'beginFleetPlacement = \'PoliceLegacyAdminBeginFleetPlacement\'',
            'recallFleetVehicle = \'PoliceLegacyAdminRecallFleetVehicle\'',
            'recallAllFleetVehicles = \'PoliceLegacyAdminRecallAllFleetVehicles\'',
            'tuneFleetVehicle = \'PoliceLegacyAdminTuneFleetVehicle\'',
        )
        for mapping in expected:
            self.assertIn(mapping, self.police)
        self.assertNotIn("id = 'lspd'", self.police)
        self.assertIn("sahp = {", self.law_config)
        self.assertIn("sheriff = {", self.law_config)
        self.assertIn("fib = {", self.law_config)
        self.assertIn("army = {", self.law_config)

    def test_registration_overwrites_canonical_registry_entry_idempotently(self):
        register = self.admin_orgs.split('local function registerOrganization(org)', 1)[1]
        register = register.split('\nend', 1)[0]
        self.assertIn('local orgId = normalizeOrgId(org.id)', register)
        self.assertIn('organizations[orgId] = {', register)
        self.assertIn('orgOwner[orgId] =', register)
        self.assertIn("return tostring(orgId or ''):match('^%s*(.-)%s*$'):lower()", self.admin_orgs)
        self.assertNotIn("organizations[tostring(orgId or '')]", self.admin_orgs)
        self.assertIn("if owner == resourceName then unregisterOrganization(id) end", self.admin_orgs)

    def test_generic_and_police_assignment_argument_order_and_permissions(self):
        assign = self.admin_orgs.split('function CMOrganizations.assignLeader(src, orgId, targetCid)', 1)[1]
        assign = assign.split('\nend', 1)[0]
        self.assertIn('](src, targetCid, org.id)', assign)
        self.assertIn("if not hasPerm(src, 'orgs.manage')", assign)
        generic = self.law.split('local function assignLeader(src, targetCid, orgId)', 1)[1]
        generic = generic.split('\nend', 1)[0]
        self.assertIn("exports('AdminAssignLeader', assignLeader)", self.law)
        self.assertIn("orgId = validOrgId(orgId)", generic)
        police = self.police.split('local function doCentralAdminAssignLeader(src, targetCid, orgId)', 1)[1]
        police = police.split('\nend', 1)[0]
        self.assertIn('exports(\'PoliceCentralAdminAssignLeader\', doCentralAdminAssignLeader)', self.police)
        self.assertIn("policePermission(src, 'orgs.manage')", police)
        self.assertIn("PoliceConfig.AdminPermission = 'police.admin.manage'", self.police_config)
        self.assertIn("PoliceConfig.AdminPermission", self.police)

    def test_missing_org_has_one_clean_result_and_duplicate_results_are_ignored(self):
        self.assertIn('Organization is not currently registered. Refresh CM Admin and try again.', self.admin_orgs)
        self.assertNotIn("return false, 'Unknown organization.'", self.admin_orgs)
        assignment = self.admin_main.split("if action == 'orgsAssignLeader' then", 1)[1]
        assignment = assignment.split("if action == 'orgsRemoveLeader' then", 1)[0]
        self.assertEqual(assignment.count('sendOrgActionResult('), 2)
        self.assertNotIn('notify(src,', assignment)
        self.assertIn('if (!pending) return;', self.admin_ui)
        self.assertIn('pendingOrgLeaderActions.delete(String(result.requestId));', self.admin_ui)


if __name__ == '__main__':
    unittest.main()
