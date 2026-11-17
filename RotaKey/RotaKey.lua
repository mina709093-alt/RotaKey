-- 매크로메이커 (RotaKey) 0.11.0
-- 그룹별 스킬 로테이션을 퀵슬롯 매크로 아이콘 하나로 실행
-- /castsequence reset=target/combat 매크로 (대상이 바뀌거나 전투가 끝나면 1번부터)

local ADDON = "RotaKey"
local MAX_SLOTS = 10
local SLOTS_PER_ROW = 5
local MACRO_LIMIT = 255
local DEFAULT_ICON = 134400 -- 물음표

local isSecret = issecretvalue or function() return false end
local DB
local refreshStatus = function() end
local selected = 1

local function out(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4db8e0[매크로메이커]|r " .. tostring(msg))
end

------------------------------------------------------------
-- 데이터
------------------------------------------------------------
local function newGroup(n)
    local id = DB.nextId
    DB.nextId = DB.nextId + 1
    return {
        id = id,
        name = "그룹 " .. n,
        macroName = "로테" .. id,
        icon = nil,
        slots = { 0, 0 },
        attack = true,
    }
end

local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = (type(v) == "table") and copyTable(v) or v end
    return c
end

local function spellName(id)
    if not id or id == 0 then return nil end
    return C_Spell.GetSpellName and C_Spell.GetSpellName(id)
end

local function spellIcon(id)
    if not id or id == 0 then return nil end
    return C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
end

local function filledSpells(g)
    local t = {}
    for _, id in ipairs(g.slots) do
        local n = spellName(id)
        if n then t[#t + 1] = { id = id, name = n } end
    end
    return t
end

-- 조건부 스킬 키 (shift / ctrl / alt)
local MOD_LABEL = { shift = "Shift", ctrl = "Ctrl", alt = "Alt" }
local MOD_ORDER = { "shift", "ctrl", "alt" }

-- 조건부 스킬 (그룹당 최대 3개, 각각 Shift / Ctrl / Alt)
local function isCond(g, i) return g.conds and g.conds[i] ~= nil end

local function condList(g)
    local t = {}
    if not g.conds or g.custom then return t end -- 상세 그룹은 조건부 아이콘 대신 줄에서 직접 처리
    for i, id in ipairs(g.slots) do
        local m = g.conds[i]
        local n = m and spellName(id)
        if n then t[#t + 1] = { id = id, name = n, slot = i, mod = m } end
    end
    return t
end

local function freeMod(g, except)
    local used = {}
    if g.conds then
        for i, m in pairs(g.conds) do if i ~= except then used[m] = true end end
    end
    for _, m in ipairs(MOD_ORDER) do if not used[m] then return m end end
end

local function resetStr(g)
    local list = condList(g)
    if #list == 0 then return "reset=target/combat " end
    local mods = {}
    for k, c in ipairs(list) do mods[k] = c.mod end
    return "reset=target/combat/" .. table.concat(mods, "/") .. " "
end

-- GCD가 없고 쿨타임이 있는 스킬 (예: 피의 분노) → 순서에서 빼고 매크로 맨 끝에서 매번 시도
local function isFreeSpell(id)
    if not id or id == 0 or not GetSpellBaseCooldown then return false end
    local cdMS, gcdMS = GetSpellBaseCooldown(id)
    return (cdMS or 0) > 0 and gcdMS == 0
end

-- 순서대로 진행하는 스킬 (조건부, 매번 시도 스킬 제외)
local function seqSpells(g)
    local t = {}
    for i, id in ipairs(g.slots) do
        if not isCond(g, i) and not isFreeSpell(id) then
            local n = spellName(id)
            if n then t[#t + 1] = { id = id, name = n } end
        end
    end
    return t
end

local function freeSpells(g)
    local t = {}
    for i, id in ipairs(g.slots) do
        if not isCond(g, i) and isFreeSpell(id) then
            local n = spellName(id)
            if n then t[#t + 1] = { id = id, name = n } end
        end
    end
    return t
end

local function seqNames(list)
    local names = {}
    for i, s in ipairs(list) do names[i] = s.name end
    return table.concat(names, ", ")
end

local function buildBody(g)
    if g.custom and g.lines then
        return table.concat(g.lines, "\n"), #g.lines
    end
    local atk = g.attack and "/startattack\n" or ""
    local conds = condList(g)
    local seq = seqSpells(g)
    local lines = {}
    -- GCD 스킬은 한 번 누를 때 한 번만 시도되므로, 조건부 스킬은 각자 정한 키를 누를 때만 시도
    for _, c in ipairs(conds) do
        lines[#lines + 1] = "/cast [mod:" .. c.mod .. "] " .. c.name
        -- 조건부 키를 누르고 있으면 여기서 멈춤 (아래 순서·매번 스킬은 처리하지 않음)
        lines[#lines + 1] = "/stopmacro [mod:" .. c.mod .. "]"
    end
    if #seq == 1 then
        -- 순서를 돌릴 스킬이 1개면 castsequence 대신 /cast (기존 매크로와 같은 방식)
        lines[#lines + 1] = "/cast " .. seq[1].name
    elseif #seq > 1 then
        lines[#lines + 1] = "/castsequence " .. resetStr(g) .. seqNames(seq)
    end
    local free = freeSpells(g)
    for _, f in ipairs(free) do lines[#lines + 1] = "/cast " .. f.name end
    return atk .. table.concat(lines, "\n"), #seq + #free + #conds
end

-- 화면 아이콘용: 클릭하면 조건부 스킬, 조건부 키+클릭이면 사이클도 1번으로
local function condMacroText(g, c)
    local seq = seqSpells(g)
    local t = "/cast " .. c.name
    if #seq > 1 then
        t = t .. "\n/castsequence [mod:" .. c.mod .. "] " .. resetStr(g) .. seqNames(seq)
    end
    return t
end

------------------------------------------------------------
-- 스타일 도우미 (상수의 레벨업 가이드와 같은 스타일)
------------------------------------------------------------
local C_BG = { 0.09, 0.10, 0.13 }
local C_PANEL = { 0.06, 0.07, 0.09 }
local C_EDGE = { 0.32, 0.35, 0.40 }
local C_TEXT = { 0.93, 0.94, 0.96 }
local C_MUTED = { 0.64, 0.68, 0.74 }
local C_ACCENT = { 0.30, 0.62, 0.78 }
local C_ACCENT_HI = { 0.38, 0.70, 0.86 }
local C_BTN = { 0.20, 0.22, 0.27 }
local C_BTN_HI = { 0.29, 0.32, 0.38 }

-- 레벨업 가이드 글꼴(마루부리)을 쓰고, 없으면 기본 글꼴로
local FONT_R = "Interface\\AddOns\\KQuestGuide\\fonts\\MaruBuri-Regular.ttf"
local FONT_B = "Interface\\AddOns\\KQuestGuide\\fonts\\MaruBuri-Bold.ttf"
local function SetF(fs, size, bold)
    local ok, r = pcall(fs.SetFont, fs, bold and FONT_B or FONT_R, size or 12, "")
    if not ok or r == false then
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size or 12, "")
    end
    return fs
end

local function Txt(parent, size, bold, muted)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    SetF(fs, size, bold)
    local c = muted and C_MUTED or C_TEXT
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function flat(f, bg, edge, a)
    bg = bg or C_BG
    edge = edge or C_EDGE
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], a or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
end

local function accentLine(f)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("TOPRIGHT", -1, -1)
    t:SetHeight(3)
    t:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
    return t
end

local function makeButton(parent, text, w, h, primary)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h or 24)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    b.text = Txt(b, 12, primary)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.primary = primary
    local function paint(self, hover)
        local on = self.primary or self.active
        local c = on and (hover and C_ACCENT_HI or C_ACCENT) or (hover and C_BTN_HI or C_BTN)
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        if on then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3]) end
        SetF(self.text, 12, on)
    end
    b:SetScript("OnEnter", function(self) paint(self, true) end)
    b:SetScript("OnLeave", function(self) paint(self, false) end)
    function b:SetUsable(on)
        self:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.4)
    end
    function b:SetActive(on)
        self.active = on
        paint(self, false)
    end
    paint(b, false)
    return b
end

-- 레벨업 가이드의 X 버튼처럼 글자만 있는 버튼
local function iconTextButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b.text = Txt(b, 15, true, true)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function() b.text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3]) end)
    b:SetScript("OnLeave", function() b.text:SetTextColor(C_MUTED[1], C_MUTED[2], C_MUTED[3]) end)
    return b
end

local function makeEdit(parent, w, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w, 24)
    flat(e, C_PANEL)
    e:SetFontObject(GameFontHighlight)
    SetF(e, 12)
    e:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
    e:SetTextInsets(7, 7, 0, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1) end)
    e:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C_EDGE[1], C_EDGE[2], C_EDGE[3], 1) end)
    return e
