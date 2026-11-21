-- 매크로메이커 원클릭 낚시: 낚싯대를 들면 화면에 버튼 하나가 생기고, 그 버튼 하나로 던지기와 건지기를 합니다.
--
-- 동작
--   * 던지기 대기: 버튼은 보안 버튼이며, 클릭하면 "낚시" 주문을 씁니다. (사용자의 실제 클릭만으로 시전)
--   * 찌가 떠 있음(낚시 시전 중): 버튼이 클릭을 받지 않게 바꾸고, 마우스가 버튼 위에 있는 동안만
--     왼쪽 클릭을 게임의 "상호작용(INTERACTTARGET)" 단축키로 잠시 지정합니다.
--     그 자리를 클릭하면 게임이 소프트 타겟인 낚시찌와 상호작용해서 건져 올립니다.
--   * 낚시가 끝나면(건짐, 이동, 전투, 낚싯대 해제) 임시 지정을 바로 풀고 던지기 대기로 돌아갑니다.
--
-- 지키는 것
--   * 클릭 없이 자동으로 던지거나 건지지 않습니다. 입질은 게임이 알려 주지 않으므로 사용자가 보고 누릅니다.
--   * 임시 단축키는 마우스가 버튼 위에 있을 때만, 전투가 아닐 때만 겁니다. 전투가 시작되면 즉시 풉니다.
--   * 보안 버튼의 표시/속성 변경은 전투 중에 하지 않고, 전투가 끝난 뒤 정리합니다.
--   * 낚시찌가 소프트 타겟으로 잡히려면 게임의 소프트 타겟 상호작용 설정(SoftTargetInteract)이 켜져 있어야 합니다.
--
--   * 스페이스바: 버튼이 보이는 동안(낚싯대 착용 중)만 버튼과 같은 동작(던지기/건지기). 이 동안 점프는 안 됩니다.
--
-- 명령: /rk 낚시 (켜기/끄기)  /rk 낚시 스페이스 (스페이스바 켜기/끄기)  /rk 낚시 진단  /rk 낚시 위치초기화
-- 설정(캐릭터별 RotaKeyDB): fishOff = true 이면 꺼짐, fishSpaceOff = true 이면 스페이스바 꺼짐, fishPos = 버튼 위치
-- 버튼 이동: Shift 를 누른 채 끌기 (Shift 클릭은 낚시를 하지 않음)

local UI = RotaKeyUI
if not UI then return end
local out, SetF, flat, C = UI.out, UI.SetF, UI.flat, UI.C

local SKILL_FISHING = 356            -- 낚시 전문 기술 번호
local ICON_FISHING = 136245          -- Trade_Fishing 아이콘
local SLOT_MAIN = 16                 -- 주무기 칸
local INTERACT = "INTERACTTARGET"    -- 게임의 상호작용 단축키 명령
local SIZE = 64
local C_REEL = { 1.00, 0.82, 0.10 }  -- 건지기 상태 글자색 (눈에 띄는 노랑)

local isSecret = issecretvalue or function() return false end

local btn                -- 보안 버튼
local bindOwner          -- 임시 단축키 주인 (일반 프레임)
local bound = false      -- 지금 왼쪽 클릭에 상호작용을 걸어 두었는지
local fishing = false    -- 낚시 시전(찌가 떠 있음) 중인지
local pending = false    -- 전투 때문에 미뤄 둔 정리가 있는지
local spellID, spellName -- 쓸 낚시 주문

local function DB() return UI.DB() end
local function On()
    local d = DB()
    return d ~= nil and not d.fishOff
end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

------------------------------------------------------------
-- 판별
------------------------------------------------------------
local function HasPole()
    local id = GetInventoryItemID and GetInventoryItemID("player", SLOT_MAIN)
    if type(id) ~= "number" or isSecret(id) or not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local ok, _, _, _, _, _, class, sub = pcall(C_Item.GetItemInfoInstant, id)
    if not ok then return false end
    local weapon = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    local pole = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
    return class == weapon and sub == pole
end

