local version, news, addonName, addonDB
local MAJOR, MINOR = "NewsFrame-1.0", 3
local NewsFrame, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not NewsFrame then return end -- No Upgrade needed.

--[[
NewsFrame:InitializeNewsFrame()
Used for version checking to see if the frame needs to be shown
Send this function the db where you want the settings and
table with patch notes formate like
patchnotes = {
    {version number, data}
    note 1
    {version number, data}
    note 1
    note 2 etc
}
]]
function NewsFrame:InitializeNewsFrame(db, newsTable, addon)
    addonName = addon
    addonDB = db
    version = GetAddOnMetadata(addonName, "Version")
    addonDB.AutoShowNews = addonDB.AutoShowNews or addonDB.AutoShowNews and addonDB.AutoShowNews ~= false and true
    if not addonDB.NewsVersion or addonDB.NewsVersion ~= version then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00|Hspell:"..addonName..":NewsLink|h"..addonName.." has been updated|cff00ffff [Click:Open News]|h|r")
        if addonDB.AutoShowNews then
            Timer.After(5, function() self:OpenNewsFrame() end)
        end
    end
    addonDB.NewsVersion = version
    news = newsTable

    hooksecurefunc("SetItemRef", function(link)
        local linkType, addon, param1 = strsplit(":", link)
        if linkType == "spell" and addon == addonName then
            if param1 == "NewsLink" then
                self:OpenNewsFrame()
            end
        end
    end)
end

local function copyToClipboard(text)
	Internal_CopyToClipboard(text)
	SendSystemMessage(S_COPIED_TO_CLIPBOARD:format(text:gsub("X%-", "")))
end



