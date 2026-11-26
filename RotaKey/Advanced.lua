-- 매크로메이커 [상세옵션]: Razer Synapse 3 매크로 편집기처럼 줄 단위로 매크로를 직접 고치기
--
-- · 왼쪽: 매크로 줄 목록 (끌어서 순서 변경, 추가/복제/삭제/위/아래)
-- · 오른쪽: 고른 줄의 명령어, 주문(주문책에서 끌어다 놓기), 대상, 조건, 직접 입력
-- · 아래: 실제 매크로 미리보기와 글자 수(255 제한), 기본 설정으로 다시 만들기, 글자로 복사/붙여넣기
-- 처음 열면 기본 화면 설정으로 만든 줄이 들어 있고, 여기서 고치면 그 그룹은 "상세 그룹"이 됩니다.
-- 검증(MacroProbe, 2026-11-17)에서 동작이 확인된 명령어·조건·대상만 목록에 넣었습니다. (/run, /script, @focus 제외)
local UI = RotaKeyUI
if not UI then return end
local F, Txt, C, out = UI.F, UI.Txt, UI.C, UI.out

---------------------------------------------------------------------------
-- 목록 데이터
---------------------------------------------------------------------------
local COMMANDS = {
  { "/cast", "주문 시전", true }, { "/use", "아이템/주문 사용", true, "아이템 이름, 또는 장비 칸 번호\n예: /use 13 (위 장신구), /use 14 (아래 장신구)" },
  { "/castsequence", "순서대로 시전", nil, "예: /castsequence reset=target 주문1, 주문2" }, { "/castrandom", "무작위로 하나 시전", nil, "예: /castrandom 주문1, 주문2" },
  { "/startattack", "자동 공격 시작" }, { "/stopattack", "자동 공격 멈춤" }, { "/stopmacro", "조건 맞으면 매크로 끝", nil, "조건이 맞으면 이 줄에서 매크로를 멈춥니다" },
  { "/stopcasting", "시전 중인 주문 취소" }, { "/targetenemy", "가까운 적 대상 잡기" }, { "/targetfriend", "가까운 아군 대상 잡기" },
  { "/targetlasttarget", "이전 대상" }, { "/target", "이름으로 대상 잡기" }, { "/cleartarget", "대상 해제" },
  { "/assist", "대상의 대상 잡기" }, { "/cancelaura", "버프 취소 (버프 이름)" }, { "/cancelform", "변신/태세 해제" },
  { "/dismount", "탈것에서 내리기" }, { "/petattack", "소환수 공격" }, { "/petfollow", "소환수 따라오기" },
  { "/petpassive", "소환수 가만히" }, { "/petdefensive", "소환수 방어" }, { "/petassist", "소환수 지원" }, { "/petstay", "소환수 대기" },
  { "/equip", "장비 착용 (아이템 이름)", nil, "한손 무기는 주무기 칸에 들어갑니다" }, { "/equipslot", "칸 번호에 장비 착용", nil, "예: /equipslot 17 아이템이름 (보조장비/방패)\n칸 번호: 1 머리, 6 허리, 8 발, 10 손, 13·14 장신구, 15 망토, 16 주무기, 17 보조장비, 18 원거리" }, { "/click", "버튼 클릭 (버튼 이름)" },
  { "/p", "파티 채팅", nil, "파티원에게 말합니다. %t 는 대상 이름으로 바뀝니다\n예: /p %t 양 변신 중입니다" },
  { "/s", "말하기 (일반)", nil, "주변에 말합니다. %t 는 대상 이름" }, { "/y", "외치기", nil, "넓은 범위에 외칩니다. %t 는 대상 이름" },
  { "/g", "길드 채팅", nil, "%t 는 대상 이름" }, { "/ra", "공격대 채팅", nil, "%t 는 대상 이름" },
  { "/rw", "공격대 경보", nil, "공격대장/부공대장만 가능. 화면 가운데에 크게 뜹니다" },
  { "/e", "감정 표현 (직접 쓰기)", nil, "예: /e 이(가) 도발합니다!" }, { "/w", "귓속말", nil, "예: /w 캐릭터이름 할 말" },
  { "/trade", "대상과 거래창 열기" },
  { "#showtooltip", "아이콘 표시 (맨 위 줄)", nil, "아이콘과 툴팁을 이 주문으로 보여 줍니다. 맨 위 줄에 둡니다" },
}
local SPELL_CMD = { ["/cast"] = true, ["/use"] = true }
-- 주문 대신 말할 내용을 쓰는 명령어
local CHAT_CMD = { ["/p"] = true, ["/s"] = true, ["/y"] = true, ["/g"] = true, ["/ra"] = true, ["/rw"] = true, ["/e"] = true, ["/w"] = true }

