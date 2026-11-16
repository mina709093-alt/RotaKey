-- 상수팩 공통 모듈 (SangsuPack.lua)
-- 상수팩에 속한 모든 애드온에 같은 파일로 들어 있습니다.
-- 여러 애드온에 들어 있어도 한 번만 동작하며, 모듈 번호가 가장 높은 파일의 코드가 쓰입니다.
--
-- 하는 일
--   1) 같은 길드 / 파티 / 공격대에 있는 상수팩 사용자끼리 애드온 버전을 주고받습니다. (애드온 메시지, 화면에 보이지 않음)
--   2) 내 애드온보다 새 버전을 가진 사람이 있으면, 채팅창에 업데이트 알림(WowUp 안내)을 띄우고 30분마다 다시 알려 줍니다.
--   3) /상수팩 : 설치된 상수팩 애드온과 버전, 알려진 최신 버전을 보여 줍니다.
--   4) 업데이트 후 첫 접속(또는 첫 /리)에 한 번만, 바뀐 애드온 이름과 [업데이트 내역 보기] 링크를 채팅창에 띄웁니다.
--      링크를 누르거나 /상수팩 내역 을 입력하면 내역 창이 열립니다. (내역 글은 각 애드온 파일 안에 들어 있음)
--
-- 한계: 와우 애드온은 인터넷에 접속할 수 없습니다. 그래서 새 버전을 쓰는 사람이
--       같은 길드나 파티에 함께 접속해 있을 때만 업데이트를 알 수 있습니다.

local ADDON_NAME = ...
local MODULE_VERSION = 4

