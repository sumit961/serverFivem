-- Self-test for the cm-playerdata journaled-money caller gate used by cm-gasstations purchases.
--   lua tests/money_gate_selftest.lua        (run from resources/[core]/cm-gasstations)
-- REAL: MONEY_OP_CALLERS / MoneyOpCallerAllowed are extracted verbatim from cm-playerdata/server/main.lua and executed here.
-- TEST DOUBLE: NormalizeAccount (the only dependency) and the three exports' wiring is asserted against source text.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

local f = assert(io.open(here .. '/../cm-playerdata/server/main.lua', 'rb'))
local src = f:read('a'); f:close()

local a = src:find('local MONEY_OP_CALLERS = {', 1, true)
local b = src:find('local function ValidMoneyOpArgs(', 1, true)
assert(a and b and b > a, 'gate not found in cm-playerdata/server/main.lua')
local chunk = src:sub(a, b - 1) .. '\nreturn MoneyOpCallerAllowed'
local function NormalizeAccount(account) account = tostring(account or ''):lower(); if account == 'cash' or account == 'bank' then return account end return nil end
local allowed = assert(load(chunk, 'gate', 't', { NormalizeAccount = NormalizeAccount, type = type, tostring = tostring }))()

check('billing may use any reference and account', allowed('cm-billing', 'INV-1:debit', 'bank') and allowed('cm-billing', 'anything', 'cash') and allowed('cm-billing', 'x', nil))
check('gasstations may use GAS-PUR- references on cash', allowed('cm-gasstations', 'GAS-PUR-1-1-abc:debit', 'cash') and allowed('cm-gasstations', 'GAS-PUR-1-1-abc:refund', 'CASH'))
check('gasstations may query status for its namespace (no account)', allowed('cm-gasstations', 'GAS-PUR-1-1-abc:debit', nil))
check('gasstations cannot touch the bank account', not allowed('cm-gasstations', 'GAS-PUR-1-1-abc:debit', 'bank'))
check('gasstations cannot touch another resource namespace (billing refs)', not allowed('cm-gasstations', 'INV-1:debit', 'cash') and not allowed('cm-gasstations', 'gas-pur-1', 'cash') and not allowed('cm-gasstations', 'XGAS-PUR-1', 'cash'))
check('gasstations cannot pass a non-string reference', not allowed('cm-gasstations', nil, 'cash') and not allowed('cm-gasstations', {}, 'cash'))
check('cm-store: STORE-PUR- references on cash and bank only', allowed('cm-store', 'STORE-PUR-1-2-3:debit', 'bank') and allowed('cm-store', 'STORE-PUR-1-2-3:refund', 'cash') and allowed('cm-store', 'STORE-PUR-1-2-3:debit', nil))
check('cm-store cannot use other namespaces or unknown accounts', not allowed('cm-store', 'GAS-PUR-1-2-3:debit', 'bank') and not allowed('cm-store', 'CLOTH-PUR-1-2-3:debit', 'bank') and not allowed('cm-store', 'STORE-PUR-1', 'gold'))
check('nv_cloth: CLOTH-PUR- references on cash and bank only', allowed('nv_cloth', 'CLOTH-PUR-1-2-3:debit', 'bank') and allowed('nv_cloth', 'CLOTH-PUR-1-2-3:refund', 'cash'))
check('nv_cloth cannot use other namespaces', not allowed('nv_cloth', 'STORE-PUR-1-2-3:debit', 'bank') and not allowed('nv_cloth', 'GAS-PUR-1-2-3:debit', 'cash') and not allowed('nv_cloth', 'INV-1', 'cash'))
check('gasstations is still cash-only after the gate generalisation', allowed('cm-gasstations', 'GAS-PUR-1:debit', 'cash') and not allowed('cm-gasstations', 'GAS-PUR-1:debit', 'bank'))
check('other resources are denied', not allowed('cm-evil', 'GAS-PUR-1', 'cash') and not allowed('cm-store', 'GAS-PUR-1', 'cash') and not allowed(nil, 'GAS-PUR-1', 'cash'))
check('exports are wired through the gate (no remaining hard-coded cm-billing check)',
    select(2, src:gsub("MoneyOpCallerAllowed%(GetInvokingResource%(%)", '')) == 3 and not src:find("GetInvokingResource%(%) ~= 'cm%-billing'"))

print(('\ncm-playerdata money gate self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