local TARGETS = {
  { "", "기본 (현재 대상)" }, { "@player", "나 자신" }, { "@mouseover", "마우스를 올린 대상" },
  { "@mouseover*", "마우스 올린 대상 (없으면 현재 대상)" },
  { "@mouseover*help", "마우스 올린 아군 (없으면 현재 대상)" }, { "@mouseover*harm", "마우스 올린 적 (없으면 현재 대상)" },
  { "@target", "현재 대상" }, { "@targettarget", "대상의 대상" },
  { "@pet", "소환수" }, { "@party1", "파티원 1" }, { "@party2", "파티원 2" }, { "@party3", "파티원 3" }, { "@party4", "파티원 4" },
  { "@cursor", "마우스 위치 (지면 주문)" },
}

-- 자주 쓰는 조건 (버튼), 더 보기 조건
local CONDS = {
  { "mod:shift", "Shift", "Shift 키를 누르고 있을 때" }, { "mod:ctrl", "Ctrl", "Ctrl 키를 누르고 있을 때" },
  { "mod:alt", "Alt", "Alt 키를 누르고 있을 때" }, { "nomod", "키 안 누름", "Shift/Ctrl/Alt 를 아무것도 안 눌렀을 때" },
  { "combat", "전투 중", "전투 중일 때" }, { "nocombat", "전투 아님", "전투 중이 아닐 때" },
  { "harm", "적 대상", "대상이 공격할 수 있는 적일 때" }, { "help", "아군 대상", "대상이 도울 수 있는 아군일 때" },
  { "nodead", "살아 있음", "대상이 살아 있을 때" }, { "dead", "죽음", "대상이 죽었을 때" },
  { "exists", "대상 있음", "대상이 있을 때" }, { "noexists", "대상 없음", "대상이 없을 때" },
}
local MORE_CONDS = {
  { "stealth", "은신 중" }, { "nostealth", "은신 아님" }, { "mounted", "탈것 탐" }, { "nomounted", "탈것 안 탐" },
  { "group", "내가 파티/공격대 중" }, { "group:raid", "내가 공격대 중" }, { "pet", "소환수 있음" }, { "nopet", "소환수 없음" },
  { "channeling", "정신 집중 중" }, { "nochanneling", "정신 집중 아님" }, { "indoors", "실내" }, { "outdoors", "실외" },
  { "swimming", "수영 중" }, { "stance:1", "태세/형상 1" }, { "stance:2", "태세/형상 2" }, { "stance:3", "태세/형상 3" },
  { "nostance", "태세 없음" }, { "form:1", "형상 1" }, { "resting", "휴식 중" }, { "button:2", "오른쪽 클릭으로 눌렀을 때" }, { "btn:2", "오른쪽 클릭 (짧은 표기)" }, { "btn:1", "왼쪽 클릭/단축키" },
}
local KNOWN_COND = {}
for _, c in ipairs(CONDS) do KNOWN_COND[c[1]] = c[2] end
for _, c in ipairs(MORE_CONDS) do KNOWN_COND[c[1]] = c[2] end
local KNOWN_CMD = {}
for _, c in ipairs(COMMANDS) do KNOWN_CMD[c[1]] = c[2] end