end

-- 평면 체크박스
local function makeCheck(parent, label)
    local c = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    c:SetSize(16, 16)
    flat(c, C_PANEL)
    local mark = c:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
    c:SetCheckedTexture(mark)
    c.label = Txt(c, 12)
    c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c.label:SetText(label)
    c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 8), 0, 0)
    c:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1) end)
    c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C_EDGE[1], C_EDGE[2], C_EDGE[3], 1) end)
    return c
end

local function setTex(tex, icon)
    if type(icon) == "string" and not icon:find("[/\\]") then
        tex:SetTexture("Interface\\Icons\\" .. icon)
    else
        tex:SetTexture(icon or DEFAULT_ICON)
    end
end

------------------------------------------------------------
-- 메인 창
------------------------------------------------------------
local F = CreateFrame("Frame", "RotaKeyFrame", UIParent, "BackdropTemplate")
F:SetSize(600, 636)
F:SetPoint("CENTER")
flat(F)
accentLine(F)
F:SetMovable(true)
F:EnableMouse(true)
F:RegisterForDrag("LeftButton")
F:SetScript("OnDragStart", F.StartMoving)
F:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB.pos = { p, rp, x, y }
end)
F:SetFrameStrata("DIALOG")
F:SetClampedToScreen(true)
F:Hide()
tinsert(UISpecialFrames, "RotaKeyFrame")

local title = Txt(F, 16, true)
title:SetPoint("TOPLEFT", 14, -12)
title:SetText("매크로메이커")
local subTitle = Txt(F, 12, false, true)
subTitle:SetPoint("LEFT", title, "RIGHT", 8, -1)
subTitle:SetText("스킬 로테이션")

local closeBtn = iconTextButton(F, "X")
closeBtn:SetPoint("TOPRIGHT", -8, -10)
closeBtn:SetScript("OnClick", function() F:Hide() end)

-- 좌측: 그룹 목록
local left = CreateFrame("Frame", nil, F, "BackdropTemplate")
left:SetPoint("TOPLEFT", 10, -40)
left:SetSize(140, 586)
flat(left, C_PANEL)

local groupLabel = Txt(left, 13, true)
groupLabel:SetPoint("TOPLEFT", 8, -8)
groupLabel:SetText("그룹")

local groupBtns = {}
local addBtn = makeButton(left, "그룹 추가", 124)
addBtn:SetPoint("BOTTOM", 0, 64)
local dupBtn = makeButton(left, "그룹 복제", 124)
dupBtn:SetPoint("BOTTOM", 0, 38)
local delBtn = makeButton(left, "그룹 삭제", 124)
delBtn:SetPoint("BOTTOM", 0, 12)
local statusCheck = makeCheck(left, "상태창 표시")
statusCheck:SetPoint("BOTTOMLEFT", 6, 90)
local logBtn = makeButton(left, "기능 확인: 꺼짐", 124)
logBtn:SetPoint("BOTTOM", 0, 116)
logBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("기능 확인")
    GameTooltip:AddLine("켜 두면 아이콘을 연타할 때 시전된 스킬과", 1, 1, 1)
    GameTooltip:AddLine("1번부터 다시 시작된 순간을 채팅창에 기록합니다.", 1, 1, 1)
    GameTooltip:Show()
end)
logBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    self:SetActive(self.active)
end)

local function refreshLogBtn()
    logBtn:SetActive(DB.logOn and true or false)
    logBtn.text:SetText(DB.logOn and "기능 확인: 켜짐" or "기능 확인: 꺼짐")
end

function F.ToggleLog()
    DB.logOn = not DB.logOn
    refreshLogBtn()
    out(DB.logOn and "기능 확인 |cff4db8e0켜짐|r - 시전된 스킬을 채팅창에 기록합니다." or "기능 확인 꺼짐")
end
logBtn:SetScript("OnClick", function() F.ToggleLog() end)

-- 우측: 그룹 설정
local right = CreateFrame("Frame", nil, F)
right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
right:SetPoint("BOTTOMRIGHT", -10, 10)

local nameLabel = Txt(right, 13, true)
nameLabel:SetPoint("TOPLEFT", 0, -6)
nameLabel:SetText("그룹 이름")
local nameEdit = makeEdit(right, 160, 12)
nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)

local iconBtn = CreateFrame("Button", nil, right, "BackdropTemplate")
iconBtn:SetSize(40, 40)
iconBtn:SetPoint("TOPLEFT", 0, -36)
flat(iconBtn, { 0, 0, 0 })
iconBtn.tex = iconBtn:CreateTexture(nil, "ARTWORK")
iconBtn.tex:SetPoint("TOPLEFT", 2, -2)
iconBtn.tex:SetPoint("BOTTOMRIGHT", -2, 2)
local iconHint = Txt(right, 11, false, true)
iconHint:SetPoint("TOP", iconBtn, "BOTTOM", 0, -2)
iconHint:SetText("아이콘")

local macroLabel = Txt(right, 13, true)
macroLabel:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 12, -2)
macroLabel:SetText("아이콘 이름 (매크로 이름)")
local macroEdit = makeEdit(right, 160, 16)
macroEdit:SetPoint("TOPLEFT", macroLabel, "BOTTOMLEFT", 0, -4)

-- 슬롯 영역
local slotArea = CreateFrame("Frame", nil, right, "BackdropTemplate")
slotArea:SetPoint("TOPLEFT", 0, -114)
slotArea:SetSize(428, 268)
flat(slotArea, C_PANEL)

local slotHelp = Txt(right, 11, false, true)
slotHelp:SetPoint("BOTTOMLEFT", slotArea, "TOPLEFT", 0, 3)
slotHelp:SetText("주문책에서 스킬을 끌어다 놓기 · 칸끼리 끌어서 순서 바꾸기 · 우클릭으로 비우기")

local plusBtn = makeButton(right, "+", 26)
plusBtn:SetPoint("TOPLEFT", slotArea, "BOTTOMLEFT", 0, -6)
local minusBtn = makeButton(right, "-", 26)
minusBtn:SetPoint("LEFT", plusBtn, "RIGHT", 4, 0)
local slotCount = Txt(right, 11, false, true)
slotCount:SetPoint("LEFT", minusBtn, "RIGHT", 8, 0)

-- 평타 / 대상 변경
local atkCheck = makeCheck(right, "기본 공격(평타) 사용")
atkCheck:SetPoint("TOPLEFT", plusBtn, "BOTTOMLEFT", -2, -10)

