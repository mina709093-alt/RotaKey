-- 매크로메이커 퀵클릭: 파티창 / 내 초상화 / 공격대창을 마우스로 클릭해서 바로 주문 시전 (Clique 방식)
--
-- 예) 왼쪽 클릭 = 순간 치유, Shift+왼쪽 = 회복의 기원, Ctrl+왼쪽 = 질병 해제, 오른쪽 = 보호막
--     Shift+Ctrl+왼쪽, 가운데 버튼, 마우스 4·5번 버튼 등 모든 조합 가능
--
-- 동작 원리: 블리자드 유닛 창(보안 버튼)에 "shift-type1 = spell / shift-spell1 = 주문" 같은 보안 속성을 붙인다.
--   · 게임 규칙상 전투 중에는 속성을 바꿀 수 없다 → 바꾼 내용은 전투가 끝나면 자동 적용
--   · 원래 값(왼쪽 = 대상 지정, 오른쪽 = 메뉴)은 기억해 두었다가 등록을 지우면 되돌린다
local UI = RotaKeyUI
if not UI then return end
local F, out, Txt, C = UI.F, UI.out, UI.Txt, UI.C

local BUTTONS = {
    { key = "1", label = "왼쪽", click = "LeftButton" },
    { key = "2", label = "오른쪽", click = "RightButton" },
    { key = "3", label = "가운데", click = "MiddleButton" },
    { key = "4", label = "4번 버튼", click = "Button4" },
    { key = "5", label = "5번 버튼", click = "Button5" },
}
local BTN_BY_CLICK, BTN_LABEL = {}, {}
for _, b in ipairs(BUTTONS) do BTN_BY_CLICK[b.click] = b.key; BTN_LABEL[b.key] = b.label end

local KIND_LABEL = { spell = "주문", target = "대상 지정", menu = "메뉴 열기" }
local ATTR_TYPE = { spell = "spell", target = "target", menu = "togglemenu" }

local QDB         -- RotaKeyDB.quick (캐릭터별)
local pending     -- 전투 중이라 적용 못 한 변경이 있음
local touched = {} -- 속성을 붙인 프레임 -> { [속성이름] = 원래 값 }
local applyAt     -- 이 시각에 한 번 적용 (여러 변화를 모아서)

---------------------------------------------------------------------------
-- 조합 표기
---------------------------------------------------------------------------
-- 저장 형식: "alt-ctrl-shift-1" (보안 속성 접두어 순서: alt → ctrl → shift)
local function comboKey(alt, ctrl, shift, btn)
    return (alt and "alt-" or "") .. (ctrl and "ctrl-" or "") .. (shift and "shift-" or "") .. btn
end