local SP = _G.SangsuPack
if not SP or (SP.moduleVersion or 0) < MODULE_VERSION then
    SP = SP or {}
    _G.SangsuPack = SP
    SP.moduleVersion = MODULE_VERSION

    -- 상수팩 안내 페이지 (WowUp 설치 방법과 애드온별 주소)
    SP.DOWNLOAD_URL = "https://github.com/mina709093-alt/SangsuPack"

    SP.PREFIX = "SangsuPack"
    SP.NOTIFY_INTERVAL = 30 * 60      -- 업데이트 알림 반복 간격 (초)
    SP.addons = SP.addons or {}       -- 내 애드온: 폴더명 -> { version, title }
    SP.newer = SP.newer or {}         -- 다른 사람에게서 알게 된 최신 버전: 폴더명 -> 버전
    SP.lastReply = SP.lastReply or {} -- 채널별 마지막 답장 시각

    local TAG = "|cffff9900[상수팩]|r "

    -----------------------------------------------------------------------
    -- 도구
    -----------------------------------------------------------------------
    local function IsSecret(v)
        if issecretvalue then
            local ok, r = pcall(issecretvalue, v)
            return ok and r
        end
        return false
    end

    local function Meta(addon, field)
        local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        if not fn then return nil end
        local ok, v = pcall(fn, addon, field)
        if ok and type(v) == "string" and v ~= "" then return v end
    end

    local function CleanTitle(t)
        t = tostring(t or "")
        t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return (t:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function Parts(v)
        local t = {}
        for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end

    -- a < b: -1, 같음: 0, a > b: 1
    function SP.Compare(a, b)
        local x, y = Parts(a), Parts(b)
        for i = 1, math.max(#x, #y) do
            local p, q = x[i] or 0, y[i] or 0
            if p ~= q then return p < q and -1 or 1 end
        end
        return 0
    end

    function SP.Print(msg)
        DEFAULT_CHAT_FRAME:AddMessage(TAG .. msg)
    end

    -----------------------------------------------------------------------
    -- 등록 (각 애드온의 toc 에 있는 ## Version 사용)
    -----------------------------------------------------------------------
    function SP:Register(addon)
        if not addon then return end
        local version = Meta(addon, "Version") or "0"
        local title = CleanTitle(Meta(addon, "Title-koKR") or Meta(addon, "Title") or addon)
        self.addons[addon] = { version = version:gsub("[,=|;]", ""), title = title }
    end

    -----------------------------------------------------------------------
    -- 보내기
    -----------------------------------------------------------------------
    local function BuildMessages()
        local items = {}
        for name, info in pairs(SP.addons) do items[#items + 1] = name .. "=" .. info.version end
        table.sort(items)
        local msgs, cur = {}, "V1|"
        for _, it in ipairs(items) do
            if #cur + #it + 1 > 240 then
                msgs[#msgs + 1] = cur
                cur = "V1|"
            end
            cur = cur .. (cur == "V1|" and "" or ",") .. it
        end
        if cur ~= "V1|" then msgs[#msgs + 1] = cur end
        return msgs
    end

    local function RawSend(msg, channel)
        local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
        if not fn then return end
        pcall(fn, SP.PREFIX, msg, channel)
    end

    local function GroupChannel()
        if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid and IsInRaid() then return "RAID" end
        if IsInGroup and IsInGroup() then return "PARTY" end
    end

    -- channels: { "GUILD", "PARTY" ... }  (귓속말은 쓰지 않음: 상대가 없을 때 시스템 알림이 반복되기 때문)
    function SP:Broadcast(channels)
        if InCombatLockdown and InCombatLockdown() then
            self.pendingBroadcast = true
            return
        end
        local msgs = BuildMessages()
        if #msgs == 0 then return end
        for _, ch in ipairs(channels) do
            for _, m in ipairs(msgs) do RawSend(m, ch) end
        end
    end

    function SP:BroadcastAll()
        local chans = {}
        if IsInGuild and IsInGuild() then chans[#chans + 1] = "GUILD" end
        local g = GroupChannel()
        if g then chans[#chans + 1] = g end
        self:Broadcast(chans)
    end

    -----------------------------------------------------------------------
    -- 알림
    -----------------------------------------------------------------------
    function SP:GetOutdated()
        local list = {}
        for name, newest in pairs(self.newer) do
            local mine = self.addons[name]
            if mine and SP.Compare(mine.version, newest) < 0 then
                list[#list + 1] = { name = name, title = mine.title, mine = mine.version, newest = newest }
            end
        end
        table.sort(list, function(a, b) return a.title < b.title end)
        return list
    end

    function SP:Notify()
        local list = self:GetOutdated()
        if #list == 0 then return end
        -- 1줄: 안내 문구 / 2줄: WowUp 안내 / 3줄: 안내 페이지 주소  (어떤 애드온이 바뀌었는지는 /상수팩 에서 확인)
        self.Print("|cffffd200최신 버전이 업데이트 되었습니다|r")
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200WowUp에서 업데이트 버튼을 눌러 주세요|r")
        if self.DOWNLOAD_URL and self.DOWNLOAD_URL ~= "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. self.DOWNLOAD_URL .. "|r")
        end
        PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081)
    end

    function SP:StartReminder()
        if self.ticker then return end
        self.ticker = C_Timer.NewTicker(self.NOTIFY_INTERVAL, function()
            SP:Notify()
        end)
    end

    -----------------------------------------------------------------------
    -- 받기
    -----------------------------------------------------------------------
    function SP:OnAddonMessage(prefix, msg, channel, sender)
        if prefix ~= self.PREFIX or IsSecret(msg) or type(msg) ~= "string" then return end
        local me = UnitName("player")
        local who = sender and Ambiguate and Ambiguate(sender, "none") or sender
        if who == me then return end
        local body = msg:match("^V1|(.*)$")
        if not body then return end

        local learned, iAmNewer = false, false
        for name, ver in body:gmatch("([^,=]+)=([^,]+)") do
            local mine = self.addons[name]
            if mine then
                local c = SP.Compare(mine.version, ver)
                if c < 0 then
                    if not self.newer[name] or SP.Compare(self.newer[name], ver) < 0 then
                        self.newer[name] = ver
                        learned = true
                    end
                elseif c > 0 then
                    iAmNewer = true
                end
            end
        end

        if learned then
            self:Notify()
            self:StartReminder()
        end

        -- 상대가 구버전이면 같은 채널로 내 버전을 알려 줌 (채널당 1분에 한 번)
        if iAmNewer and (channel == "GUILD" or channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT") then
            local now = GetTime()
            if not self.lastReply[channel] or now - self.lastReply[channel] > 60 then
                self.lastReply[channel] = now
                C_Timer.After(math.random(1, 5), function() SP:Broadcast({ channel }) end)
            end
        end
    end

    -----------------------------------------------------------------------
    -- /상수팩
    -----------------------------------------------------------------------
    function SP:ShowStatus()
        local names = {}
        for name in pairs(self.addons) do names[#names + 1] = name end
        table.sort(names, function(a, b) return self.addons[a].title < self.addons[b].title end)
        self.Print("설치된 상수팩 애드온 " .. #names .. "개")
        for _, name in ipairs(names) do
            local info = self.addons[name]
            local newest = self.newer[name]
            local state = (newest and SP.Compare(info.version, newest) < 0)
                and ("|cffff5555업데이트 필요 → " .. newest .. "|r") or "|cff33ff33최신|r"
            self.Print(string.format("  %s  %s  %s", info.title, info.version, state))
        end
        if self.DOWNLOAD_URL and self.DOWNLOAD_URL ~= "" then
            self:ShowCopyBox(self.DOWNLOAD_URL)
        else
            self.Print("최신 파일은 상수에게 받아 주세요.")
        end
    end

    function SP:ShowCopyBox(text)
        if not self.copyBox then
            local f = CreateFrame("Frame", "SangsuPackCopyFrame", UIParent, "BasicFrameTemplateWithInset")
            f:SetSize(420, 90)
            f:SetPoint("CENTER", 0, 120)
            f:SetFrameStrata("DIALOG")
            local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            if not f.TitleText then title:SetPoint("TOP", 0, -5) end
            title:SetText("상수팩 최신 파일 주소 (Ctrl+C 로 복사)")
            local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
            eb:SetSize(380, 24)
            eb:SetPoint("CENTER", 0, -8)
            eb:SetAutoFocus(true)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)
            eb:SetScript("OnEnterPressed", function() f:Hide() end)
            f.eb = eb
            tinsert(UISpecialFrames, "SangsuPackCopyFrame")
            self.copyBox = f
        end
        self.copyBox.eb:SetText(text)
        self.copyBox:Show()
        self.copyBox.eb:SetFocus()
        self.copyBox.eb:HighlightText()
    end


    -----------------------------------------------------------------------
    -- 업데이트 내역 (모듈 4)
    --   각 애드온이 SangsuPack:RegisterChangelog("폴더명", { { ver = "0.19.0", "줄1", "줄2" }, ... }) 로 등록
    --   (새 버전이 위로). 마지막으로 본 버전은 SangsuPackDB.seen[폴더명] 에 저장되어, 한 번 보여준 뒤에는 나오지 않습니다.
    -----------------------------------------------------------------------
    SP.changelogs = SP.changelogs or {}
    SP.baseline = SP.baseline or {}
    -- since: 이 번호가 도입되기 전에 설치돼 있던 사람에게는 이 버전 이후 내역만 보여 줌 (처음 도입 시 한 번)
    function SP:RegisterChangelog(addon, list, since)
        if addon and type(list) == "table" then
            self.changelogs[addon] = list
            if since then self.baseline[addon] = since end
        end
    end

    local LINK = "sangsupack:log"

    -- 이번에 처음 보는 업데이트: { {addon, title, version, from}, ... }
    function SP:CollectUpdated()
        SangsuPackDB = SangsuPackDB or {}
        SangsuPackDB.seen = SangsuPackDB.seen or {}
        local seen, list = SangsuPackDB.seen, {}
        for name, info in pairs(self.addons) do
            local prev = seen[name]
            if self.changelogs[name] and (prev == nil or SP.Compare(prev, info.version) < 0) then
                list[#list + 1] = { addon = name, title = info.title, version = info.version, from = prev or self.baseline[name] }
            end
            seen[name] = info.version
        end
        table.sort(list, function(a, b) return a.title < b.title end)
        return list
    end

    function SP:CheckUpdated()
        if self.updateChecked then return end
        self.updateChecked = true
        local list = self:CollectUpdated()
        if #list == 0 then return end
        self.lastUpdated = list
        local names = {}
        for _, u in ipairs(list) do names[#names + 1] = u.title .. " " .. u.version end
        self.Print("|cffffd200업데이트됨:|r " .. table.concat(names, ", "))
        DEFAULT_CHAT_FRAME:AddMessage("|Hsangsupack:log|h|cff66ccff[업데이트 내역 보기]|r|h")
    end

    -- 내역 글 만들기: from 보다 새롭고 현재 버전 이하인 항목을 모아 줌
    local function BuildLogText(list)
        local out = {}
        for _, u in ipairs(list) do
            out[#out + 1] = "|cffffd200" .. u.title .. "  " .. u.version .. "|r"
            local entries = SP.changelogs[u.addon] or {}
            local shown = 0
            for _, e in ipairs(entries) do
                local newer = (u.from == nil) or SP.Compare(e.ver, u.from) > 0
                if newer and SP.Compare(e.ver, u.version) <= 0 then
                    out[#out + 1] = "|cff66ccff" .. e.ver .. "|r" .. (e.date and ("  (" .. e.date .. ")") or "")
                    for _, line in ipairs(e) do out[#out + 1] = "  - " .. line end
                    shown = shown + 1
                end
            end
            if shown == 0 and entries[1] then
                out[#out + 1] = "|cff66ccff" .. entries[1].ver .. "|r"
                for _, line in ipairs(entries[1]) do out[#out + 1] = "  - " .. line end
            end
            out[#out + 1] = ""
        end
        return table.concat(out, "\n")
    end

    function SP:ShowChangelog()
        local list = self.lastUpdated
        if not list or #list == 0 then
            -- 방금 업데이트된 게 없으면 등록된 모든 애드온의 최근 내역을 보여 줌
            list = {}
            for name, info in pairs(self.addons) do
                if self.changelogs[name] then
                    list[#list + 1] = { addon = name, title = info.title, version = info.version, from = nil }
                end
            end
            table.sort(list, function(a, b) return a.title < b.title end)
        end
        if #list == 0 then self.Print("등록된 업데이트 내역이 없습니다.") return end
        if not self.logFrame then
            local f = CreateFrame("Frame", "SangsuPackLogFrame", UIParent, "BasicFrameTemplateWithInset")
            f:SetSize(520, 420)
            f:SetPoint("CENTER", 0, 20)
            f:SetFrameStrata("DIALOG")
            f:SetMovable(true)
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
            local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            if not f.TitleText then title:SetPoint("TOP", 0, -5) end
            title:SetText("상수팩 업데이트 내역")
            local sf = CreateFrame("ScrollFrame", "SangsuPackLogScroll", f, "UIPanelScrollFrameTemplate")
            sf:SetPoint("TOPLEFT", 12, -30)
            sf:SetPoint("BOTTOMRIGHT", -32, 12)
            local child = CreateFrame("Frame", nil, sf)
            child:SetSize(450, 10)
            sf:SetScrollChild(child)
            local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOPLEFT", 0, 0)
            fs:SetWidth(450)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            f.fs, f.child = fs, child
            tinsert(UISpecialFrames, "SangsuPackLogFrame")
            self.logFrame = f
        end
        local f = self.logFrame
        f.fs:SetText(BuildLogText(list))
        f.child:SetHeight((f.fs:GetStringHeight() or 300) + 10)
        f:Show()
    end

    if not SP.linkHooked and hooksecurefunc then
        SP.linkHooked = true
        hooksecurefunc("SetItemRef", function(link)
            if link == LINK then
                local sp = _G.SangsuPack
                if sp and sp.ShowChangelog then sp:ShowChangelog() end
            end
        end)
    end

    SLASH_SANGSUPACK1 = "/상수팩"
    SLASH_SANGSUPACK2 = "/sangsupack"
    SlashCmdList["SANGSUPACK"] = function(msg)
        msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "내역" or msg == "log" or msg == "changelog" then SP:ShowChangelog() else SP:ShowStatus() end
    end

    -----------------------------------------------------------------------
    -- 이벤트 (한 번만 생성)
    -----------------------------------------------------------------------
    if not SP.frame then
        SP.frame = CreateFrame("Frame")
        SP.frame:RegisterEvent("PLAYER_LOGIN")
        SP.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        SP.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        SP.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        SP.frame:RegisterEvent("CHAT_MSG_ADDON")
        SP.frame:SetScript("OnEvent", function(_, event, ...)
            local ok, err = pcall(SP.OnEvent, SP, event, ...)
            if not ok and not SP.errorShown then
                SP.errorShown = true
                SP.Print("내부 오류: " .. tostring(err))
            end
        end)
    end

    function SP:OnEvent(event, ...)
        if event == "PLAYER_LOGIN" then
            local fn = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
            if fn then pcall(fn, self.PREFIX) end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if not self.announced then
                self.announced = true
                C_Timer.After(15, function() SP:BroadcastAll() end)
            end
            C_Timer.After(6, function() SP:CheckUpdated() end)
        elseif event == "GROUP_ROSTER_UPDATE" then
            local g = GroupChannel()
            if not g then return end
            local now = GetTime()
            if self.lastGroupSend and now - self.lastGroupSend < 60 then return end
            self.lastGroupSend = now
            C_Timer.After(5, function()
                local ch = GroupChannel()
                if ch then SP:Broadcast({ ch }) end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if self.pendingBroadcast then
                self.pendingBroadcast = nil
                C_Timer.After(3, function() SP:BroadcastAll() end)
            end
        elseif event == "CHAT_MSG_ADDON" then
            self:OnAddonMessage(...)
        end
    end
end

-- 이 파일이 들어 있는 애드온을 상수팩에 등록
SP:Register(ADDON_NAME)
