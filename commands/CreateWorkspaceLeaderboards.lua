-- Roblox Studio Command Bar setup script.
-- Copy src/ServerScriptService/LeaderboardSystem into ServerScriptService first,
-- then paste and run this whole file in the Command Bar.
--
-- The script is idempotent: running it again updates existing boards and creates
-- missing boards without duplicating boards for the same LeaderboardId.
--
-- Generated hierarchy:
-- Workspace
--   Leaderboards
--     Leaderboard_<Id>
--     Leaderboard_<Id>_Daily
--     Leaderboard_<Id>_Weekly

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local LEADERBOARD_SYSTEM_NAME = "LeaderboardSystem"
local LEADERBOARDS_FOLDER_NAME = "Leaderboards"
local BOARD_NAME_PREFIX = "Leaderboard_"

local BOARD_SIZE = Vector3.new(12, 18, 1)
local BOARD_START_POSITION = Vector3.new(0, 6, 0)
local BOARD_SPACING_STUDS = 15

local DEFAULT_FACE = "Front"
local DEFAULT_REFRESH_SECONDS = 120

local defaultPeriod = "AllTime"

local function getLeaderboardSystem()
	local leaderboardSystem = ServerScriptService:FindFirstChild(LEADERBOARD_SYSTEM_NAME)
	assert(leaderboardSystem ~= nil, "Copy src/ServerScriptService/LeaderboardSystem into ServerScriptService first.")

	return leaderboardSystem
end

local function getLeaderboardDefinitions(leaderboardSystem)
	local definitionsModule = leaderboardSystem:FindFirstChild("LeaderboardDefinitions")
	assert(definitionsModule ~= nil, "LeaderboardSystem is missing LeaderboardDefinitions.")

	return require(definitionsModule)
end

local function getOrCreateFolder()
	local folder = Workspace:FindFirstChild(LEADERBOARDS_FOLDER_NAME)
	if folder ~= nil then
		assert(folder:IsA("Folder"), "Workspace.Leaderboards exists but is not a Folder.")
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = LEADERBOARDS_FOLDER_NAME
	folder.Parent = Workspace

	return folder
end

local function getDefinitionPeriods(definition)
	if type(definition.Periods) ~= "table" then
		return { defaultPeriod }
	end

	return definition.Periods
end

local function getDefaultPeriod(definitionsApi)
	if type(definitionsApi.GetDefaultPeriod) == "function" then
		return definitionsApi.GetDefaultPeriod()
	end

	return defaultPeriod
end

local function getPeriodLabel(definitionsApi, period)
	if type(definitionsApi.GetPeriodLabel) == "function" then
		return definitionsApi.GetPeriodLabel(period)
	end

	if period == "AllTime" then
		return "All Time"
	end

	return tostring(period)
end

local function getBoardName(definition, period)
	local baseName = BOARD_NAME_PREFIX .. tostring(definition.Id)
	if period == defaultPeriod then
		return baseName
	end

	return baseName .. "_" .. period
end

local function getBoardTitle(definitionsApi, definition, period)
	if period == defaultPeriod then
		return definition.DisplayName
	end

	return definition.DisplayName .. " - " .. getPeriodLabel(definitionsApi, period)
end

local function getPartPeriod(part)
	local period = part:GetAttribute("LeaderboardPeriod")
	if type(period) ~= "string" or period == "" then
		return defaultPeriod
	end

	return period
end

local function findExistingBoard(folder, definition, period)
	local boardName = getBoardName(definition, period)
	local namedChild = folder:FindFirstChild(boardName)
	if namedChild ~= nil and namedChild:IsA("BasePart") then
		return namedChild
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant:GetAttribute("LeaderboardId") == definition.Id
			and getPartPeriod(descendant) == period
		then
			return descendant
		end
	end

	return nil
end

local function applyAttributes(part, definitionsApi, definition, period)
	part:SetAttribute("LeaderboardId", definition.Id)
	part:SetAttribute("LeaderboardPeriod", period)
	part:SetAttribute("LeaderboardTitle", getBoardTitle(definitionsApi, definition, period))
	part:SetAttribute("LeaderboardTopCount", definition.TopCount)
	part:SetAttribute("LeaderboardRefreshSeconds", DEFAULT_REFRESH_SECONDS)
	part:SetAttribute("LeaderboardFace", DEFAULT_FACE)
end

local function createBoardPart(folder, definitionsApi, definition, period, index)
	local part = Instance.new("Part")
	part.Name = getBoardName(definition, period)
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(24, 32, 62)
	part.Size = BOARD_SIZE
	part.Position = BOARD_START_POSITION + Vector3.new((index - 1) * BOARD_SPACING_STUDS, 0, 0)
	applyAttributes(part, definitionsApi, definition, period)
	part.Parent = folder

	return part
end

local leaderboardSystem = getLeaderboardSystem()
local LeaderboardDefinitions = getLeaderboardDefinitions(leaderboardSystem)
defaultPeriod = getDefaultPeriod(LeaderboardDefinitions)

local definitionsValid, reason = LeaderboardDefinitions.ValidateAll()
assert(definitionsValid, "Leaderboard definitions are invalid: " .. tostring(reason))

local folder = getOrCreateFolder()
local createdCount = 0
local updatedCount = 0
local nextCreateIndex = 1

for _, descendant in ipairs(folder:GetDescendants()) do
	if descendant:IsA("BasePart") then
		nextCreateIndex += 1
	end
end

for _, definition in ipairs(LeaderboardDefinitions.GetOrderedDefinitions()) do
	for _, period in ipairs(getDefinitionPeriods(definition)) do
		local part = findExistingBoard(folder, definition, period)
		if part == nil then
			part = createBoardPart(folder, LeaderboardDefinitions, definition, period, nextCreateIndex)
			nextCreateIndex += 1
			createdCount += 1
		else
			updatedCount += 1
		end

		applyAttributes(part, LeaderboardDefinitions, definition, period)
	end
end

print(
	string.format(
		"LeaderboardSystem: created %d board(s), updated %d board(s) in Workspace.%s.",
		createdCount,
		updatedCount,
		LEADERBOARDS_FOLDER_NAME
	)
)