local function comboLabel(key)
    local parts = {}
    if key:find("shift%-") then parts[#parts + 1] = "Shift" end
    if key:find("ctrl%-") then parts[#parts + 1] = "Ctrl" end
    if key:find("alt%-") then parts[#parts + 1] = "Alt" end
    parts[#parts + 1] = (BTN_LABEL[key:match("(%d)$")] or "?") .. " 클릭"
    return table.concat(parts, "+")
end

local function splitKey(key) -- "ctrl-shift-1" -> "ctrl-shift-", "1"
    return key:match("^(.-)(%d)$")
end

local function spellNameOf(id)
    return id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or nil
end

local function spellIconOf(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id)
end

---------------------------------------------------------------------------
-- 대상 프레임 찾기
---------------------------------------------------------------------------
-- Blizzard 창은 ClickCastFrames 표가 있으면 스스로 등록한다 (Clique 와 같은 약속)
local clickRegistered = {}
local function hookClickCastTable()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Clique") then return end
    local old = rawget(_G, "ClickCastFrames")
    local t = setmetatable({}, { __newindex = function(_, f, v)
        if v then clickRegistered[f] = true else clickRegistered[f] = nil end
        if QDB then
            if InCombatLockdown() then pending = true else applyAt = GetTime() + 0.5 end
        end
    end })
    if type(old) == "table" then for f, v in pairs(old) do if v then clickRegistered[f] = true end end end
    ClickCastFrames = t
end
hookClickCastTable()

local function category(f)
    if f == PlayerFrame then return "player" end
    if f == TargetFrame then return "target" end
    local n = f.GetName and f:GetName() or ""
    if n:find("Raid") then return "raid" end
    if n:find("Party") then return "party" end
    local p = f.GetParent and f:GetParent()
    local pn = p and p.GetName and p:GetName() or ""
    if pn:find("Raid") then return "raid" end
    if pn:find("Party") then return "party" end
    return nil
end

local function collectFrames()
    local list, seen = {}, {}
    local function add(f)
        if type(f) == "table" and f.SetAttribute and not seen[f] and f.IsProtected and f:IsProtected() then
            local cat = category(f)
            if cat then seen[f] = true; list[#list + 1] = { f = f, cat = cat } end
        end
    end
    add(PlayerFrame)
    add(TargetFrame)
    for i = 1, 5 do add(_G["CompactPartyFrameMember" .. i]) end
    for i = 1, 4 do add(_G["PartyMemberFrame" .. i]) end
    if PartyFrame and PartyFrame.PartyMemberFramePool and PartyFrame.PartyMemberFramePool.EnumerateActive then
        for f in PartyFrame.PartyMemberFramePool:EnumerateActive() do add(f) end
    end
    for i = 1, 40 do add(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do for m = 1, 5 do add(_G["CompactRaidGroup" .. g .. "Member" .. m]) end end
    for f in pairs(clickRegistered) do add(f) end
    return list
end

---------------------------------------------------------------------------
-- 적용
---------------------------------------------------------------------------
local function remember(f, attr)
    local t = touched[f]
    if not t then t = {}; touched[f] = t end
    if t[attr] == nil then t[attr] = f:GetAttribute(attr) or false end
end

local function restoreFrame(f)
    local t = touched[f]
    if not t then return end
    for attr, old in pairs(t) do f:SetAttribute(attr, old or nil) end
    touched[f] = nil
end

local hooked = {}
local function hookLog(f)
    if hooked[f] then return end
    hooked[f] = true
    f:HookScript("PostClick", function(self, button)
        if not QDB or not QDB.log then return end
        local key = comboKey(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), BTN_BY_CLICK[button] or "?")
        local b = QDB.binds[key]
        local unit = self:GetAttribute("unit") or self.unit
        local who = unit and UnitName(unit)
        if issecretvalue and issecretvalue(who) then who = unit end
        local what = b and (b.kind == "spell" and (spellNameOf(b.spell) or b.name or "?") or KIND_LABEL[b.kind]) or "등록 없음 (기본 동작)"
        out(("퀵클릭: |cff4db8e0%s|r → %s  |cff8fa0b0(%s)|r"):format(comboLabel(key), what, tostring(who or unit or "?")))
    end)
end

local function apply()
    if not QDB then return end
    if InCombatLockdown() then
        if not pending then out("전투 중이라 퀵클릭 변경은 전투가 끝나면 적용됩니다.") end
        pending = true
        return
    end
    pending = false
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Clique") then
        if next(QDB.binds) then out("Clique 애드온이 켜져 있어 퀵클릭을 적용하지 않습니다. 둘 중 하나만 사용해 주세요.") end
        return
    end
    local frames = collectFrames()
    local wanted = {}
    for _, e in ipairs(frames) do
        if QDB.frames[e.cat] then wanted[e.f] = true end
    end
    -- 1) 이전에 붙인 속성을 모두 원래대로
    for f in pairs(touched) do restoreFrame(f) end
    -- 2) 지금 등록된 조합을 붙이기
    local count = 0
    for f in pairs(wanted) do
        for key, b in pairs(QDB.binds) do
            local prefix, n = splitKey(key)
            if prefix and ATTR_TYPE[b.kind] then
                remember(f, prefix .. "type" .. n)
                f:SetAttribute(prefix .. "type" .. n, ATTR_TYPE[b.kind])
                if b.kind == "spell" then
                    remember(f, prefix .. "spell" .. n)
                    f:SetAttribute(prefix .. "spell" .. n, spellNameOf(b.spell) or b.name or b.spell)
                end
            end
        end
        if f.RegisterForClicks then f:RegisterForClicks("AnyUp") end
        hookLog(f)
        count = count + 1
    end
    QDB.lastCount = count
end

local function requestApply()
    if InCombatLockdown() then
        if not pending then out("전투 중이라 퀵클릭 변경은 전투가 끝나면 적용됩니다.") end
        pending = true
    else
        apply()
    end
end

---------------------------------------------------------------------------
-- 탭
---------------------------------------------------------------------------
local Q = CreateFrame("Frame", nil, F, "BackdropTemplate")
Q:SetPoint("TOPLEFT", 10, -40)
Q:SetPoint("BOTTOMRIGHT", -10, 10)
Q:Hide()

local tabMacro = UI.makeButton(F, "매크로", 70, 22)
local tabQuick = UI.makeButton(F, "퀵클릭", 70, 22)
tabQuick:SetPoint("TOPRIGHT", -36, -9)
tabMacro:SetPoint("RIGHT", tabQuick, "LEFT", -4, 0)

local function showTab(quick)
    UI.left:SetShown(not quick)
    UI.right:SetShown(not quick)
    Q:SetShown(quick)
    tabMacro:SetActive(not quick)
    tabQuick:SetActive(quick)
    UI.subTitle:SetText(quick and "퀵클릭 (파티창 클릭 시전)" or "스킬 로테이션")
end
tabMacro:SetScript("OnClick", function() showTab(false) end)
tabQuick:SetScript("OnClick", function() showTab(true) end)
tabMacro:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
tabQuick:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
F:HookScript("OnShow", function() showTab(Q:IsShown()) end)

---------------------------------------------------------------------------
-- 퀵클릭 화면
---------------------------------------------------------------------------
local help = Txt(Q, 12, false, true)
help:SetPoint("TOPLEFT", 4, -4)
help:SetWidth(570)
help:SetJustifyH("LEFT")
help:SetText("파티창·내 초상화·공격대창을 클릭하면 퀵슬롯에 없어도 바로 주문이 시전됩니다.\n" ..
    "등록하지 않은 클릭은 원래대로(왼쪽 = 대상 지정, 오른쪽 = 메뉴) 동작합니다.")

-- 적용할 창
local frameLabel = Txt(Q, 13, true)
frameLabel:SetPoint("TOPLEFT", 4, -48)
frameLabel:SetText("적용할 창")
local frameChecks = {}
local FRAME_OPTS = { { "party", "파티창" }, { "player", "내 초상화" }, { "raid", "공격대창" }, { "target", "대상 창" } }
local prevCheck
for i, o in ipairs(FRAME_OPTS) do
    local c = UI.makeCheck(Q, o[2])
    if i == 1 then c:SetPoint("LEFT", frameLabel, "RIGHT", 14, 0) else c:SetPoint("LEFT", prevCheck, "RIGHT", 96, 0) end
    c:SetScript("OnClick", function(self)
        QDB.frames[o[1]] = self:GetChecked() and true or false
        requestApply()
    end)
    frameChecks[o[1]] = c
    prevCheck = c
end

-- 등록 영역
local addBox = CreateFrame("Frame", nil, Q, "BackdropTemplate")
addBox:SetPoint("TOPLEFT", 0, -74)
addBox:SetSize(580, 92)
UI.flat(addBox, C.PANEL)

local addTitle = Txt(addBox, 13, true)
addTitle:SetPoint("TOPLEFT", 8, -8)
addTitle:SetText("새 조합 등록")

local captureBtn = UI.makeButton(addBox, "여기를 원하는 조합으로 클릭", 220, 30)
captureBtn:SetPoint("TOPLEFT", 8, -30)
captureBtn:RegisterForClicks("AnyUp")
local draft = { key = nil, kind = "spell", spell = nil }

local arrow = Txt(addBox, 14, true, true)
arrow:SetPoint("LEFT", captureBtn, "RIGHT", 8, 0)
arrow:SetText("→")

local actSlot = CreateFrame("Button", nil, addBox, "BackdropTemplate")
actSlot:SetSize(36, 36)
actSlot:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
UI.flat(actSlot, { 0, 0, 0 })
actSlot.tex = actSlot:CreateTexture(nil, "ARTWORK")
actSlot.tex:SetPoint("TOPLEFT", 2, -2)
actSlot.tex:SetPoint("BOTTOMRIGHT", -2, 2)
actSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
local actText = Txt(addBox, 12)
actText:SetPoint("LEFT", actSlot, "RIGHT", 8, 0)
actText:SetWidth(150)
actText:SetJustifyH("LEFT")

local addBtn = UI.makeButton(addBox, "등록", 70, 30, true)
addBtn:SetPoint("TOPRIGHT", -8, -30)

local addHint = Txt(addBox, 11, false, true)
addHint:SetPoint("BOTTOMLEFT", 8, 6)
addHint:SetText("주문책에서 주문을 네모 칸에 끌어다 놓기 · 칸을 우클릭하면 주문 → 대상 지정 → 메뉴 열기로 바뀝니다")

local function refreshDraft()
    captureBtn.text:SetText(draft.key and comboLabel(draft.key) or "여기를 원하는 조합으로 클릭")
    if draft.kind == "spell" then
        UI.setTex(actSlot.tex, draft.spell and spellIconOf(draft.spell) or 134400)
        actText:SetText(draft.spell and (spellNameOf(draft.spell) or "?") or "주문을 끌어다 놓으세요")
    else
        actSlot.tex:SetTexture(draft.kind == "target" and 132212 or 134331)
        actText:SetText(KIND_LABEL[draft.kind])
    end
    addBtn:SetUsable(draft.key ~= nil and (draft.kind ~= "spell" or draft.spell ~= nil))
end

captureBtn:SetScript("OnClick", function(_, button)
    local n = BTN_BY_CLICK[button]
    if not n then return end
    draft.key = comboKey(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), n)
    refreshDraft()
end)

local function takeCursorSpell()
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return end
    local id = c or b
    if type(a) == "number" and not c and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(a, Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
        id = (info and info.spellID) or id
    end
    if type(id) ~= "number" then return end
    ClearCursor()
    draft.kind, draft.spell = "spell", id
    refreshDraft()
end
actSlot:SetScript("OnReceiveDrag", takeCursorSpell)
actSlot:SetScript("OnClick", function(_, button)
    if GetCursorInfo() then takeCursorSpell() return end
    if button == "RightButton" then
        draft.kind = (draft.kind == "spell" and "target") or (draft.kind == "target" and "menu") or "spell"
        refreshDraft()
    end
end)

-- 목록
local listTitle = Txt(Q, 13, true)
listTitle:SetPoint("TOPLEFT", 4, -176)
listTitle:SetText("등록된 조합")
local listArea = CreateFrame("Frame", nil, Q, "BackdropTemplate")
listArea:SetPoint("TOPLEFT", 0, -196)
listArea:SetSize(580, 330)
UI.flat(listArea, C.PANEL)

local ROWS, ROW_H = 12, 27
local rows, offset = {}, 0
for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, listArea)
    r:SetSize(560, ROW_H - 2)
    r:SetPoint("TOPLEFT", 10, -6 - (i - 1) * ROW_H)
    r.combo = Txt(r, 12, true)
    r.combo:SetPoint("LEFT", 0, 0)
    r.combo:SetWidth(200)
    r.combo:SetJustifyH("LEFT")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 210, 0)
    r.what = Txt(r, 12)
    r.what:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.what:SetWidth(270)
    r.what:SetJustifyH("LEFT")
    r.del = UI.iconTextButton(r, "X")
    r.del:SetPoint("RIGHT", 0, 0)
    rows[i] = r
end

local emptyText = Txt(listArea, 12, false, true)
emptyText:SetPoint("CENTER")
emptyText:SetText("아직 등록된 조합이 없습니다.\n위에서 조합을 클릭하고 주문을 끌어다 놓은 뒤 [등록]을 누르세요.")

local upBtn = UI.makeButton(Q, "▲", 26, 20)
upBtn:SetPoint("TOPRIGHT", listArea, "BOTTOMRIGHT", -30, -4)
local downBtn = UI.makeButton(Q, "▼", 26, 20)
downBtn:SetPoint("LEFT", upBtn, "RIGHT", 4, 0)

-- 아래: 기능 확인 / 상태
local logBtn = UI.makeButton(Q, "기능 확인: 꺼짐", 130, 26)
logBtn:SetPoint("BOTTOMLEFT", 0, 0)
local statusText = Txt(Q, 11, false, true)
statusText:SetPoint("LEFT", logBtn, "RIGHT", 10, 0)
statusText:SetWidth(430)
statusText:SetJustifyH("LEFT")

local ORDER_BTN = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5 }
local function sortedKeys()
    local keys = {}
    for k in pairs(QDB.binds) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local pa, na = splitKey(a)
        local pb, nb = splitKey(b)
        if na ~= nb then return ORDER_BTN[na] < ORDER_BTN[nb] end
        if #pa ~= #pb then return #pa < #pb end
        return pa < pb
    end)
    return keys