local modeDesc = Txt(right, 11, false, true)
modeDesc:SetPoint("TOPLEFT", atkCheck, "BOTTOMLEFT", 2, -8)
modeDesc:SetWidth(428)
modeDesc:SetJustifyH("LEFT")

-- 저장
local saveBtn = makeButton(right, "저장 / 아이콘 생성", 150, 26, true)
saveBtn:SetPoint("BOTTOMLEFT", 0, 0)
local pickBtn = makeButton(right, "아이콘 꺼내기", 100, 26)
pickBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
local moveBtn = makeButton(right, "조건부 아이콘 위치", 130, 26)
moveBtn:SetPoint("LEFT", pickBtn, "RIGHT", 6, 0)
moveBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
moveBtn:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then F.ResetCondPos() return end
    F.SetMoving(not F.IsMoving())
end)
moveBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("조건부 아이콘 위치")
    GameTooltip:AddLine("왼쪽 클릭: 위치 바꾸기 시작 / 끝내기", 1, 1, 1)
    GameTooltip:AddLine("하늘색 상자를 끌어서 원하는 곳에 놓으세요.", 1, 1, 1)
    GameTooltip:AddLine("오른쪽 클릭: 처음 위치로 되돌리기", 1, 1, 1)
    GameTooltip:Show()
end)
moveBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    self:SetActive(self.active)
end)
function F.RefreshMoveBtn()
    local on = F.IsMoving and F.IsMoving()
    moveBtn:SetActive(on and true or false)
    moveBtn.text:SetText(on and "위치 저장 (완료)" or "조건부 아이콘 위치")
end
local statusText = Txt(right, 11)
statusText:SetPoint("BOTTOMLEFT", saveBtn, "TOPLEFT", 0, 6)
statusText:SetWidth(428)
statusText:SetJustifyH("LEFT")

local function G() return DB.groups[selected] end

local function setStatus(msg, r, g, b)
    statusText:SetText(msg or "")
    statusText:SetTextColor(r or C_ACCENT_HI[1], g or C_ACCENT_HI[2], b or C_ACCENT_HI[3])
end

-- kind: "name"(이름/아이콘), "adv"(상세옵션 편집), nil(기본 설정: 슬롯·평타·조건)
local function markDirty(kind)
    local g = G()
    if g then
        g.dirty = true
        if g.custom and kind ~= "name" and kind ~= "adv" then
            g.linesBackup = g.lines
            g.custom, g.lines = nil, nil
            out("기본 설정이 바뀌어 이 그룹의 상세옵션 내용을 기본 설정으로 다시 만들었어요. [상세옵션]의 '이전 상세 내용 복원'으로 되돌릴 수 있어요.")
        end
    end
    setStatus("변경 사항이 있어요. [저장 / 아이콘 생성]을 눌러야 퀵슬롯 아이콘에 반영됩니다.")
end

------------------------------------------------------------
-- 슬롯
------------------------------------------------------------
local slots = {}
local dragSrc, dragId

local function cursorSpell()
    local t, a, _, c = GetCursorInfo()
    if t == "spell" then return c or a end
end

local function slotDrop(self)
    local g = G()
    if not g or InCombatLockdown() then return end
    local id = cursorSpell()
    if not id then return end
    local i = self.index
    if dragSrc and dragId == id and dragSrc ~= i then
        g.slots[dragSrc] = g.slots[i] or 0
        if g.conds then g.conds[dragSrc], g.conds[i] = g.conds[i], g.conds[dragSrc] end
    end
    g.slots[i] = id
    dragSrc, dragId = nil, nil
    ClearCursor()
    markDirty()
    F.Refresh()
end

local function updateCooldown(cd, id)
    if not id or id == 0 then cd:Clear() return end
    if C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id)
        if ok and d then
            if pcall(cd.SetCooldownFromDurationObject, cd, d) then return end
        end
    end
    local ok, c = pcall(C_Spell.GetSpellCooldown, id)
    if ok and c and not isSecret(c.startTime) and not isSecret(c.duration) then
        cd:SetCooldown(c.startTime, c.duration)
    end
end