---------------------------------------------------------------------------
-- 줄 해석 / 만들기
---------------------------------------------------------------------------
-- 반환: { cmd, target, conds = {}, fallback, arg, complex }
local function Parse(line)
  local p = { conds = {} }
  local cmd, rest = line:match("^(%S+)%s*(.*)$")
  p.cmd = cmd or ""
  rest = rest or ""
  local opt, after = rest:match("^%[([^%]]*)%](.*)$")
  if opt then
    for tok in opt:gmatch("[^,]+") do
      tok = strtrim(tok)
      if tok:sub(1, 1) == "@" then p.target = tok
      elseif tok:sub(1, 7) == "target=" then p.target = "@" .. tok:sub(8)
      elseif tok ~= "" then p.conds[#p.conds + 1] = tok end
    end
    after = after or ""
    if after:sub(1, 2) == "[]" then p.fallback = true; after = after:sub(3)
    elseif after:sub(1, 1) == "[" then p.complex = true end
    rest = strtrim(after)
  end
  if rest:find(";", 1, true) then p.complex = true end
  p.arg = rest
  return p
end

local function Build(p)
  local parts = {}
  if p.target and p.target ~= "" then parts[#parts + 1] = p.target end
  for _, c in ipairs(p.conds) do parts[#parts + 1] = c end
  local s = p.cmd
  if #parts > 0 then s = s .. " [" .. table.concat(parts, ",") .. "]" .. (p.fallback and "[]" or "") end
  if p.arg and p.arg ~= "" then s = s .. " " .. p.arg end
  return s
end

-- 게임이 모를 수 있는 부분 (경고 표시용)
local function Warn(line)
  local p = Parse(line)
  if p.cmd ~= "" and not KNOWN_CMD[p.cmd] and p.cmd:sub(1, 1) == "/" then return "목록에 없는 명령어: " .. p.cmd end
  if p.cmd == "/run" or p.cmd == "/script" then return "포에버에서 동작하지 않는 명령어" end
  if p.target == "@focus" then return "포에버에서는 주시 대상이 동작하지 않음" end
  if p.target == "@mouseover" then
    for _, c in ipairs(p.conds) do
      if c == "group" or c == "group:raid" then
        return "group 은 '내가 파티 중'이라는 뜻입니다. 마우스 올린 아군만 고르려면 대상에서 '마우스 올린 아군'을 고르세요"
      end
    end
  end
  for _, c in ipairs(p.conds) do
    local base = c:gsub("^no", "")
    if not KNOWN_COND[c] and not KNOWN_COND[base] and not c:find("^mod") and not c:find("^stance") and not c:find("^form") then
      return "확인 안 된 조건: " .. c
    end
  end
end

---------------------------------------------------------------------------
-- 상태
---------------------------------------------------------------------------
local work = {}     -- 편집 중인 줄 목록 (그룹마다 새로 채움)
local sel = 1
local scroll = 0
local ROWS, ROW_H = 12, 22

local function G() return UI.G() end

local function LoadWork()
  local g = G()
  if not g then return end
  wipe(work)
  if g.custom and g.lines then
    for i, l in ipairs(g.lines) do work[i] = l end
  else
    local body = UI.buildBody(g)
    for l in (body .. "\n"):gmatch("(.-)\n") do if strtrim(l) ~= "" then work[#work + 1] = l end end
  end
  if sel > #work then sel = math.max(1, #work) end
end

local Refresh -- forward

local function Commit()
  local g = G()
  g.custom = true
  g.lines = {}
  for i, l in ipairs(work) do g.lines[i] = l end
  UI.markDirty("adv")
  Refresh()
end

---------------------------------------------------------------------------
-- 화면
---------------------------------------------------------------------------
local right = UI.right
local A = CreateFrame("Frame", nil, right, "BackdropTemplate")
A:SetPoint("TOPLEFT", 0, -88)
A:SetPoint("BOTTOMRIGHT", 0, 52)
A:SetFrameLevel(right:GetFrameLevel() + 20)
UI.flat(A, C.BG)
A:EnableMouse(true)
A:Hide()

-- 기본 / 상세옵션 탭 (그룹 이름 오른쪽)
local tBasic = UI.makeButton(right, "기본", 56, 22)
local tAdv = UI.makeButton(right, "상세옵션", 70, 22)
tAdv:SetPoint("TOPRIGHT", 0, -2)
tBasic:SetPoint("RIGHT", tAdv, "LEFT", -4, 0)
local badge = Txt(right, 11, true)
badge:SetPoint("RIGHT", tBasic, "LEFT", -8, 0)

-- 상세 그룹일 때 기본 탭을 덮는 안내판 (빈 슬롯을 잘못 건드려 상세 내용이 사라지지 않게)
local cover = CreateFrame("Frame", nil, right, "BackdropTemplate")
cover:SetPoint("TOPLEFT", 0, -88)
cover:SetPoint("BOTTOMRIGHT", 0, 52)
cover:SetFrameLevel(right:GetFrameLevel() + 19)
UI.flat(cover, C.BG)
cover:EnableMouse(true)
cover:Hide()
local coverTitle = Txt(cover, 13, true)
coverTitle:SetPoint("TOPLEFT", 10, -10)
coverTitle:SetText("|cffe6c229상세옵션으로 만든 매크로예요|r")
local coverHelp = Txt(cover, 11, false, true)
coverHelp:SetPoint("TOPLEFT", 10, -32)
coverHelp:SetPoint("RIGHT", -10, 0)
coverHelp:SetJustifyH("LEFT")
coverHelp:SetText("기본 탭의 슬롯은 쓰지 않습니다. 내용을 고치려면 [상세옵션에서 고치기]를 누르세요.")
local coverBox = CreateFrame("Frame", nil, cover, "BackdropTemplate")
coverBox:SetPoint("TOPLEFT", 10, -54)
coverBox:SetPoint("BOTTOMRIGHT", -10, 42)
UI.flat(coverBox, C.PANEL)
local coverLines = Txt(coverBox, 12)
coverLines:SetPoint("TOPLEFT", 8, -8)
coverLines:SetPoint("BOTTOMRIGHT", -8, 8)
coverLines:SetJustifyH("LEFT")
coverLines:SetJustifyV("TOP")
local coverEdit = UI.makeButton(cover, "상세옵션에서 고치기", 150, 24)
coverEdit:SetPoint("BOTTOMLEFT", 10, 10)
local coverBasic = UI.makeButton(cover, "기본 방식으로 바꾸기", 150, 24)
coverBasic:SetPoint("LEFT", coverEdit, "RIGHT", 8, 0)
coverBasic:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("상세 내용을 보관해 두고 슬롯 방식으로 바꿉니다.\n상세옵션의 '이전 상세 내용 복원'으로 되돌릴 수 있어요.", 1, 1, 1, 1, true)
  GameTooltip:Show()
end)
coverBasic:SetScript("OnLeave", function(self) self:SetActive(self.active); GameTooltip:Hide() end)

local function ShowAdv(on)
  A:SetShown(on)
  tBasic:SetActive(not on)
  tAdv:SetActive(on)
  if on then LoadWork() end
  Refresh()
end
coverEdit:SetScript("OnClick", function() ShowAdv(true) end)
coverBasic:SetScript("OnClick", function()
  local g = G()
  if not g then return end
  if g.custom then g.linesBackup = g.lines end
  g.custom, g.lines = nil, nil
  UI.markDirty("adv")
  if F.Refresh then F.Refresh() end
end)
tBasic:SetScript("OnClick", function() ShowAdv(false) end)
tAdv:SetScript("OnClick", function() ShowAdv(true) end)
tBasic:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
tAdv:SetScript("OnLeave", function(self) self:SetActive(self.active) end)

-- 왼쪽: 줄 목록
local list = CreateFrame("Frame", nil, A, "BackdropTemplate")
list:SetPoint("TOPLEFT", 0, -18)
list:SetSize(236, ROWS * ROW_H + 8)
UI.flat(list, C.PANEL)
local listLabel = Txt(A, 11, false, true)
listLabel:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, 3)
listLabel:SetText("매크로 줄 (끌어서 순서 변경)")

local rows = {}
local dragFrom
local function RowAtCursor()
  local _, y = GetCursorPosition()
  y = y / list:GetEffectiveScale()
  local top = list:GetTop() - 4
  local idx = math.floor((top - y) / ROW_H) + 1 + scroll
  return math.max(1, math.min(#work, idx))
end

for i = 1, ROWS do
  local r = CreateFrame("Button", nil, list, "BackdropTemplate")
  r:SetSize(228, ROW_H - 2)
  r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
  r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  r:SetBackdropColor(0, 0, 0, 0)
  r.grip = Txt(r, 11, false, true); r.grip:SetPoint("LEFT", 2, 0); r.grip:SetText("≡")
  r.num = Txt(r, 11, false, true); r.num:SetPoint("LEFT", 14, 0); r.num:SetWidth(16); r.num:SetJustifyH("RIGHT")
  r.text = Txt(r, 11); r.text:SetPoint("LEFT", 34, 0); r.text:SetWidth(178); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
  r.warn = Txt(r, 12, true); r.warn:SetPoint("RIGHT", -2, 0); r.warn:SetText("!"); r.warn:SetTextColor(1, 0.75, 0.2)
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnClick", function(self) sel = self.idx; Refresh() end)
  r:SetScript("OnDragStart", function(self) dragFrom = self.idx end)
  r:SetScript("OnDragStop", function()
    if not dragFrom then return end
    local to = RowAtCursor()
    if to ~= dragFrom then
      local l = table.remove(work, dragFrom)
      table.insert(work, to, l)
      sel = to
      Commit()
    end
    dragFrom = nil
  end)
  r:SetScript("OnEnter", function(self)
    if not self.idx then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(work[self.idx] or "", 1, 1, 1, 1, true)
    local w = Warn(work[self.idx] or "")
    if w then GameTooltip:AddLine("주의: " .. w, 1, 0.75, 0.2, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
end
list:EnableMouseWheel(true)
list:SetScript("OnMouseWheel", function(_, d) scroll = math.max(0, math.min(math.max(0, #work - ROWS), scroll - d)); Refresh() end)

local function smallBtn(text, w, x, y, fn, tip)
  local b = UI.makeButton(A, text, w, 22)
  b:SetPoint("TOPLEFT", list, "BOTTOMLEFT", x, y)
  b:SetScript("OnClick", fn)
  if tip then
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
  end
  b:SetScript("OnLeave", function(self) GameTooltip:Hide(); self:SetActive(self.active) end)
  return b
end
smallBtn("+ 줄", 50, 0, -4, function() table.insert(work, sel + 1, "/cast "); sel = math.min(#work, sel + 1); Commit() end, "고른 줄 아래에 새 줄 추가")
smallBtn("복제", 44, 54, -4, function() if work[sel] then table.insert(work, sel + 1, work[sel]); sel = sel + 1; Commit() end end, "고른 줄을 하나 더 만들기")
smallBtn("삭제", 44, 102, -4, function() if work[sel] then table.remove(work, sel); sel = math.max(1, sel - 1); Commit() end end, "고른 줄 지우기")
smallBtn("▲", 32, 150, -4, function() if sel > 1 then work[sel], work[sel - 1] = work[sel - 1], work[sel]; sel = sel - 1; Commit() end end, "위로")
smallBtn("▼", 32, 186, -4, function() if sel < #work then work[sel], work[sel + 1] = work[sel + 1], work[sel]; sel = sel + 1; Commit() end end, "아래로")

-- 오른쪽: 속성 패널
local prop = CreateFrame("Frame", nil, A, "BackdropTemplate")
prop:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
prop:SetPoint("BOTTOMRIGHT", A, "TOPRIGHT", 0, -18 - (ROWS * ROW_H + 8))
UI.flat(prop, C.PANEL)
local propLabel = Txt(A, 11, false, true)
propLabel:SetPoint("BOTTOMLEFT", prop, "TOPLEFT", 0, 3)

local function label(text, y)
  local t = Txt(prop, 11, false, true)
  t:SetPoint("TOPLEFT", 6, y)
  t:SetText(text)
  return t
end

-- 고르기 메뉴 (명령어/대상/더 보기 조건 공용)
local menu = CreateFrame("Frame", nil, A, "BackdropTemplate")
menu:SetFrameLevel(A:GetFrameLevel() + 30)
UI.flat(menu, C.PANEL)
menu:Hide()
-- 메뉴 바깥을 누르면 닫기 (상세옵션 패널 전체를 덮는 투명 판)
local catcher = CreateFrame("Button", nil, A)
catcher:SetAllPoints(A)
catcher:SetFrameLevel(A:GetFrameLevel() + 29)
catcher:RegisterForClicks("AnyUp")
catcher:SetScript("OnClick", function() GameTooltip:Hide(); menu:Hide() end)
catcher:Hide()
menu:SetScript("OnShow", function() catcher:Show() end)
menu:SetScript("OnHide", function() catcher:Hide(); menu.anchor = nil end)
local menuBtns = {}
local function OpenMenu(anchor, items, onPick, width)
  -- 같은 버튼을 다시 누르면 닫기
  if menu:IsShown() and menu.anchor == anchor then menu:Hide() return end
  menu.anchor = anchor
  for _, b in ipairs(menuBtns) do b:Hide() end
  local n = #items
  local cols = n > 14 and 2 or 1
  local per = math.ceil(n / cols)
  width = width or 180
  local RH = 20
  menu:SetSize(width * cols + 8, per * RH + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  for i, it in ipairs(items) do
    local b = menuBtns[i]
    if not b then
      b = CreateFrame("Button", nil, menu, "BackdropTemplate")
      b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
      b.t = Txt(b, 11); b.t:SetPoint("LEFT", 4, 0); b.t:SetJustifyH("LEFT")
      b.t:SetWordWrap(false)
      if b.t.SetMaxLines then b.t:SetMaxLines(1) end
      b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 0.5)
        if self.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
      end)
      b:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0); GameTooltip:Hide() end)
      menuBtns[i] = b
    end
    b:SetSize(width, RH)
    b.tip = it.tip
    b:SetBackdropColor(0, 0, 0, 0)
    local col = math.floor((i - 1) / per)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4 + col * width, -4 - ((i - 1) % per) * RH)
    b.t:SetWidth(width - 8)
    b.t:SetText(it.label)
    b:SetScript("OnClick", function() GameTooltip:Hide(); menu:Hide(); onPick(it.value) end)
    b:Show()
  end
  menu:Show()
end
A:HookScript("OnHide", function() menu:Hide() end)

local function pickBox(y, w)
  local b = UI.makeButton(prop, "", w or 178, 22)
  b:SetPoint("TOPLEFT", 6, y)
  b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 6, 0); b.text:SetWidth((w or 178) - 20); b.text:SetJustifyH("LEFT")
  local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -5, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"); arrow:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
  return b
end

label("명령어", -6)
local cmdBox = pickBox(-20)
local spellLabel = label("주문 (주문책에서 끌어다 놓기)", -48)
local spellSlot = CreateFrame("Button", nil, prop, "BackdropTemplate")
spellSlot:SetSize(178, 24)
spellSlot:SetPoint("TOPLEFT", 6, -62)
UI.flat(spellSlot, { 0, 0, 0 })
spellSlot.icon = spellSlot:CreateTexture(nil, "ARTWORK"); spellSlot.icon:SetSize(20, 20); spellSlot.icon:SetPoint("LEFT", 2, 0)
spellSlot.t = Txt(spellSlot, 11); spellSlot.t:SetPoint("LEFT", 26, 0); spellSlot.t:SetWidth(148); spellSlot.t:SetJustifyH("LEFT")
local chatEdit = CreateFrame("EditBox", nil, prop, "BackdropTemplate")
chatEdit:SetSize(178, 24)
chatEdit:SetPoint("TOPLEFT", 6, -62)
UI.flat(chatEdit, { 0, 0, 0 })
chatEdit:SetFontObject(ChatFontNormal)
chatEdit:SetTextInsets(6, 6, 0, 0)
chatEdit:SetAutoFocus(false)
chatEdit:SetMaxLetters(200)
chatEdit:Hide()
label("대상", -92)
local targetBox = pickBox(-106)
label("조건 (눌러서 켜기/끄기)", -134)

local chips = {}
local function chip(def, i)
  local b = UI.makeButton(prop, def[2], 58, 20)
  local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
  b:SetPoint("TOPLEFT", 6 + col * 60, -148 - row * 22)
  b.cond = def[1]
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(def[2]); GameTooltip:AddLine(def[3] .. "  [" .. def[1] .. "]", 1, 1, 1, true); GameTooltip:Show() end)
  b:SetScript("OnLeave", function(self) GameTooltip:Hide(); self:SetActive(self.active) end)
  return b
end
for i, def in ipairs(CONDS) do chips[i] = chip(def, i) end
local moreBtn = UI.makeButton(prop, "조건 더 보기 +", 178, 20)
moreBtn:SetPoint("TOPLEFT", 6, -148 - 4 * 22)
moreBtn:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
local extraText = Txt(prop, 10, false, true)
extraText:SetPoint("TOPLEFT", moreBtn, "BOTTOMLEFT", 0, -2)
extraText:SetWidth(178); extraText:SetJustifyH("LEFT")

-- 직접 입력 (전체 너비)
local rawLabel = Txt(A, 11, false, true)
rawLabel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -32)
rawLabel:SetText("직접 입력 (이 줄 그대로) · Enter 로 적용")
local rawEdit = UI.makeEdit(A, 428, 255)
rawEdit:SetPoint("TOPLEFT", rawLabel, "BOTTOMLEFT", 0, -2)

-- 미리보기
local prevLabel = Txt(A, 11, false, true)
prevLabel:SetPoint("TOPLEFT", rawEdit, "BOTTOMLEFT", 0, -8)
prevLabel:SetText("미리보기 (실제 매크로)")
local countText = Txt(A, 11, true)
countText:SetPoint("TOPRIGHT", rawEdit, "BOTTOMRIGHT", 0, -8)
local bar = A:CreateTexture(nil, "ARTWORK")
bar:SetPoint("TOPLEFT", prevLabel, "BOTTOMLEFT", 0, -3)
bar:SetHeight(3)
local barBg = A:CreateTexture(nil, "BACKGROUND")
barBg:SetPoint("TOPLEFT", prevLabel, "BOTTOMLEFT", 0, -3); barBg:SetSize(428, 3); barBg:SetColorTexture(0.055, 0.085, 0.10, 1)
local prevText = Txt(A, 10, false, true)
prevText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
prevText:SetWidth(428); prevText:SetJustifyH("LEFT"); prevText:SetMaxLines(4)

local rebuildBtn = UI.makeButton(A, "기본 설정으로 다시 만들기", 170, 22)
rebuildBtn:SetPoint("BOTTOMLEFT", 0, 2)
local restoreBtn = UI.makeButton(A, "이전 상세 내용 복원", 130, 22)
restoreBtn:SetPoint("LEFT", rebuildBtn, "RIGHT", 6, 0)
local copyBtn = UI.makeButton(A, "글자로 복사/붙여넣기", 130, 22)
copyBtn:SetPoint("BOTTOMRIGHT", 0, 2)
for _, b in ipairs({ rebuildBtn, restoreBtn, copyBtn }) do b:SetScript("OnLeave", function(self) self:SetActive(self.active) end) end

---------------------------------------------------------------------------
-- 동작
---------------------------------------------------------------------------
local function CurP() return Parse(work[sel] or "") end
local function SetP(p) work[sel] = Build(p); Commit() end

cmdBox:SetScript("OnClick", function(self)
  local items = {}
  for _, c in ipairs(COMMANDS) do items[#items + 1] = { label = c[1] .. "  |cffaaaaaa" .. c[2] .. "|r", value = c[1], tip = c[4] and (c[1] .. "\n" .. c[4]) or nil } end
  OpenMenu(self, items, function(v)
    local p = CurP()
    if p.complex then work[sel] = v .. " " .. (p.arg or "") ; Commit() return end
    p.cmd = v
    SetP(p)
  end, 210)
end)

targetBox:SetScript("OnClick", function(self)
  local items = {}
  for _, t in ipairs(TARGETS) do items[#items + 1] = { label = t[2] .. (t[1] ~= "" and ("  " .. t[1]:match("^[^*]*")) or ""), value = t[1] } end
  OpenMenu(self, items, function(v)
    local p = CurP()
    if p.complex then out("이 줄은 구조가 복잡해서 아래 '직접 입력'으로 고쳐 주세요.") return end
    local kind = v:match("^@mouseover%*(%a+)$")
    if kind then
      -- 마우스 올린 아군/적: 아군·적·살아 있음 조건을 새로 정함 (실제 매크로에서는 마우스 대상에만 붙음)
      local keep = {}
      for _, c in ipairs(p.conds) do
        if c ~= "help" and c ~= "harm" and c ~= "nodead" and c ~= "dead" then keep[#keep + 1] = c end
      end
      keep[#keep + 1] = kind
      keep[#keep + 1] = "nodead"
      p.conds, p.target, p.fallback = keep, "@mouseover", true
    elseif v == "@mouseover*" then p.target, p.fallback = "@mouseover", true
    else p.target, p.fallback = v, nil end
    SetP(p)
  end, 210)
end)

for _, b in ipairs(chips) do
  b:SetScript("OnClick", function(self)
    local p = CurP()
    if p.complex then out("이 줄은 구조가 복잡해서 아래 '직접 입력'으로 고쳐 주세요.") return end
    local found
    for i, c in ipairs(p.conds) do if c == self.cond then found = i end end
    if found then table.remove(p.conds, found) else p.conds[#p.conds + 1] = self.cond end
    SetP(p)
  end)
end

moreBtn:SetScript("OnClick", function(self)
  local p = CurP()
  local on = {}
  for _, c in ipairs(p.conds) do on[c] = true end
  local items = {}
  for _, c in ipairs(MORE_CONDS) do items[#items + 1] = { label = (on[c[1]] and "|cff4db8e0● |r" or "○ ") .. c[2] .. "  [" .. c[1] .. "]", value = c[1] } end
  OpenMenu(self, items, function(v)
    local q = CurP()
    if q.complex then out("이 줄은 구조가 복잡해서 아래 '직접 입력'으로 고쳐 주세요.") return end
    local found
    for i, c in ipairs(q.conds) do if c == v then found = i end end
    if found then table.remove(q.conds, found) else q.conds[#q.conds + 1] = v end
    SetP(q)
  end, 170)
end)

local function takeSpell()
  local kind, a, b, c = GetCursorInfo()
  if kind ~= "spell" then return end
  local id = c or b
  if type(a) == "number" and not c and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
    local info = C_SpellBook.GetSpellBookItemInfo(a, Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
    id = (info and info.spellID) or id
  end
  local name = type(id) == "number" and C_Spell.GetSpellName(id)
  ClearCursor()
  if not name then return end
  local p = CurP()
  if p.cmd == "/castsequence" or p.cmd == "/castrandom" then
    p.arg = (p.arg and p.arg ~= "" and (p.arg .. ", ") or "") .. name
  elseif p.cmd == "#showtooltip" then
    p.arg = name
  else
    if not SPELL_CMD[p.cmd] then p.cmd = "/cast" end
    p.arg = name
  end
  SetP(p)
end
spellSlot:SetScript("OnReceiveDrag", takeSpell)
chatEdit:SetScript("OnEnterPressed", function(self)
  self:ClearFocus()
  if not work[sel] then return end
  local p = CurP()
  p.arg = strtrim(self:GetText() or "")
  SetP(p)
end)
chatEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
spellSlot:SetScript("OnClick", function() if GetCursorInfo() then takeSpell() end end)

rawEdit:SetScript("OnEnterPressed", function(self)
  self:ClearFocus()
  if not work[sel] then return end
  work[sel] = strtrim(self:GetText())
  Commit()
end)

rebuildBtn:SetScript("OnClick", function()
  local g = G()
  if g.custom then g.linesBackup = g.lines end
  g.custom, g.lines = nil, nil
  UI.markDirty("adv")
  out("이 그룹을 기본 설정으로 다시 만들었어요. '이전 상세 내용 복원'으로 되돌릴 수 있어요.")
  LoadWork(); Refresh()
end)
restoreBtn:SetScript("OnClick", function()
  local g = G()
  if not g.linesBackup then return end
  g.lines, g.linesBackup, g.custom = g.linesBackup, nil, true
  UI.markDirty("adv")
  LoadWork(); Refresh()
end)

-- 글자로 복사 / 붙여넣기 창
local cp = CreateFrame("Frame", "RotaKeyMacroText", F, "BackdropTemplate")
cp:SetSize(440, 260)
cp:SetPoint("CENTER", F, "CENTER", 0, 0)
cp:SetFrameLevel(F:GetFrameLevel() + 60)
UI.flat(cp, C.BG)
cp:EnableMouse(true)
cp:Hide()
local cpTitle = Txt(cp, 13, true); cpTitle:SetPoint("TOPLEFT", 10, -10)
cpTitle:SetText("매크로 글자로 복사 / 붙여넣기")
local cpHelp = Txt(cp, 11, false, true); cpHelp:SetPoint("TOPLEFT", 10, -28)
cpHelp:SetText("Ctrl+A, Ctrl+C 로 복사 · 다른 매크로를 붙여 넣고 [적용]")
local cpBox = CreateFrame("Frame", nil, cp, "BackdropTemplate")
cpBox:SetPoint("TOPLEFT", 10, -46); cpBox:SetPoint("BOTTOMRIGHT", -10, 38)
UI.flat(cpBox, C.PANEL)
local cpEdit = CreateFrame("EditBox", nil, cpBox)
cpEdit:SetMultiLine(true); cpEdit:SetFontObject(ChatFontNormal); cpEdit:SetAutoFocus(false)
cpEdit:SetPoint("TOPLEFT", 6, -6); cpEdit:SetPoint("BOTTOMRIGHT", -6, 6)
cpEdit:SetScript("OnEscapePressed", function() cp:Hide() end)
local cpApply = UI.makeButton(cp, "적용", 80, 24, true); cpApply:SetPoint("BOTTOMRIGHT", -10, 8)
local cpClose = UI.makeButton(cp, "닫기", 80, 24); cpClose:SetPoint("RIGHT", cpApply, "LEFT", -6, 0)
cpClose:SetScript("OnClick", function() cp:Hide() end)
cpApply:SetScript("OnClick", function()
  wipe(work)
  for l in (cpEdit:GetText() .. "\n"):gmatch("(.-)\n") do if strtrim(l) ~= "" then work[#work + 1] = strtrim(l) end end
  sel = 1; scroll = 0
  cp:Hide()
  Commit()
end)
copyBtn:SetScript("OnClick", function()
  cpEdit:SetText(table.concat(work, "\n"))
  cp:Show(); cpEdit:SetFocus(); cpEdit:HighlightText()
end)

---------------------------------------------------------------------------
-- 새로 그리기
---------------------------------------------------------------------------
function Refresh()
  local g = G()
  if not g then return end
  badge:SetText(g.custom and "|cffe6c229상세 그룹|r" or "")
  local showCover = g.custom and g.lines and not A:IsShown()
  cover:SetShown(showCover and true or false)
  if showCover then
    local t = {}
    for i, l in ipairs(g.lines) do t[#t + 1] = "|cff6f7a88" .. i .. "|r  " .. l end
    coverLines:SetText(#t > 0 and table.concat(t, "\n") or "(줄 없음)")
  end
  if not A:IsShown() then return end
  scroll = math.max(0, math.min(scroll, math.max(0, #work - ROWS)))
  if sel > scroll + ROWS then scroll = sel - ROWS elseif sel <= scroll then scroll = math.max(0, sel - 1) end
  for i = 1, ROWS do
    local r, idx = rows[i], i + scroll
    if work[idx] then
      r.idx = idx
      r.num:SetText(idx)
      r.text:SetText(work[idx])
      r.warn:SetShown(Warn(work[idx]) ~= nil)
      if idx == sel then r:SetBackdropColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 0.35) else r:SetBackdropColor(0, 0, 0, 0) end
      r:Show()
    else
      r.idx = nil
      r:Hide()
    end
  end
  local p = CurP()
  propLabel:SetText(work[sel] and (sel .. "번 줄 속성") or "줄이 없습니다. [+ 줄]로 추가하세요.")
  cmdBox.text:SetText(p.cmd ~= "" and (p.cmd .. "  " .. (KNOWN_CMD[p.cmd] or "")) or "명령어 고르기")
  local isChat = CHAT_CMD[p.cmd] and true or false
  spellSlot:SetShown(not isChat)
  chatEdit:SetShown(isChat)
  spellLabel:SetText(isChat and "말할 내용 (%t = 대상 이름) · Enter 로 적용" or "주문 (주문책에서 끌어다 놓기)")
  if isChat and not chatEdit:HasFocus() then chatEdit:SetText(p.arg or "") end
  local sname = (SPELL_CMD[p.cmd] or p.cmd == "#showtooltip") and p.arg or ((p.cmd == "/castsequence" or p.cmd == "/castrandom") and p.arg) or nil
  if sname and sname ~= "" then
    local first = sname:gsub("^reset=%S+%s*", ""):match("^([^,]+)")
    local icon = first and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(strtrim(first))
    spellSlot.icon:SetTexture(icon or 134400)
    spellSlot.t:SetText(sname)
  else
    spellSlot.icon:SetTexture(134400)
    spellSlot.t:SetText("주문을 끌어다 놓으세요")
  end
  local tl = "기본 (현재 대상)"
  local moKind = "@mouseover*"
  if p.target == "@mouseover" and p.fallback then
    for _, c in ipairs(p.conds) do
      if c == "help" then moKind = "@mouseover*help" elseif c == "harm" then moKind = "@mouseover*harm" end
    end
  end
  for _, t in ipairs(TARGETS) do
    local v = t[1]
    if p.target == "@mouseover" and p.fallback then
      if v == moKind then tl = t[2] end
    elseif v == (p.target or "") then tl = t[2] end
  end
  targetBox.text:SetText(p.complex and "복잡한 줄 (직접 입력으로)" or tl)
  local on = {}
  for _, c in ipairs(p.conds) do on[c] = true end
  for _, b in ipairs(chips) do b:SetActive(on[b.cond] and true or false) end
  local extra = {}
  for _, c in ipairs(p.conds) do
    local isChip = false
    for _, d in ipairs(CONDS) do if d[1] == c then isChip = true end end
    if not isChip then extra[#extra + 1] = KNOWN_COND[c] or c end
  end
  extraText:SetText(#extra > 0 and ("추가 조건: " .. table.concat(extra, ", ")) or "")
  if not rawEdit:HasFocus() then rawEdit:SetText(work[sel] or "") end
  -- 실제로 게임에 들어가는 글 (같은 명령의 조건 줄은 한 줄로 합쳐짐)
  local body, merged
  if UI.customBody then body, merged = UI.customBody(work) else body = table.concat(work, "\n") end
  prevLabel:SetText(merged and "미리보기 (실제 매크로 · 조건 줄을 한 줄로 합침)" or "미리보기 (실제 매크로)")
  local n, lim = #body, UI.MACRO_LIMIT
  countText:SetText(("%d / %d"):format(n, lim))
  local col = n > lim and { 0.9, 0.35, 0.32 } or (n > lim * 0.85 and { 0.9, 0.75, 0.2 } or { 0.45, 0.85, 0.55 })
  countText:SetTextColor(col[1], col[2], col[3])
  bar:SetColorTexture(col[1], col[2], col[3], 1)
  bar:SetWidth(math.max(1, math.min(1, n / lim) * 428))
  prevText:SetText((body:gsub("\n", "  |cff6f7a88/|r  ")))
  restoreBtn:SetShown(g.linesBackup ~= nil)
end

-- 그룹을 바꾸거나 기본 화면이 바뀌면 같이 갱신
local origRefresh = F.Refresh
F.Refresh = function(...)
  origRefresh(...)
  if A:IsShown() then LoadWork() end
  Refresh()
end
F:HookScript("OnShow", function() ShowAdv(false) end)