-- Creates News Frame
local frameCreated
local function createNewsFrame()
    if frameCreated then return end
    local mainframe = CreateFrame("FRAME", addonName.."NewsFrame", UIParent,"UIPanelDialogTemplate")
    mainframe:SetSize(500,600)
    mainframe:SetPoint("CENTER",0,0)
    mainframe:EnableMouse(true)
    mainframe:SetMovable(true)
    mainframe:RegisterForDrag("LeftButton")
    mainframe:SetScript("OnDragStart", function() mainframe:StartMoving() end)
    mainframe:SetScript("OnDragStop", function() mainframe:StopMovingOrSizing() end)
    mainframe.TitleText = mainframe:CreateFontString()
    mainframe.TitleText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    mainframe.TitleText:SetFontObject(GameFontNormal)
    mainframe.TitleText:SetText(addonName.." Version: "..version)
    mainframe.TitleText:SetPoint("TOP", 0, -9)
    mainframe.TitleText:SetShadowOffset(1,-1)
    mainframe:SetScript("OnShow", function()
        NewsFrame:NewsScrollFrameUpdate()
        mainframe.AutoShowNews:SetChecked(addonDB.AutoShowNews)
        end)
    mainframe:Hide()
    mainframe.AutoShowNews = CreateFrame("CheckButton", addonName.."NewsFrameAutoShow", mainframe, "OptionsCheckButtonTemplate")
    mainframe.AutoShowNews:SetPoint("BOTTOMLEFT", 20, 15)
    mainframe.AutoShowNews.Text:SetText("Auto Open on New Changes" )
    mainframe.AutoShowNews:SetScript("OnClick", function() addonDB.AutoShowNews = not addonDB.AutoShowNews end)

    local metaData = {
        {"X-Discord", "Discord"},
        {"X-Github-Repository", "GitHub"}
    }

    local lastButton
    local function createLinkButton(link, linkName)
        mainframe[linkName] = CreateFrame("Button", addonName.."NewsFrameDiscordCopyButton", mainframe)
        mainframe[linkName]:RegisterForClicks("AnyDown")
        mainframe[linkName]:SetScript("OnEnter", function(self)
            GameTooltip:ClearLines()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -(self:GetWidth() / 2), 5)
            GameTooltip:AddLine("|cff1eff00"..link)
            GameTooltip:AddLine("Click to copy link to clipboard")
            GameTooltip:Show()
        end)
        mainframe[linkName]:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mainframe[linkName]:SetSize(100, 20)

        if not lastButton then
            mainframe[linkName]:SetPoint("LEFT", mainframe.AutoShowNews, 250, 0)
        else
            mainframe[linkName]:SetPoint("LEFT", lastButton, "RIGHT", 0, 0)
        end

        mainframe[linkName]:SetScript("OnClick", function() copyToClipboard(link) end)
        mainframe[linkName].Text = mainframe[linkName]:CreateFontString(mainframe[linkName],"OVERLAY","GameFontNormal")
        mainframe[linkName].Text:SetText("|cff1eff00"..linkName.." Link")
        mainframe[linkName].Text:SetPoint("LEFT", 0, 0)
        mainframe[linkName].Text:SetJustifyH("LEFT")
        lastButton = mainframe[linkName]
    end

    if #metaData > 0 then
        for _, linkData in pairs(metaData) do
        local link = GetAddOnMetadata(addonName, linkData[1])
            if link then
                createLinkButton(link, linkData[2])
            end
        end
    end

    tinsert(UISpecialFrames, addonName.."NewsFrame")
    --ScrollFrame
    local ROW_HEIGHT = 25   -- How tall is each row?
    local MAX_ROWS = 20      -- How many rows can be shown at once?

    local scrollFrame = CreateFrame("Frame", addonName.."NewsScrollFrame", mainframe)
        scrollFrame:EnableMouse(true)
        scrollFrame:SetSize(mainframe:GetWidth()-40, ROW_HEIGHT * MAX_ROWS + 16)
        scrollFrame:SetPoint("TOP",0,-42)
        scrollFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true, tileSize = 16,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
    -- scrollframe update function
    function NewsFrame:NewsScrollFrameUpdate()
        local maxValue = #news
        FauxScrollFrame_Update(scrollFrame.scrollBar, maxValue, MAX_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scrollFrame.scrollBar)
        for i = 1, MAX_ROWS do
            local value = i + offset
            if value <= maxValue then
                local row = scrollFrame.rows[i]
                if type(news[value]) == "table" then
                    row:SetText("|cFFFFFF00" .. news[value][1] .. " (|cFFFF8800" .. news[value][2] .. "|r)")
                else
                    row:SetText("|cffFFFFFF- " .. news[value])
                end
                row:Show()
            else
                scrollFrame.rows[i]:Hide()
            end
        end
    end

    local scrollSlider = CreateFrame("ScrollFrame",addonName.."NewsFrameScroll",scrollFrame,"FauxScrollFrameTemplate")
    scrollSlider:SetPoint("TOPLEFT", 0, -8)
    scrollSlider:SetPoint("BOTTOMRIGHT", -30, 8)
    scrollSlider:SetScript("OnVerticalScroll", function(self, offset)
        self.offset = math.floor(offset / ROW_HEIGHT + 0.5)
        NewsFrame:NewsScrollFrameUpdate()
    end)

    scrollFrame.scrollBar = scrollSlider

    local rows = setmetatable({}, { __index = function(t, i)
        local row = scrollFrame:CreateFontString("$parentRow"..i,"OVERLAY","GameFontNormal")
        row:SetSize(420, 25)
        row:SetJustifyH("LEFT")
        if i == 1 then
            row:SetPoint("TOPLEFT", scrollFrame, 10, -8)
        else
            row:SetPoint("TOPLEFT", scrollFrame.rows[i-1], "BOTTOMLEFT")
        end
        rawset(t, i, row)
        return row
    end })

    scrollFrame.rows = rows
    frameCreated = true
end

function NewsFrame:OpenNewsFrame()
    createNewsFrame()
    _G[addonName.."NewsFrame"]:Show()
end

-- ---------------------------------------------------------------------
-- Embed handling

NewsFrame.embeds = NewsFrame.embeds or {}

local mixins = {
	"InitializeNewsFrame",
    "OpenNewsFrame",
}

function NewsFrame:Embed(target)
	self.embeds[target] = true
	for _,v in pairs(mixins) do
		target[v] = self[v]
	end
	return target
end

-- Update embeds
for addon, _ in pairs(NewsFrame.embeds) do
	NewsFrame:Embed(addon)
end