local function makeSlot(i)
    local s = CreateFrame("Button", nil, slotArea, "BackdropTemplate")
    s:SetSize(80, 124)
    local row = math.floor((i - 1) / SLOTS_PER_ROW)
    local col = (i - 1) % SLOTS_PER_ROW
    s:SetPoint("TOPLEFT", 8 + col * 83, -8 - row * 128)
    s.index = i
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s:RegisterForDrag("LeftButton")

    s.num = Txt(s, 11, true)
    s.num:SetPoint("TOPLEFT", 2, -1)

    s.iconFrame = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.iconFrame:SetSize(42, 42)
    s.iconFrame:SetPoint("TOP", 0, -12)
    flat(s.iconFrame, { 0, 0, 0 })
    s.icon = s.iconFrame:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 2, -2)
    s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    s.cd = CreateFrame("Cooldown", nil, s.iconFrame, "CooldownFrameTemplate")
    s.cd:SetAllPoints(s.icon)
    s.plus = Txt(s.iconFrame, 18, true, true)
    s.plus:SetPoint("CENTER")
    s.plus:SetText("+")

    s.name = Txt(s, 11)
    s.name:SetPoint("TOP", s.iconFrame, "BOTTOM", 0, -3)
    s.name:SetWidth(78)
    s.name:SetWordWrap(false)
    s.info = Txt(s, 11, false, true)
    s.info:SetPoint("TOP", s.name, "BOTTOM", 0, -2)
    s.info:SetWidth(78)
    s.info:SetWordWrap(false)
    s.cond = makeCheck(s, "조건부")
    s.cond:SetPoint("BOTTOMLEFT", 8, 22)
    s.cond.label:SetFontObject(GameFontHighlightSmall)
    SetF(s.cond.label, 11)
    s.cond.label:SetTextColor(C_MUTED[1], C_MUTED[2], C_MUTED[3])
    s.cond:SetScript("OnClick", function(self)
        local g = G()
        if not g or InCombatLockdown() then self:SetChecked(g and isCond(g, i)) return end
        g.conds = g.conds or {}
        if self:GetChecked() then
            local m = freeMod(g, i)
            if not m then
                self:SetChecked(false)
                out("조건부 스킬은 그룹당 3개(Shift, Ctrl, Alt)까지예요.")
                return
            end
            g.conds[i] = m
        else
            g.conds[i] = nil
        end
        markDirty()
        F.Refresh()
    end)
    s.modBtn = makeButton(s, "Shift", 64, 17)
    s.modBtn:SetPoint("BOTTOM", 0, 3)
    s.modBtn:SetScript("OnClick", function()
        local g = G()
        if not g or InCombatLockdown() or not isCond(g, i) then return end
        -- 다른 조건부 스킬이 쓰지 않는 다음 키로
        local cur = g.conds[i]
        local used = {}
        for k, m in pairs(g.conds) do if k ~= i then used[m] = true end end
        local start
        for k, m in ipairs(MOD_ORDER) do if m == cur then start = k end end
        for step = 1, #MOD_ORDER do
            local m = MOD_ORDER[((start or 0) + step - 1) % #MOD_ORDER + 1]
            if not used[m] then g.conds[i] = m break end
        end
        markDirty()
        F.Refresh()
    end)
    s.modBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("이 조건부 스킬의 키")
        GameTooltip:AddLine("누를 때마다 다른 조건부 스킬이 쓰지 않는 키로 바뀝니다.", 1, 1, 1)
        GameTooltip:AddLine("Shift+숫자는 기본 설정에서 액션바 페이지 넘기기라", 1, 0.82, 0)
        GameTooltip:AddLine("숫자키 퀵슬롯이라면 Ctrl이나 Alt를 추천합니다.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    s.modBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.cond:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("조건부 스킬 (그룹당 3개까지)")
        GameTooltip:AddLine("순서에서 빠지고, 쓸 수 있을 때 화면에 아이콘이 뜹니다.", 1, 1, 1)
        GameTooltip:AddLine("정한 키(Shift/Ctrl/Alt)+퀵슬롯 또는 화면 아이콘 클릭으로 사용", 1, 1, 1)
        GameTooltip:Show()
    end)
    s.cond:HookScript("OnLeave", function() GameTooltip:Hide() end)

    s:SetScript("OnReceiveDrag", slotDrop)
    s:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local g = G()
            if g and not InCombatLockdown() then
                g.slots[self.index] = 0
                if g.conds then g.conds[self.index] = nil end
                markDirty()
                F.Refresh()
            end
        else
            slotDrop(self)
        end
    end)
    s:SetScript("OnDragStart", function(self)
        local g = G()
        local id = g and g.slots[self.index]
        if not id or id == 0 or InCombatLockdown() then return end
        dragSrc, dragId = self.index, id
        if C_Spell.PickupSpell then C_Spell.PickupSpell(id) elseif PickupSpell then PickupSpell(id) end
    end)
    s:SetScript("OnEnter", function(self)
        local g = G()
        local id = g and g.slots[self.index]
        if id and id ~= 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(id)
            GameTooltip:Show()
        end
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[i] = s
    return s
end

for i = 1, MAX_SLOTS do makeSlot(i) end

local function slotInfo(id)
    local cdMS, gcdMS
    if GetSpellBaseCooldown then cdMS, gcdMS = GetSpellBaseCooldown(id) end
    local cdText
    if cdMS and cdMS > 0 then
        local sec = cdMS / 1000
        cdText = (sec == math.floor(sec)) and ("쿨 %d초"):format(sec) or ("쿨 %.1f초"):format(sec)
    else
        cdText = "쿨 없음"
    end
    local gcdText = (gcdMS and gcdMS > 0) and "GCD" or "GCD 없음"
    return cdText .. " · " .. gcdText
end

local function refreshSlots()
    local g = G()
    for i = 1, MAX_SLOTS do
        local s = slots[i]
        if g and i <= #g.slots then
            s:Show()
            local id = g.slots[i]
            s.num:SetText(i)
            if id and id ~= 0 then
                setTex(s.icon, spellIcon(id))
                s.icon:Show()
                s.plus:Hide()
                s.name:SetText(spellName(id) or "?")
                s.info:SetText(slotInfo(id))
                local known = true
                if IsPlayerSpell then
                    local ok, r = pcall(IsPlayerSpell, id)
                    if ok and r == false then known = false end
                end
                s.icon:SetDesaturated(not known)
                s.cond:Show()
                s.cond:SetChecked(isCond(g, i))
                s.modBtn:SetShown(isCond(g, i))
                if isCond(g, i) then
                    s.modBtn.text:SetText(MOD_LABEL[g.conds[i]] .. " 키")
                    s.num:SetText("|cff4db8e0조건|r")
                elseif isFreeSpell(id) then
                    s.num:SetText("|cff9fd86b매번|r")
                else
                    s.num:SetText(tostring(i))
                end
                updateCooldown(s.cd, id)
            else
                s.icon:Hide()
                s.plus:Show()
                s.name:SetText("|cff666666빈 칸|r")
                s.info:SetText("")
                s.cd:Clear()
                s.cond:Hide()
                s.modBtn:Hide()
            end
        else
            s:Hide()
        end
    end
    if g then slotCount:SetText(("슬롯 %d / %d"):format(#g.slots, MAX_SLOTS)) end
end

------------------------------------------------------------
-- 새로고침
------------------------------------------------------------
local function refreshGroups()
    for i, g in ipairs(DB.groups) do
        local b = groupBtns[i]
        if not b then
            b = makeButton(left, "", 124, 24)
            b:SetPoint("TOP", 0, -28 - (i - 1) * 28)
            b:SetScript("OnClick", function(self)
                selected = self.index
                F.Refresh()
            end)
            groupBtns[i] = b
        end
        b.index = i
        b.text:SetText(g.name)
        b:SetActive(i == selected)
        b:Show()
    end
    for i = #DB.groups + 1, #groupBtns do groupBtns[i]:Hide() end
    addBtn:SetUsable(#DB.groups < 10)
    delBtn:SetUsable(#DB.groups > 1)
end

function F.Refresh()
    if not DB then return end
    if selected > #DB.groups then selected = #DB.groups end
    local g = G()
    refreshGroups()
    if not nameEdit:HasFocus() then nameEdit:SetText(g.name) end
    if not macroEdit:HasFocus() then macroEdit:SetText(g.macroName) end
    local firstIcon
    for _, id in ipairs(g.slots) do
        if id ~= 0 then firstIcon = spellIcon(id) break end
    end
    setTex(iconBtn.tex, g.icon or firstIcon or DEFAULT_ICON)
    refreshSlots()
    atkCheck:SetChecked(g.attack)
    local body = buildBody(g)
    local conds = condList(g)
    local condLine = ""
    if #conds > 0 then
        local cn = {}
        for k, c in ipairs(conds) do cn[k] = c.name .. "(" .. MOD_LABEL[c.mod] .. ")" end
        condLine = "|cff4db8e0조건부 [" .. table.concat(cn, ", ") .. "]: 아이콘이 뜨면 해당 키+퀵슬롯 또는 아이콘 클릭|r\n"
    end
    local free = freeSpells(g)
    if #free > 0 then
        local fn = {}
        for k, f in ipairs(free) do fn[k] = f.name end
        condLine = condLine .. "|cff9fd86b매번 시도 [" .. table.concat(fn, ", ") .. "]: GCD 없는 쿨 스킬이라 순서에서 빼고 매번 함께 시도|r\n"
    end
    modeDesc:SetText(("%s대상이 바뀌거나 전투가 끝나면 1번부터 다시 시작합니다. 쿨타임이 남은 스킬은 돌아올 때까지 기다립니다.\n매크로 글자 수: %d / %d (한글은 1글자에 3칸)"):format(condLine, #body, MACRO_LIMIT))
    statusCheck:SetChecked(DB.showStatus)
    refreshLogBtn()
    refreshStatus()
    plusBtn:SetUsable(#g.slots < MAX_SLOTS)
    minusBtn:SetUsable(#g.slots > 1)
    if g.dirty then
        setStatus("변경 사항이 있어요. [저장 / 아이콘 생성]을 눌러야 퀵슬롯 아이콘에 반영됩니다.")
    elseif g.savedMacro then
        setStatus("저장됨: 퀵슬롯의 [" .. g.savedMacro .. "] 아이콘을 연타하면 실행됩니다.", 0.45, 0.85, 0.55)
    else
        setStatus("스킬을 등록하고 [저장 / 아이콘 생성]을 눌러 주세요.", C_MUTED[1], C_MUTED[2], C_MUTED[3])
    end
end

------------------------------------------------------------
-- 입력 처리
------------------------------------------------------------
nameEdit:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local g = G()
    local t = strtrim(self:GetText())
    if t ~= "" then g.name = t refreshGroups() end
end)
nameEdit:HookScript("OnEditFocusLost", function() F.Refresh() end)

macroEdit:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    G().macroName = strtrim(self:GetText())
    markDirty("name")
end)

atkCheck:SetScript("OnClick", function(self)
    G().attack = self:GetChecked() and true or false
    markDirty()
    F.Refresh()
end)

plusBtn:SetScript("OnClick", function()
    local g = G()
    if #g.slots < MAX_SLOTS then g.slots[#g.slots + 1] = 0 markDirty() F.Refresh() end
end)
minusBtn:SetScript("OnClick", function()
    local g = G()
    if #g.slots > 1 then
        if g.conds then g.conds[#g.slots] = nil end
        g.slots[#g.slots] = nil
        markDirty()
        F.Refresh()
    end
end)

addBtn:SetScript("OnClick", function()
    if #DB.groups >= 10 then return end
    DB.groups[#DB.groups + 1] = newGroup(#DB.groups + 1)
    selected = #DB.groups
    F.Refresh()
end)

dupBtn:SetScript("OnClick", function()
    if #DB.groups >= 10 then out("그룹은 최대 10개까지 만들 수 있어요.") return end
    local c = copyTable(G())
    c.id = DB.nextId
    DB.nextId = DB.nextId + 1
    if strlenutf8(c.name) <= 9 then c.name = c.name .. " 복사" end
    c.macroName = "로테" .. c.id
    c.savedMacro = nil
    c.dirty = true
    DB.groups[#DB.groups + 1] = c
    selected = #DB.groups
    F.Refresh()
end)

StaticPopupDialogs["ROTAKEY_DELETE"] = {
    text = "[%s] 그룹을 삭제할까요?\n퀵슬롯 아이콘(매크로)도 함께 삭제됩니다.",
    button1 = "삭제",
    button2 = "취소",
    OnAccept = function()
        if InCombatLockdown() then out("전투 중에는 삭제할 수 없어요.") return end
        local g = G()
        if g.savedMacro then
            local idx = GetMacroIndexByName(g.savedMacro)
            if idx and idx > 0 then DeleteMacro(idx) end
        end
        table.remove(DB.groups, selected)
        if F.ApplyAllCond then F.ApplyAllCond() end
        selected = math.max(1, selected - 1)
        F.Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

delBtn:SetScript("OnClick", function()
    if #DB.groups <= 1 then return end
    StaticPopup_Show("ROTAKEY_DELETE", G().name)
end)

------------------------------------------------------------
-- 저장 / 아이콘 생성
------------------------------------------------------------
local function saveGroup()
    if InCombatLockdown() then setStatus("전투 중에는 저장할 수 없어요. 전투가 끝난 뒤 눌러 주세요.", 0.90, 0.35, 0.32) return end
    local g = G()
    local spells = filledSpells(g)
    if #spells == 0 and not (g.custom and g.lines and #g.lines > 0) then setStatus("슬롯에 스킬을 1개 이상 등록해 주세요.", 0.90, 0.35, 0.32) return end
    local mname = strtrim(g.macroName or "")
    if mname == "" then setStatus("아이콘 이름을 입력해 주세요.", 0.90, 0.35, 0.32) return end
    for i, o in ipairs(DB.groups) do
        if i ~= selected and (o.savedMacro == mname or o.macroName == mname) then
            setStatus("다른 그룹(" .. o.name .. ")이 같은 아이콘 이름을 쓰고 있어요.", 0.90, 0.35, 0.32)
            return
        end
    end
    local body = buildBody(g)
    if #body > MACRO_LIMIT then
        setStatus(("매크로가 너무 길어요 (%d / %d). %s"):format(#body, MACRO_LIMIT, g.custom and "상세옵션에서 줄을 줄여 주세요." or "슬롯을 줄여 주세요."), 0.90, 0.35, 0.32)
        return
    end
    -- 내 것이 아닌 같은 이름의 매크로가 이미 있으면 덮어쓰지 않음
    local existing = GetMacroIndexByName(mname)
    if existing and existing > 0 and g.savedMacro ~= mname then
        setStatus("[" .. mname .. "] 이름의 매크로가 이미 있어요. 다른 이름을 써 주세요.", 0.90, 0.35, 0.32)
        return
    end
    local icon = g.icon or spells[1] and spellIcon(spells[1].id) or DEFAULT_ICON
    local idx = g.savedMacro and GetMacroIndexByName(g.savedMacro) or 0
    local created = false
    local ok, err = pcall(function()
        if idx and idx > 0 then
            EditMacro(idx, mname, icon, body)
            idx = GetMacroIndexByName(mname)
        else
            idx = CreateMacro(mname, icon, body, true)
            created = true
        end
    end)
    if not ok or not idx or idx == 0 then
        setStatus("아이콘을 만들지 못했어요. 캐릭터 전용 매크로 칸이 꽉 찼는지 확인해 주세요.", 0.90, 0.35, 0.32)
        if err then out("오류: " .. tostring(err)) end
        return
    end
    g.savedMacro = mname
    if F.ApplyAllCond then F.ApplyAllCond() end
    g.dirty = nil
    F.Refresh()
    if created then
        PickupMacro(idx)
        setStatus("커서에 [" .. mname .. "] 아이콘이 올라갔어요. 퀵슬롯 빈 칸에 놓아 주세요.", 0.45, 0.85, 0.55)
    else
        setStatus("저장됨: 퀵슬롯에 놓아 둔 [" .. mname .. "] 아이콘이 자동으로 갱신됐어요.", 0.45, 0.85, 0.55)
    end
end
saveBtn:SetScript("OnClick", saveGroup)

pickBtn:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    local g = G()
    local idx = g.savedMacro and GetMacroIndexByName(g.savedMacro) or 0
    if idx and idx > 0 then
        PickupMacro(idx)
        setStatus("커서에 아이콘이 올라갔어요. 퀵슬롯에 놓아 주세요.", 0.45, 0.85, 0.55)
    else
        setStatus("아직 만들어진 아이콘이 없어요. 먼저 저장해 주세요.", 0.90, 0.35, 0.32)
    end
end)

------------------------------------------------------------
-- 아이콘 선택 창
------------------------------------------------------------
local ICON_COLS, ICON_ROWS = 10, 6
local P = CreateFrame("Frame", "RotaKeyIconPicker", F, "BackdropTemplate")
P:SetSize(10 + ICON_COLS * 38 + 6, 60 + ICON_ROWS * 38 + 40)
P:SetPoint("TOPLEFT", F, "TOPRIGHT", 6, 0)
flat(P)
accentLine(P)
P:EnableMouse(true)
P:SetFrameStrata("DIALOG")
P:SetClampedToScreen(true)
P:Hide()

local pTitle = Txt(P, 13, true)
pTitle:SetPoint("TOPLEFT", 10, -12)
pTitle:SetText("아이콘 선택")
local pClose = iconTextButton(P, "X")
pClose:SetPoint("TOPRIGHT", -8, -10)
pClose:SetScript("OnClick", function() P:Hide() end)

local pAuto = makeButton(P, "자동 (1번 슬롯 스킬 아이콘)", 200, 22)
pAuto:SetPoint("TOPLEFT", 10, -34)

local iconList, page = nil, 1
local iconCells = {}
local pageText = Txt(P, 11)
pageText:SetPoint("BOTTOM", 0, 14)
local prevBtn = makeButton(P, "◀ 이전", 70)
prevBtn:SetPoint("BOTTOMLEFT", 10, 10)
local nextBtn = makeButton(P, "다음 ▶", 70)
nextBtn:SetPoint("BOTTOMRIGHT", -10, 10)

local function buildIconList()
    local list, seen = {}, {}
    local function add(v)
        if v and not seen[v] then seen[v] = true list[#list + 1] = v end
    end
    add(DEFAULT_ICON)
    for _, g in ipairs(DB.groups) do
        for _, id in ipairs(g.slots) do if id ~= 0 then add(spellIcon(id)) end end
    end
    if IconDataProviderMixin and CreateAndInitFromMixin then
        local ok, prov = pcall(CreateAndInitFromMixin, IconDataProviderMixin,
            IconDataProviderExtraType and IconDataProviderExtraType.Spellbook)
        if ok and prov and prov.GetNumIcons then
            for i = 1, prov:GetNumIcons() do add(prov:GetIconByIndex(i)) end
            if prov.Release then pcall(prov.Release, prov) end
        end
    end
    if #list < 100 and GetMacroIcons then
        local t = {}
        pcall(GetMacroIcons, t)
        for _, v in ipairs(t) do add(v) end
        if GetMacroItemIcons then
            local t2 = {}
            pcall(GetMacroItemIcons, t2)
            for _, v in ipairs(t2) do add(v) end
        end
    end
    return list
end

local function refreshPicker()
    local per = ICON_COLS * ICON_ROWS
    local pages = math.max(1, math.ceil(#iconList / per))
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    for i = 1, per do
        local cell = iconCells[i]
        local v = iconList[(page - 1) * per + i]
        if v then
            setTex(cell.tex, v)
            cell.value = v
            cell:Show()
            local cur = G().icon
            local bc = (cur == v) and C_ACCENT or C_EDGE
            cell:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
        else
            cell:Hide()
        end
    end
    pageText:SetText(("%d / %d  (아이콘 %d개)"):format(page, pages, #iconList))
end

for i = 1, ICON_COLS * ICON_ROWS do
    local c = CreateFrame("Button", nil, P, "BackdropTemplate")
    c:SetSize(36, 36)
    local row = math.floor((i - 1) / ICON_COLS)
    local col = (i - 1) % ICON_COLS
    c:SetPoint("TOPLEFT", 10 + col * 38, -60 - row * 38)
    flat(c, { 0, 0, 0 })
    c.tex = c:CreateTexture(nil, "ARTWORK")
    c.tex:SetPoint("TOPLEFT", 2, -2)
    c.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    c:SetScript("OnClick", function(self)
        G().icon = self.value
        markDirty("name")
        F.Refresh()
        refreshPicker()
    end)
    iconCells[i] = c
end

P:EnableMouseWheel(true)
P:SetScript("OnMouseWheel", function(_, d) page = page - d refreshPicker() end)
prevBtn:SetScript("OnClick", function() page = page - 1 refreshPicker() end)
nextBtn:SetScript("OnClick", function() page = page + 1 refreshPicker() end)
pAuto:SetScript("OnClick", function()
    G().icon = nil
    markDirty("name")
    F.Refresh()
    refreshPicker()
end)

iconBtn:SetScript("OnClick", function()
    if P:IsShown() then P:Hide() return end
    iconList = buildIconList()
    page = 1
    refreshPicker()
    P:Show()
end)
iconBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("클릭해서 아이콘 고르기")
    GameTooltip:Show()
end)
iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------
-- 미니맵 버튼
------------------------------------------------------------
local mm = CreateFrame("Button", "RotaKeyMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
local mmIcon = mm:CreateTexture(nil, "BACKGROUND")
mmIcon:SetSize(20, 20)
mmIcon:SetPoint("CENTER", 0, 1)
mmIcon:SetTexture("Interface\\Icons\\Ability_Warrior_DecisiveStrike")
local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function placeMinimap()
    local a = math.rad(DB.minimapAngle or 200)
    mm:ClearAllPoints()
    local radius = (Minimap:GetWidth() / 2) + 5
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end
mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        DB.minimapAngle = math.deg((math.atan2 or math.atan)(cy / s - my, cx / s - mx))
        placeMinimap()
    end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
        F.ToggleLog()
    else
        F:SetShown(not F:IsShown())
    end
end)
mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("매크로메이커")
    GameTooltip:AddLine("왼쪽 클릭: 설정창 열기/닫기", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("오른쪽 클릭: 기능 확인 켜기/끄기", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("드래그: 아이콘 위치 이동", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("기능 확인: " .. (DB.logOn and "|cff4db8e0켜짐|r" or "꺼짐"), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------
-- 조건부 스킬 화면 아이콘
------------------------------------------------------------
local condBtns = {}
local glowing = {}
local pendingCond = false

local function condVis(b, a)
    b.icon:SetAlpha(a)
    b.edge:SetAlpha(a)
end

local function condButton(key)
    local b = condBtns[key]
    if b then return b end
    if InCombatLockdown() then return nil end
    b = CreateFrame("Button", "RotaKeyCond" .. key, UIParent, "SecureActionButtonTemplate")
    b:SetSize(48, 48)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.edge:SetColorTexture(C_ACCENT_HI[1], C_ACCENT_HI[2], C_ACCENT_HI[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.label = Txt(b, 11, false, true)
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.label:SetText("조건부 아이콘")
    b.label:Hide()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.gname or "조건부 스킬")
        GameTooltip:AddLine("클릭: 이 스킬 사용", 1, 1, 1)
        GameTooltip:AddLine((self.modLabel or "Shift") .. "+클릭: 사용하고 사이클을 1번부터", 1, 1, 1)
        GameTooltip:AddLine("위치 변경: 설정창 [조건부 아이콘 위치] 버튼", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    condVis(b, 0)
    condBtns[key] = b
    return b
end

local function applyCond(g, c, n, alive)
    local key = g.id .. "_" .. c.mod
    local b = condButton(key)
    if not b then return end
    alive[key] = true
    b.gid = key
    b.gname = g.name .. " - " .. c.name
    b.modLabel = MOD_LABEL[c.mod]
    b.spellID = c.id
    b:SetAttribute("macrotext", condMacroText(g, c))
    setTex(b.icon, spellIcon(c.id))
    b:ClearAllPoints()
    local pos = DB.condPos and DB.condPos[key]
    if pos then
        b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        b:SetPoint("CENTER", UIParent, "CENTER", (n - 1) * 56 - 56, 140 + (g.id % 4) * 56)
    end
    b:Show()
end

local function applyAllCond()
    if InCombatLockdown() then pendingCond = true return end
    pendingCond = false
    local alive = {}
    for _, g in ipairs(DB.groups) do
        if g.savedMacro then
            for n, c in ipairs(condList(g)) do applyCond(g, c, n, alive) end
        end
    end
    for key, b in pairs(condBtns) do
        if not alive[key] then b:Hide() end
    end
end

local condTick = 0
local condUpdater = CreateFrame("Frame")
condUpdater:SetScript("OnUpdate", function(_, el)
    condTick = condTick + el
    if condTick < 0.1 then return end
    condTick = 0
    local preview = F:IsShown()
    for _, b in pairs(condBtns) do
        if b:IsShown() and b.spellID then
            b.label:SetShown(preview)
            if glowing[b.spellID] then
                condVis(b, 1)
            elseif preview then
                condVis(b, 0.6)
            else
                local ok, u = pcall(C_Spell.IsSpellUsable, b.spellID)
                if not ok or u == nil then
                    condVis(b, 0)
                elseif isSecret(u) then
                    -- 값을 모르는 채로 화면에만 반영
                    local done = false
                    if b.icon.SetAlphaFromBoolean then
                        done = pcall(b.icon.SetAlphaFromBoolean, b.icon, u, 1, 0)
                        pcall(b.edge.SetAlphaFromBoolean, b.edge, u, 1, 0)
                    end
                    if not done then condVis(b, 0) end
                else
                    condVis(b, u and 1 or 0)
                end
            end
        end
    end
end)

F.ApplyAllCond = applyAllCond

-- 조건부 아이콘 위치 설정 (이동용 덮개를 끌어서 옮김)
local movers = {}
local moving = false

local function getMover(b)
    local m = movers[b]
    if m then return m end
    m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m:SetSize(b:GetWidth(), b:GetHeight())
    m:SetFrameStrata("DIALOG")
    flat(m, C_ACCENT, C_ACCENT_HI, 0.35)
    m:EnableMouse(true)
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:RegisterForDrag("LeftButton")
    m.text = Txt(m, 11, true)
    m.text:SetPoint("TOP", m, "BOTTOM", 0, -3)
    m:SetScript("OnDragStart", function(self) self:StartMoving() end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if InCombatLockdown() then return end
        local p, _, rp, x, y = self:GetPoint()
        b:ClearAllPoints()
        b:SetPoint(p, UIParent, rp, x, y)
        DB.condPos = DB.condPos or {}
        DB.condPos[b.gid] = { p, rp, x, y }
    end)
    movers[b] = m
    return m
end

function F.SetMoving(on)
    if on and InCombatLockdown() then out("전투 중에는 위치를 바꿀 수 없어요.") return end
    moving = on and true or false
    local count = 0
    for _, b in pairs(condBtns) do
        if b:IsShown() then
            local m = getMover(b)
            if moving then
                m:ClearAllPoints()
                local cx, cy = b:GetCenter()
                m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
                m.text:SetText(b.gname or "조건부 아이콘")
                m:Show()
                count = count + 1
            else
                m:Hide()
            end
        elseif movers[b] then
            movers[b]:Hide()
        end
    end
    if moving and count == 0 then
        moving = false
        out("조건부 스킬이 있는 저장된 그룹이 없어요. 슬롯에 [조건부]를 체크하고 저장해 주세요.")
    end
    if F.RefreshMoveBtn then F.RefreshMoveBtn() end
end

function F.ResetCondPos()
    if InCombatLockdown() then return end
    DB.condPos = nil
    applyAllCond()
    if moving then F.SetMoving(true) end
    out("조건부 아이콘 위치를 처음 자리로 되돌렸어요.")
end
function F.IsMoving() return moving end

------------------------------------------------------------
-- 실행 상태 표시창
------------------------------------------------------------
local S = CreateFrame("Frame", "RotaKeyStatus", UIParent, "BackdropTemplate")
S:SetSize(240, 40)
S:SetPoint("CENTER", 0, -200)
flat(S, C_BG, C_EDGE, 0.92)
accentLine(S)
S:SetMovable(true)
S:EnableMouse(true)
S:RegisterForDrag("LeftButton")
S:SetClampedToScreen(true)
S:SetScript("OnDragStart", S.StartMoving)
S:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB.statusPos = { p, rp, x, y }
end)
S:Hide()
local sTitle = Txt(S, 11, true)
sTitle:SetPoint("TOPLEFT", 7, -7)
sTitle:SetText("매크로메이커")

local rows, statusList = {}, {}
local lastReset, resetReason, lastGUID = 0, "", nil
local lastCast = {}

local function makeRow(i)
    local r = CreateFrame("Frame", nil, S, "BackdropTemplate")
    r:SetSize(228, 34)
    r:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 37)
    flat(r, C_PANEL)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(28, 28)
    r.icon:SetPoint("LEFT", 3, 0)
    r.name = Txt(r, 11)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1)
    r.name:SetWidth(120)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.nextIcon = r:CreateTexture(nil, "ARTWORK")
    r.nextIcon:SetSize(14, 14)
    r.nextIcon:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 1)
    r.nextText = Txt(r, 11, false, true)
    r.nextText:SetPoint("LEFT", r.nextIcon, "RIGHT", 3, 0)
    r.nextText:SetWidth(110)
    r.nextText:SetJustifyH("LEFT")
    r.nextText:SetWordWrap(false)
    r.state = Txt(r, 11, true)
    r.state:SetPoint("RIGHT", -6, 0)
    rows[i] = r
    return r
end

local function groupIcon(g)
    if g.icon then return g.icon end
    for _, id in ipairs(g.slots) do
        if id ~= 0 then return spellIcon(id) end
    end
    return DEFAULT_ICON
end

local function updateRows()
    local now = GetTime()
    for i, g in ipairs(statusList) do
        local r = rows[i]
        local spells = seqSpells(g)
        local conds = condList(g)
        local idx = GetMacroIndexByName(g.savedMacro) or 0
        local sid
        if idx > 0 and GetMacroSpell then
            local ok, v = pcall(GetMacroSpell, idx)
            if ok then sid = v end
        end
        local secret = sid ~= nil and isSecret(sid)
        local key = secret and "secret" or sid
        if r.prev ~= nil and key ~= r.prev and now - lastReset > 0.5 then r.active = now end
        r.prev = key

        -- 다음 스킬 표시
        if sid then
            pcall(function() r.nextIcon:SetTexture(C_Spell.GetSpellTexture(sid)) end)
            r.nextIcon:Show()
            if secret then
                r.nextText:SetText("다음 스킬")
            else
                local sname = C_Spell.GetSpellName(sid)
                local step
                for n, sp in ipairs(spells) do
                    if sp.id == sid or sp.name == sname then step = n break end
                end
                local isC = false
                for _, c in ipairs(conds) do
                    if c.id == sid or c.name == sname then isC = true break end
                end
                if isC and not step then
                    r.nextText:SetText("조건부 " .. (sname or ""))
                else
                    r.nextText:SetText((step and (step .. "/" .. #spells .. " ") or "") .. (sname or ""))
                end
            end
        else
            r.nextIcon:Hide()
            r.nextText:SetText("-")
        end

        -- 한 가지 스킬만 있는 그룹은 시전 기록으로 실행 여부 판단
        if #spells == 1 then
            local t = lastCast[spells[1].name]
            if t and now - t < 3 then r.active = t end
        end

        local running = r.active and now - r.active < 3
        if now - lastReset < 2.5 then
            r.state:SetText(resetReason)
            r.state:SetTextColor(0.95, 0.78, 0.35)
        elseif running then
            r.state:SetText("실행 중")
            r.state:SetTextColor(C_ACCENT_HI[1], C_ACCENT_HI[2], C_ACCENT_HI[3])
        else
            r.state:SetText("대기")
            r.state:SetTextColor(C_MUTED[1], C_MUTED[2], C_MUTED[3])
        end
        if running then
            r:SetBackdropBorderColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
            r:SetAlpha(1)
        else
            r:SetBackdropBorderColor(C_EDGE[1], C_EDGE[2], C_EDGE[3], 1)
            r:SetAlpha(0.65)
        end
    end
end

refreshStatus = function()
    if not DB then return end
    wipe(statusList)
    for _, g in ipairs(DB.groups) do
        if g.savedMacro then statusList[#statusList + 1] = g end
    end
    for i, g in ipairs(statusList) do
        local r = rows[i] or makeRow(i)
        setTex(r.icon, groupIcon(g))
        r.name:SetText(g.name)
        r:Show()
    end
    for i = #statusList + 1, #rows do rows[i]:Hide() end
    S:SetHeight(28 + #statusList * 37)
    S:SetShown(DB.showStatus and #statusList > 0)
    if S:IsShown() then updateRows() end
end

local tick = 0
S:SetScript("OnUpdate", function(_, el)
    tick = tick + el
    if tick < 0.2 then return end
    tick = 0
    updateRows()
end)

local function markReset(reason, why)
    if DB and DB.logOn and why and GetTime() - lastReset > 1 then
        out("|cfff2c75a" .. why .. " → 1번부터 다시 시작|r")
    end
    lastReset = GetTime()
    resetReason = reason
    for _, r in ipairs(rows) do r.active = nil end
end

statusCheck:SetScript("OnClick", function(self)
    DB.showStatus = self:GetChecked() and true or false
    refreshStatus()
end)

------------------------------------------------------------
-- 이벤트
------------------------------------------------------------
F:SetScript("OnShow", function() F.Refresh() end)
F:SetScript("OnHide", function()
    P:Hide()
    if F.IsMoving and F.IsMoving() then F.SetMoving(false) end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
ev:SetScript("OnEvent", function(_, e, a1, ...)
    if e == "ADDON_LOADED" and a1 == ADDON then
        RotaKeyDB = RotaKeyDB or {}
        DB = RotaKeyDB
        DB.nextId = DB.nextId or 1
        DB.groups = DB.groups or {}
        if #DB.groups == 0 then DB.groups[1] = newGroup(1) end
        if DB.showStatus == nil then DB.showStatus = true end
    elseif e == "PLAYER_LOGIN" then
        if DB.pos then
            F:ClearAllPoints()
            F:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
        end
        placeMinimap()
        if DB.statusPos then
            S:ClearAllPoints()
            S:SetPoint(DB.statusPos[1], UIParent, DB.statusPos[2], DB.statusPos[3], DB.statusPos[4])
        end
        -- 이전 버전의 [이어가기] 그룹은 castsequence 매크로로 자동 변환
        for _, g in ipairs(DB.groups) do
            if g.mode ~= nil then
                if g.mode == "continue" and g.savedMacro and not InCombatLockdown() then
                    local idx = GetMacroIndexByName(g.savedMacro)
                    local body = buildBody(g)
                    if idx and idx > 0 and #body <= MACRO_LIMIT then
                        local sp = filledSpells(g)
                        local icon = g.icon or (sp[1] and spellIcon(sp[1].id)) or DEFAULT_ICON
                        pcall(EditMacro, idx, g.savedMacro, icon, body)
                    else
                        g.dirty = true
                    end
                end
                g.mode = nil
            end
        end
        DB.debug = nil
        for _, g in ipairs(DB.groups) do
            -- 이전 버전(조건부 1개) → 여러 개 구조로
            local migrated = false
            if g.condSlot then
                g.conds = { [g.condSlot] = MOD_LABEL[g.condMod] and g.condMod or "shift" }
                if DB.condPos and DB.condPos[g.id] then
                    DB.condPos[g.id .. "_" .. g.conds[g.condSlot]] = DB.condPos[g.id]
                    DB.condPos[g.id] = nil
                end
                g.condSlot, g.condMod = nil, nil
                migrated = true
            end
            if g.condAuto ~= nil or migrated then
                g.condAuto = nil
                if g.conds and next(g.conds) and g.savedMacro and not InCombatLockdown() then
                    local idx = GetMacroIndexByName(g.savedMacro)
                    local body = buildBody(g)
                    if idx and idx > 0 and #body <= MACRO_LIMIT then
                        local sp = filledSpells(g)
                        local icon = g.icon or (sp[1] and spellIcon(sp[1].id)) or DEFAULT_ICON
                        pcall(EditMacro, idx, g.savedMacro, icon, body)
                    else
                        g.dirty = true
                    end
                end
            end
        end
        applyAllCond()
        refreshStatus()
        C_Timer.After(5, function() out("로드됨. 미니맵 버튼이나 /rk 로 설정창을 엽니다.") end)
    elseif e == "PLAYER_TARGET_CHANGED" then
        local guid = UnitGUID("target")
        if guid and (isSecret(guid) or guid ~= lastGUID) then
            if lastGUID then markReset("1번부터", "대상 변경") end
            lastGUID = (not isSecret(guid)) and guid or nil
        end
    elseif e == "PLAYER_REGEN_ENABLED" then
        markReset("1번부터", "전투 종료")
        if pendingCond then applyAllCond() end
    elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
        local sid = select(3, a1, ...)
        if sid and not isSecret(sid) then
            local n = C_Spell.GetSpellName(sid)
            if n then lastCast[n] = GetTime() end
            if n and DB.logOn and sid ~= 6603 and sid ~= 75 then
                -- 이 스킬이 들어 있는 그룹과 순서 찾기
                local where = {}
                for _, g in ipairs(DB.groups) do
                    if g.savedMacro and g.custom and g.lines then
                        for k, line in ipairs(g.lines) do
                            if line:find(n, 1, true) then where[#where + 1] = ("%s 상세 %d번 줄"):format(g.name, k) break end
                        end
                    elseif g.savedMacro then
                        local list = seqSpells(g)
                        local found = false
                        for k, sp in ipairs(list) do
                            if sp.id == sid or sp.name == n then
                                where[#where + 1] = ("%s %d/%d"):format(g.name, k, #list)
                                found = true
                                break
                            end
                        end
                        if not found then
                            for _, c in ipairs(condList(g)) do
                                if c.id == sid or c.name == n then
                                    where[#where + 1] = g.name .. " 조건부(" .. MOD_LABEL[c.mod] .. ")"
                                    found = true
                                    break
                                end
                            end
                        end
                        if not found then
                            for _, f in ipairs(freeSpells(g)) do
                                if f.id == sid or f.name == n then
                                    where[#where + 1] = g.name .. " 매번"
                                    break
                                end
                            end
                        end
                    end
                end
                local tail = #where > 0 and ("  |cff8fa0b0(" .. table.concat(where, ", ") .. ")|r") or "  |cff8fa0b0(그룹 밖 스킬)|r"
                out(("시전: |cff4db8e0%s|r%s  |cff6f7a88%.1f초|r"):format(n, tail, GetTime() % 1000))
            end
        elseif DB.logOn then
            out("시전: (전투 정보 보호로 스킬 이름 확인 불가)")
        end
    elseif e == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or e == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if a1 and not isSecret(a1) then glowing[a1] = (e == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or nil end
    elseif e == "SPELL_UPDATE_COOLDOWN" then
        if F:IsShown() then
            local g = G()
            for i = 1, MAX_SLOTS do
                local s = slots[i]
                if s:IsShown() then updateCooldown(s.cd, g.slots[i]) end
            end
        end
    end
end)

-- 기능 확인: 퀵슬롯 입력이 RotaKey 매크로에 도착했는지와 수정키 상태 기록
if UseAction then
    hooksecurefunc("UseAction", function(slot)
        if not DB or not DB.logOn then return end
        local txt = GetActionText and GetActionText(slot)
        if not txt then return end
        for _, g in ipairs(DB.groups) do
            if g.savedMacro == txt then
                local function yn(v) return v and "|cff4db8e0눌림|r" or "안 눌림" end
                out(("퀵슬롯 입력: [%s]  Shift %s · Ctrl %s · Alt %s"):format(txt,
                    yn(IsShiftKeyDown()), yn(IsControlKeyDown()), yn(IsAltKeyDown())))
                break
            end
        end
    end)
end

-- 퀵클릭(QuickClick.lua)에서 같은 창과 디자인을 쓰기 위해 내보내기
RotaKeyUI = {
    F = F, left = left, right = right, subTitle = subTitle,
    Txt = Txt, SetF = SetF, flat = flat, makeButton = makeButton, makeCheck = makeCheck,
    makeEdit = makeEdit, iconTextButton = iconTextButton, setTex = setTex, out = out,
    C = { BG = C_BG, PANEL = C_PANEL, EDGE = C_EDGE, TEXT = C_TEXT, MUTED = C_MUTED, ACCENT = C_ACCENT, BTN = C_BTN },
    DB = function() return DB end,
    G = function() return G() end,
    buildBody = buildBody,
    markDirty = markDirty,
    setStatus = setStatus,
    MACRO_LIMIT = MACRO_LIMIT,
    copyTable = copyTable,
}

SLASH_ROTAKEY1 = "/rk"
SLASH_ROTAKEY2 = "/rotakey"
SlashCmdList.ROTAKEY = function() F:SetShown(not F:IsShown()) end