end

local function refreshList()
    if not QDB then return end
    local keys = sortedKeys()
    offset = math.max(0, math.min(offset, #keys - ROWS))
    for i = 1, ROWS do
        local r, key = rows[i], keys[i + offset]
        if key then
            local b = QDB.binds[key]
            r.combo:SetText(comboLabel(key))
            if b.kind == "spell" then
                UI.setTex(r.icon, spellIconOf(b.spell) or 134400)
                r.what:SetText(spellNameOf(b.spell) or b.name or "?")
            else
                r.icon:SetTexture(b.kind == "target" and 132212 or 134331)
                r.what:SetText(KIND_LABEL[b.kind])
            end
            r.del:SetScript("OnClick", function()
                QDB.binds[key] = nil
                requestApply()
                refreshList()
            end)
            r:Show()
        else
            r:Hide()
        end
    end
    emptyText:SetShown(#keys == 0)
    upBtn:SetUsable(offset > 0)
    downBtn:SetUsable(offset + ROWS < #keys)
    local warn = ""
    local b1 = QDB.binds["1"]
    if b1 and b1.kind ~= "target" then warn = "  |cffffb000그냥 왼쪽 클릭에 주문을 넣어서, 창을 클릭해 대상으로 잡을 수 없습니다.|r" end
    statusText:SetText(("%d개 조합 · %s%s"):format(#keys,
        pending and "|cffffb000전투가 끝나면 적용됩니다|r" or (QDB.lastCount and ("창 " .. QDB.lastCount .. "개에 적용됨") or "적용 대기"), warn))
    logBtn:SetActive(QDB.log and true or false)
    logBtn.text:SetText(QDB.log and "기능 확인: 켜짐" or "기능 확인: 꺼짐")
    for k, c in pairs(frameChecks) do c:SetChecked(QDB.frames[k] and true or false) end
end

upBtn:SetScript("OnClick", function() offset = offset - 1; refreshList() end)
downBtn:SetScript("OnClick", function() offset = offset + 1; refreshList() end)
listArea:EnableMouseWheel(true)
listArea:SetScript("OnMouseWheel", function(_, d) offset = offset - d; refreshList() end)
logBtn:SetScript("OnClick", function()
    QDB.log = not QDB.log
    out(QDB.log and "퀵클릭 기능 확인 |cff4db8e0켜짐|r - 창을 클릭할 때마다 조합과 동작을 채팅창에 기록합니다." or "퀵클릭 기능 확인 꺼짐")
    refreshList()
end)
logBtn:SetScript("OnLeave", function(self) self:SetActive(self.active) end)

addBtn:SetScript("OnClick", function()
    if not draft.key then return end
    if draft.kind == "spell" and not draft.spell then return end
    local replaced = QDB.binds[draft.key] ~= nil
    QDB.binds[draft.key] = { kind = draft.kind, spell = draft.kind == "spell" and draft.spell or nil,
        name = draft.kind == "spell" and spellNameOf(draft.spell) or nil }
    out(("퀵클릭 %s: |cff4db8e0%s|r → %s"):format(replaced and "변경" or "등록", comboLabel(draft.key),
        draft.kind == "spell" and (spellNameOf(draft.spell) or "?") or KIND_LABEL[draft.kind]))
    draft.key, draft.spell, draft.kind = nil, nil, "spell"
    requestApply()
    refreshDraft()
    refreshList()
end)

Q:SetScript("OnShow", function() refreshDraft(); refreshList() end)

---------------------------------------------------------------------------
-- 시작 / 다시 적용 시점
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        local DB = UI.DB()
        DB.quick = DB.quick or {}
        QDB = DB.quick
        QDB.binds = QDB.binds or {}
        QDB.frames = QDB.frames or { party = true, player = true, raid = true, target = false }
        pending = false
        applyAt = GetTime() + 2
    elseif e == "PLAYER_REGEN_ENABLED" then
        if pending then
            apply()
            out("전투가 끝나 퀵클릭 설정을 적용했습니다.")
            if Q:IsShown() then refreshList() end
        end
    else
        -- 파티 구성이 바뀌면 새로 생긴 창에도 붙이기 (조금 기다렸다가 한 번에)
        if InCombatLockdown() then
            if QDB and next(QDB.binds) then
                if not pending then out("전투 중에 파티가 바뀌어, 새 파티원 창의 퀵클릭은 전투가 끝나면 연결됩니다.") end
                pending = true
            end
        else
            applyAt = GetTime() + 0.5
        end
    end
end)
ev:SetScript("OnUpdate", function()
    if applyAt and GetTime() >= applyAt then
        applyAt = nil
        if QDB and not InCombatLockdown() then apply() else pending = true end
    end
end)

SLASH_ROTAKEYQUICK1 = "/퀵클릭"
SlashCmdList.ROTAKEYQUICK = function()
    F:Show()
    showTab(true)
end
