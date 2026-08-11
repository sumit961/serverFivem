local L0_1, L1_1, L2_1, L3_1
L0_1 = {}
Dialog = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = assert
  L3_2 = type
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L3_2 = "string" == L3_2
  L4_2 = "Name must be a string"
  L2_2(L3_2, L4_2)
  L2_2 = RegisterNUICallback
  L3_2 = A0_2
  function L4_2(A0_3, A1_3)
    local L2_3, L3_3
    L2_3 = A1_2
    L3_3 = A0_3
    L2_3(L3_3)
    L2_3 = A1_3
    L3_3 = "ok"
    L2_3(L3_3)
  end
  L2_2(L3_2, L4_2)
end
L1_1 = RegisterNuiCallback
L2_1 = "closeDialog"
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = dbg
  L2_2 = L2_2.critical
  L3_2 = "closeDialog"
  L2_2(L3_2)
  L2_2 = SetNuiFocus
  L3_2 = false
  L4_2 = false
  L2_2(L3_2, L4_2)
end
L1_1(L2_1, L3_1)
L1_1 = RegisterNuiCallback
L2_1 = "confirmDialog"
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = dbg
  L2_2 = L2_2.critical
  L3_2 = "confirmDialog"
  L2_2(L3_2)
  L2_2 = SetNuiFocus
  L3_2 = false
  L4_2 = false
  L2_2(L3_2, L4_2)
end
L1_1(L2_1, L3_1)
L1_1 = Dialog
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  L3_2 = promise
  L3_2 = L3_2.new
  L3_2 = L3_2()
  L4_2 = SetNuiFocus
  L5_2 = true
  L6_2 = true
  L4_2(L5_2, L6_2)
  L4_2 = CreateThread
  function L5_2()
    local L0_3, L1_3, L2_3, L3_3
    L0_3 = L0_1
    L1_3 = "dialogState"
    function L2_3(A0_4)
      local L1_4, L2_4, L3_4
      if A0_4 then
        L1_4 = L3_2
        L2_4 = L1_4
        L1_4 = L1_4.resolve
        L3_4 = A0_4
        L1_4(L2_4, L3_4)
      else
        L1_4 = L3_2
        L2_4 = L1_4
        L1_4 = L1_4.resolve
        L3_4 = A0_4
        L1_4(L2_4, L3_4)
      end
    end
    L0_3(L1_3, L2_3)
    L0_3 = FrontendService
    L0_3 = L0_3.SendReactMessage
    L1_3 = "dialog"
    L2_3 = {}
    L2_3.visible = true
    L3_3 = A0_2
    L2_3.title = L3_3
    L3_3 = A1_2
    L2_3.desc = L3_3
    L0_3(L1_3, L2_3)
  end
  L6_2 = "cl-lib-dialog code name: Phoenix"
  L4_2(L5_2, L6_2)
  L4_2 = A2_2
  L5_2 = Citizen
  L5_2 = L5_2.Await
  L6_2 = L3_2
  L5_2, L6_2 = L5_2(L6_2)
  L4_2(L5_2, L6_2)
end
L1_1.Show = L2_1
L1_1 = Dialog
function L2_1()
  local L0_2, L1_2, L2_2
  L0_2 = SetNuiFocus
  L1_2 = false
  L2_2 = false
  L0_2(L1_2, L2_2)
  L0_2 = FrontendService
  L0_2 = L0_2.SendReactMessage
  L1_2 = "dialog"
  L2_2 = {}
  L2_2.visible = false
  L0_2(L1_2, L2_2)
end
L1_1.Hide = L2_1