-- 낚시 전문 기술의 주문 중, 낚시 아이콘을 가진 시전 가능한(지속 효과가 아닌) 주문
local function FindSpell()
    if not (GetProfessions and GetProfessionInfo and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local profs = { GetProfessions() }
    for i = 1, 7 do
        local p = profs[i]
        if p then
            local ok, _, _, _, _, count, offset, line = pcall(GetProfessionInfo, p)
            if ok and line == SKILL_FISHING and type(count) == "number" and type(offset) == "number" then
                for k = 1, count do
                    local ok2, info = pcall(C_SpellBook.GetSpellBookItemInfo, offset + k, bank)
                    local id = ok2 and type(info) == "table" and not info.isPassive and info.spellID
                    if type(id) == "number" then
                        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                        if tex == ICON_FISHING then return id end
                    end
                end
            end
        end
    end
    return nil
end

local function IsFishingSpell(id)
    if type(id) ~= "number" or isSecret(id) then return false end
    if spellID and id == spellID then return true end
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    return tex == ICON_FISHING
end

-- 지금 낚시 시전(찌가 떠 있음) 중인지: 게임의 시전 정보로 확인
local function ChannelIsFishing()
    if not UnitChannelInfo then return false end
    local ok, name, _, tex, _, _, _, _, id = pcall(UnitChannelInfo, "player")
    if not ok or not name or isSecret(name) then return false end
    if IsFishingSpell(id) then return true end
    return tex == ICON_FISHING
end

------------------------------------------------------------
-- 임시 단축키 (찌가 떠 있고, 마우스가 버튼 위에 있을 때만)
------------------------------------------------------------
local function Unbind()
    if bound and bindOwner and not InCombat() then
        ClearOverrideBindings(bindOwner)
        bound = false
    end
end

local function Bind()
    if bound or InCombat() or not bindOwner or type(SetOverrideBinding) ~= "function" then return end
    local ok = pcall(SetOverrideBinding, bindOwner, true, "BUTTON1", INTERACT)
    bound = ok
end

------------------------------------------------------------
-- 스페이스바: 버튼이 보이는 동안(낚싯대 착용 중)만 버튼과 같은 동작
--   던지기 대기 → 버튼 클릭(낚시 주문), 찌가 떠 있음 → 상호작용(건지기)
--   이 동안 스페이스바 점프는 되지 않습니다. 버튼이 사라지거나 전투가 시작되면 바로 원래대로.
------------------------------------------------------------
local spaceOwner         -- 스페이스바 임시 지정 주인 (마우스 임시 지정과 따로 관리)
local spaceMode = nil    -- nil = 지정 없음, "cast" = 던지기, "reel" = 건지기

local function SpaceOn()
    local d = DB()
    return d ~= nil and not d.fishSpaceOff
end

local function SpaceClear()
    if spaceMode and spaceOwner and not InCombat() then
        ClearOverrideBindings(spaceOwner)
        spaceMode = nil
    end
end

local function UpdateSpace()
    if InCombat() or not (btn and spaceOwner) then return end
    local want = nil
    if On() and SpaceOn() and btn:IsShown() then
        want = fishing and "reel" or (spellID and "cast" or nil)
    end
    if want == spaceMode then return end
    SpaceClear()
    if want == "cast" and type(SetOverrideBindingClick) == "function" then
        if pcall(SetOverrideBindingClick, spaceOwner, true, "SPACE", "RotaKeyFishButton", "LeftButton") then spaceMode = "cast" end
    elseif want == "reel" and type(SetOverrideBinding) == "function" then
        if pcall(SetOverrideBinding, spaceOwner, true, "SPACE", INTERACT) then spaceMode = "reel" end
    end
end

------------------------------------------------------------
-- 버튼 모양과 상태
------------------------------------------------------------
local function Paint()
    if not btn then return end
    if fishing then
        btn.label:SetText("건지기!")
        btn.label:SetTextColor(C_REEL[1], C_REEL[2], C_REEL[3])
        btn:SetBackdropBorderColor(C_REEL[1], C_REEL[2], C_REEL[3], 1)
        btn.icon:SetDesaturated(false)
    else
        btn.label:SetText("던지기")
        btn.label:SetTextColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3])
        btn:SetBackdropBorderColor(C.EDGE[1], C.EDGE[2], C.EDGE[3], 1)
        btn.icon:SetDesaturated(spellID == nil)
    end
end

