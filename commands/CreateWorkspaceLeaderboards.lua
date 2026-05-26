-- Paste this script into the Roblox Studio Command Bar after copying LeaderboardSystem
-- into ServerScriptService. It creates or updates Workspace.Leaderboards display parts.

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

-- getLeaderboardSystem locates the installed ModuleScript folder in ServerScriptService.
local function getLeaderboardSystem()
	local leaderboardSystem = ServerScriptService:FindFirstChild(LEADERBOARD_SYSTEM_NAME)
	assert(leaderboardSystem ~= nil, "Copy src/ServerScriptService/LeaderboardSystem into ServerScriptService first.")

	return leaderboardSystem
end

-- getLeaderboardDefinitions requires the source-of-truth definitions module.
local function getLeaderboardDefinitions(leaderboardSystem)
	local definitionsModule = leaderboardSystem:FindFirstChild("LeaderboardDefinitions")
	assert(definitionsModule ~= nil, "LeaderboardSystem is missing LeaderboardDefinitions.")

	return require(definitionsModule)
end

-- getOrCreateFolder creates the Workspace container without touching unrelated objects.
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

-- getBoardName keeps generated part names stable and readable.
local function getBoardName(definition)
	return BOARD_NAME_PREFIX .. tostring(definition.Id)
end

-- findExistingBoard prefers the stable generated name, then falls back to matching LeaderboardId.
local function findExistingBoard(folder, definition)
	local boardName = getBoardName(definition)
	local namedChild = folder:FindFirstChild(boardName)
	if namedChild ~= nil and namedChild:IsA("BasePart") then
		return namedChild
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("LeaderboardId") == definition.Id then
			return descendant
		end
	end

	return nil
end

-- applyAttributes updates plug-and-play attributes every time the command is run.
local function applyAttributes(part, definition)
	part:SetAttribute("LeaderboardId", definition.Id)
	part:SetAttribute("LeaderboardTitle", definition.DisplayName)
	part:SetAttribute("LeaderboardTopCount", definition.TopCount)
	part:SetAttribute("LeaderboardRefreshSeconds", DEFAULT_REFRESH_SECONDS)
	part:SetAttribute("LeaderboardFace", DEFAULT_FACE)
end

-- createBoardPart makes a new anchored display part and parents it last.
local function createBoardPart(folder, definition, index)
	local part = Instance.new("Part")
	part.Name = getBoardName(definition)
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(24, 32, 62)
	part.Size = BOARD_SIZE
	part.Position = BOARD_START_POSITION + Vector3.new((index - 1) * BOARD_SPACING_STUDS, 0, 0)
	applyAttributes(part, definition)
	part.Parent = folder

	return part
end

local leaderboardSystem = getLeaderboardSystem()
local LeaderboardDefinitions = getLeaderboardDefinitions(leaderboardSystem)

local definitionsValid, reason = LeaderboardDefinitions.ValidateAll()
assert(definitionsValid, "Leaderboard definitions are invalid: " .. tostring(reason))

local folder = getOrCreateFolder()
local createdCount = 0
local updatedCount = 0

for index, definition in ipairs(LeaderboardDefinitions.GetOrderedDefinitions()) do
	local part = findExistingBoard(folder, definition)
	if part == nil then
		part = createBoardPart(folder, definition, index)
		createdCount += 1
	else
		updatedCount += 1
	end

	applyAttributes(part, definition)
end

print(
	string.format(
		"LeaderboardSystem: created %d board(s), updated %d board(s) in Workspace.%s.",
		createdCount,
		updatedCount,
		LEADERBOARDS_FOLDER_NAME
	)
)