-- 보안 버튼의 속성/표시/마우스 설정 (전투 중이면 미룸)
local function Apply()
    if not btn then return end
    if InCombat() then pending = true return end
    pending = false
    spellID = spellID or FindSpell()
    spellName = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or nil
    if spellID then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)
    else
        btn:SetAttribute("type", nil)
    end
    -- Shift 를 누른 클릭은 아무것도 하지 않음 → Shift+끌기로 버튼을 옮길 때 낚시가 던져지지 않게
    btn:SetAttribute("shift-type1", "")
    local show = On() and HasPole()
    if show then btn:Show() else btn:Hide() end
    -- 찌가 떠 있는 동안에는 버튼이 클릭을 받지 않아야 그 자리 클릭이 상호작용 단축키로 갑니다.
    btn:EnableMouse(not (show and fishing))
    if not (show and fishing) then Unbind() end
    UpdateSpace()
    Paint()
end

local function SetFishing(v)
    if fishing == v then return end
    fishing = v
    Apply()
end

------------------------------------------------------------
-- 만들기
------------------------------------------------------------
local function SavePos()
    local d = DB()
    if not d then return end
    local p, _, rp, x, y = btn:GetPoint()
    d.fishPos = { p, rp, x, y }
end

local function Build()
    if btn then return end
    btn = CreateFrame("Button", "RotaKeyFishButton", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    btn:SetSize(SIZE, SIZE + 18)
    btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    flat(btn, C.BG)
    local d = DB()
    if d and d.fishPos then
        btn:SetPoint(d.fishPos[1], UIParent, d.fishPos[2], d.fishPos[3], d.fishPos[4])
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
    -- 게임 설정 "누를 때 실행"이 있는 클라이언트는 누를 때/뗄 때 모두 받아야 클릭이 먹힙니다.
    local keyDown = false
    if GetCVar then
        local ok, v = pcall(GetCVar, "ActionButtonUseKeyDown")
        keyDown = ok and v ~= nil
    end
    if keyDown then btn:RegisterForClicks("AnyDown", "AnyUp") else btn:RegisterForClicks("AnyUp") end

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOP", btn, "TOP", 0, -4)
    btn.icon:SetSize(SIZE - 8, SIZE - 8)
    btn.icon:SetTexture(ICON_FISHING)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)
    SetF(btn.label, 12, true)

    -- Shift + 끌기로 이동 (그냥 클릭은 낚시)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombat() then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("원클릭 낚시", 1, 1, 1)
        GameTooltip:AddLine("클릭: 낚시 던지기", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("찌가 뜨면 입질 때 같은 자리를 다시 클릭: 건지기", 0.8, 0.8, 0.8)
        if SpaceOn() then
            GameTooltip:AddLine("스페이스바: 클릭과 같은 동작 (낚싯대를 든 동안 점프 대신)", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Shift+끌기: 위치 이동", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()

    bindOwner = CreateFrame("Frame")
    spaceOwner = CreateFrame("Frame")
end

------------------------------------------------------------
-- 감시: 마우스가 버튼 위에 있을 때만 임시 단축키
------------------------------------------------------------
local watch = CreateFrame("Frame")
local acc = 0
watch:SetScript("OnUpdate", function(_, el)
    if not (btn and fishing) then return end
    acc = acc + (el or 0)
    if acc < 0.05 then return end
    acc = 0
    if InCombat() then return end
    -- 혹시 이벤트를 놓쳤으면 시전 정보로 다시 확인
    if not ChannelIsFishing() then
        SetFishing(false)
        return
    end
    if btn:IsShown() and btn:IsMouseOver() then Bind() else Unbind() end
end)

local ev = CreateFrame("Frame")
-- 이 클라이언트에 없는 이벤트가 있어도 파일 실행이 멈추지 않게 하나씩 감싸서 등록합니다.
-- (LEARNED_SPELL_IN_TAB 은 이 클라이언트에 없음: 2026-11-21 확인. 주문 변화는 SPELLS_CHANGED 로 봅니다)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                     "SKILL_LINES_CHANGED", "SPELLS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for _, e in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
    if e == "PLAYER_LOGIN" then
        Build()
        Apply()
    elseif e == "PLAYER_EQUIPMENT_CHANGED" then
        if a1 == SLOT_MAIN or a1 == nil then
            if not HasPole() then fishing = false end
            Apply()
        end
    elseif e == "PLAYER_REGEN_DISABLED" then
        -- 전투 시작: 임시 단축키(마우스, 스페이스바)를 먼저 풉니다 (전투 중에는 바꿀 수 없음)
        if bound and bindOwner then ClearOverrideBindings(bindOwner) bound = false end
        if spaceMode and spaceOwner then ClearOverrideBindings(spaceOwner) spaceMode = nil end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if pending or fishing ~= ChannelIsFishing() then
            fishing = ChannelIsFishing()
            Apply()
        else
            UpdateSpace()
        end
    elseif e == "SKILL_LINES_CHANGED" or e == "SPELLS_CHANGED" then
        -- 주문 목록이 바뀌었을 때(배움, 등급 상승)만 다시 찾습니다. 전투 중이면 Apply 가 미룹니다.
        local before = spellID
        spellID = FindSpell() or before
        if spellID ~= before or (btn and not btn:IsShown() and On() and HasPole()) then Apply() end
    elseif e == "UNIT_SPELLCAST_CHANNEL_START" then
        if IsFishingSpell(a3) or ChannelIsFishing() then SetFishing(true) end
    elseif e == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if fishing then SetFishing(false) end
    end
end)

------------------------------------------------------------
-- 명령
------------------------------------------------------------
local function Diagnose()
    out("원클릭 낚시 진단")
    out("  설정: " .. (On() and "켜짐" or "꺼짐") .. " / 낚싯대 착용: " .. (HasPole() and "예" or "아니오")
        .. " / 전투 중: " .. (InCombat() and "예" or "아니오"))
    local id = spellID or FindSpell()
    out("  낚시 주문: " .. (id and (tostring(spellName or (C_Spell.GetSpellName and C_Spell.GetSpellName(id))) .. " (" .. id .. ")") or "찾지 못함 (낚시를 배웠는지 확인)"))
    local soft = GetCVar and GetCVar("SoftTargetInteract")
    out("  소프트 타겟 상호작용(SoftTargetInteract): " .. tostring(soft)
        .. ((soft == "0" or soft == nil) and " → 꺼져 있으면 찌를 건질 수 없습니다" or ""))
    local k1, k2 = GetBindingKey(INTERACT)
    out("  게임의 상호작용 단축키: " .. tostring(k1 or "없음") .. (k2 and (", " .. k2) or ""))
    out("  상태: " .. (fishing and "찌가 떠 있음(건지기)" or "던지기 대기") .. " / 임시 클릭 지정: " .. (bound and "걸려 있음" or "없음")
        .. " / 버튼: " .. ((btn and btn:IsShown()) and "보임" or "숨김"))
    out("  스페이스바: 설정 " .. (SpaceOn() and "켜짐" or "꺼짐") .. " / 지금 "
        .. (spaceMode == "cast" and "던지기" or spaceMode == "reel" and "건지기" or "지정 없음(점프)"))
end

UI.FishCommand = function(arg)
    arg = arg or ""
    local d = DB()
    if not d then return end
    if arg == "진단" or arg == "diag" then
        Diagnose()
    elseif arg == "스페이스" or arg == "space" then
        d.fishSpaceOff = not d.fishSpaceOff or nil
        UpdateSpace()
        out("원클릭 낚시 스페이스바 " .. (d.fishSpaceOff and "꺼짐 (점프 그대로)" or "켜짐 (낚싯대를 든 동안 던지기/건지기)")
            .. (InCombat() and " (전투가 끝나면 적용)" or ""))
    elseif arg == "위치초기화" or arg == "reset" then
        if InCombat() then out("전투 중에는 할 수 없습니다.") return end
        d.fishPos = nil
        if btn then btn:ClearAllPoints() btn:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
        out("원클릭 낚시 버튼 위치를 처음으로 되돌렸습니다.")
    else
        d.fishOff = not d.fishOff or nil
        Apply()
        out("원클릭 낚시 " .. (d.fishOff and "꺼짐" or "켜짐") .. (InCombat() and " (전투가 끝나면 적용)" or ""))
    end
end
