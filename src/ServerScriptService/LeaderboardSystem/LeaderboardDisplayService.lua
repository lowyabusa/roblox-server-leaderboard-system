local Workspace = game:GetService("Workspace")

local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

local LeaderboardDisplayService = {}

local LEADERBOARDS_FOLDER_NAME = "Leaderboards"
local SURFACE_GUI_NAME = "LeaderboardSurfaceGui"

local DEFAULT_TOP_COUNT = 10
local MAX_DISPLAY_TOP_COUNT = 25
local DEFAULT_REFRESH_SECONDS = 120
local DEFAULT_FACE = Enum.NormalId.Front
local DEFAULT_PERIOD = LeaderboardService.GetDefaultPeriod()

local registeredDisplaysByPart = {}
local candidateAttributeConnectionsByPart = {}

local refreshLoopRunning = false
local workspaceFolderConnection = nil
local folderDescendantConnection = nil
local watchedLeaderboardFolder = nil

local THEME = {
	BoardScale = 1,

	RootPaddingXScale = 0.032,
	RootPaddingYScale = 0.032,
	RootLayoutPaddingScale = 0.018,

	HeaderHeightScale = 0.135,
	ListHeightScale = 0.775,
	RowLayoutPaddingScale = 0.012,

	RankWidthScale = 0.14,
	NameWidthScale = 0.69,
	ValueWidthScale = 0.17,

	NameLeftPaddingScale = 0.025,
	ValueRightPaddingScale = 0.045,

	FrameStrokeThickness = 5,
	RowStrokeThickness = 4,
	TextStrokeThickness = 3,

	RootCornerRadiusScale = 0.035,
	PanelCornerRadiusScale = 0.035,
	HeaderCornerRadiusScale = 0.16,
	RowCornerRadiusScale = 0.18,
	LabelCornerRadiusScale = 0.16,

	RootBackground = Color3.fromRGB(18, 24, 54),
	RootGradientA = Color3.fromRGB(14, 34, 82),
	RootGradientB = Color3.fromRGB(92, 34, 128),
	RootStroke = Color3.fromRGB(125, 215, 255),

	HeaderBackground = Color3.fromRGB(78, 117, 117),
	HeaderText = Color3.fromRGB(255, 238, 165),
	HeaderStroke = Color3.fromRGB(255, 210, 92),
	HeaderTextStroke = Color3.fromRGB(4, 8, 18),
	DarkTextStroke = Color3.fromRGB(3, 6, 12),

	ListBackground = Color3.fromRGB(18, 32, 68),
	ListGradientA = Color3.fromRGB(18, 46, 92),
	ListGradientB = Color3.fromRGB(58, 28, 88),
	ListStroke = Color3.fromRGB(105, 170, 230),

	RowBackground = Color3.fromRGB(34, 58, 104),
	RowStroke = Color3.fromRGB(115, 195, 255),
	EmptyBackground = Color3.fromRGB(20, 28, 46),
	Text = Color3.fromRGB(255, 255, 255),
	LabelBackground = Color3.fromRGB(255, 255, 255),
}

local BOARD_SCALE = THEME.BoardScale

local ROOT_PADDING_X_SCALE = THEME.RootPaddingXScale
local ROOT_PADDING_Y_SCALE = THEME.RootPaddingYScale
local ROOT_LAYOUT_PADDING_SCALE = THEME.RootLayoutPaddingScale

local HEADER_HEIGHT_SCALE = THEME.HeaderHeightScale
local LIST_HEIGHT_SCALE = THEME.ListHeightScale
local ROW_LAYOUT_PADDING_SCALE = THEME.RowLayoutPaddingScale

local RANK_WIDTH_SCALE = THEME.RankWidthScale
local NAME_WIDTH_SCALE = THEME.NameWidthScale
local VALUE_WIDTH_SCALE = THEME.ValueWidthScale

local NAME_LEFT_PADDING_SCALE = THEME.NameLeftPaddingScale
local VALUE_RIGHT_PADDING_SCALE = THEME.ValueRightPaddingScale

local FRAME_STROKE_THICKNESS = THEME.FrameStrokeThickness
local ROW_STROKE_THICKNESS = THEME.RowStrokeThickness
local TEXT_STROKE_THICKNESS = THEME.TextStrokeThickness

local ROOT_CORNER_RADIUS_SCALE = THEME.RootCornerRadiusScale
local PANEL_CORNER_RADIUS_SCALE = THEME.PanelCornerRadiusScale
local HEADER_CORNER_RADIUS_SCALE = THEME.HeaderCornerRadiusScale
local ROW_CORNER_RADIUS_SCALE = THEME.RowCornerRadiusScale
local LABEL_CORNER_RADIUS_SCALE = THEME.LabelCornerRadiusScale

local FACE_BY_NAME = {
	Front = Enum.NormalId.Front,
	Back = Enum.NormalId.Back,
	Left = Enum.NormalId.Left,
	Right = Enum.NormalId.Right,
	Top = Enum.NormalId.Top,
	Bottom = Enum.NormalId.Bottom,
}

local function sanitizeWholeNumber(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function sanitizePositiveNumber(value, fallback)
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue <= 0 then
		return fallback
	end

	return numberValue
end

local function sanitizeLeaderboardId(value)
	local leaderboardId = tostring(value or "")
	if leaderboardId == "" then
		return nil
	end

	return leaderboardId
end

local function getLeaderboardPeriod(part)
	local attributeValue = part:GetAttribute("LeaderboardPeriod")
	if type(attributeValue) ~= "string" or attributeValue == "" then
		return DEFAULT_PERIOD
	end

	return attributeValue
end

local function getLeaderboardFolder()
	local folder = Workspace:FindFirstChild(LEADERBOARDS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function getSurfaceFace(part)
	local attributeValue = part:GetAttribute("LeaderboardFace")
	local faceName = tostring(attributeValue or "")

	if FACE_BY_NAME[faceName] ~= nil then
		return FACE_BY_NAME[faceName]
	end

	return DEFAULT_FACE
end

local function getTopCount(part)
	return math.min(
		MAX_DISPLAY_TOP_COUNT,
		math.max(
			1,
			sanitizeWholeNumber(part:GetAttribute("LeaderboardTopCount") or DEFAULT_TOP_COUNT)
		)
	)
end

local function getRefreshSeconds(part)
	return sanitizePositiveNumber(part:GetAttribute("LeaderboardRefreshSeconds"), DEFAULT_REFRESH_SECONDS)
end

local function clearChildren(instance)
	if not instance then
		return
	end

	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function createColorSequence(colorA, colorB)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorA),
		ColorSequenceKeypoint.new(1, colorB),
	})
end

local function addGradient(parent, colorA, colorB, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Gradient"
	gradient.Color = createColorSequence(colorA, colorB)
	gradient.Rotation = tonumber(rotation) or 0
	gradient.Parent = parent

	return gradient
end

local function addCorner(parent, radiusScale)
	local corner = Instance.new("UICorner")
	corner.Name = "Corner"
	corner.CornerRadius = UDim.new(sanitizePositiveNumber(radiusScale, PANEL_CORNER_RADIUS_SCALE), 0)
	corner.Parent = parent

	return corner
end

local function addFrameStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or FRAME_STROKE_THICKNESS
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent

	return stroke
end

local function addTextStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TextStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or TEXT_STROKE_THICKNESS
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent

	return stroke
end

local function addPadding(parent, name, padding)
	local uiPadding = Instance.new("UIPadding")
	uiPadding.Name = name
	uiPadding.PaddingTop = padding.Top or UDim.new(0, 0)
	uiPadding.PaddingBottom = padding.Bottom or UDim.new(0, 0)
	uiPadding.PaddingLeft = padding.Left or UDim.new(0, 0)
	uiPadding.PaddingRight = padding.Right or UDim.new(0, 0)
	uiPadding.Parent = parent

	return uiPadding
end

local function addListLayout(parent, paddingScale)
	local layout = Instance.new("UIListLayout")
	layout.Name = "Layout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(paddingScale, 0)
	layout.Parent = parent

	return layout
end

local function getRowHeightScale(rowSlotCount)
	local safeCount = math.max(1, sanitizeWholeNumber(rowSlotCount))
	local totalPadding = ROW_LAYOUT_PADDING_SCALE * math.max(0, safeCount - 1)
	local remaining = math.max(0.05, 1 - totalPadding)

	return remaining / safeCount
end

local function getRankTextGradientColors(rank)
	if rank == 1 then
		return Color3.fromRGB(255, 238, 145), Color3.fromRGB(255, 176, 48)
	end

	if rank == 2 then
		return Color3.fromRGB(238, 248, 255), Color3.fromRGB(150, 190, 225)
	end

	if rank == 3 then
		return Color3.fromRGB(255, 196, 126), Color3.fromRGB(190, 105, 48)
	end

	return Color3.fromRGB(210, 245, 255), Color3.fromRGB(95, 190, 255)
end

local function getRowGradientColors(rank)
	if rank == 1 then
		return Color3.fromRGB(112, 76, 18), Color3.fromRGB(34, 68, 124)
	end

	if rank == 2 then
		return Color3.fromRGB(76, 94, 118), Color3.fromRGB(36, 58, 104)
	end

	if rank == 3 then
		return Color3.fromRGB(96, 54, 28), Color3.fromRGB(38, 58, 104)
	end

	if rank % 2 == 0 then
		return Color3.fromRGB(34, 84, 132), Color3.fromRGB(36, 46, 96)
	end

	return Color3.fromRGB(58, 52, 124), Color3.fromRGB(28, 74, 112)
end

local function getOrCreateSurfaceGui(part)
	local existing = part:FindFirstChild(SURFACE_GUI_NAME)
	if existing and existing:IsA("SurfaceGui") then
		existing.Face = getSurfaceFace(part)
		return existing
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = SURFACE_GUI_NAME
	surfaceGui.Face = getSurfaceFace(part)
	surfaceGui.AlwaysOnTop = false
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 48
	surfaceGui.Parent = part

	return surfaceGui
end

local function createRootFrame(surfaceGui)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = THEME.RootBackground
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.Parent = surfaceGui

	local rootScale = Instance.new("UIScale")
	rootScale.Name = "RootScale"
	rootScale.Scale = BOARD_SCALE
	rootScale.Parent = root

	addCorner(root, ROOT_CORNER_RADIUS_SCALE)

	addGradient(
		root,
		THEME.RootGradientA,
		THEME.RootGradientB,
		35
	)

	addFrameStroke(
		root,
		THEME.RootStroke,
		0.16,
		FRAME_STROKE_THICKNESS
	)

	addPadding(root, "Padding", {
		Top = UDim.new(ROOT_PADDING_Y_SCALE, 0),
		Bottom = UDim.new(ROOT_PADDING_Y_SCALE, 0),
		Left = UDim.new(ROOT_PADDING_X_SCALE, 0),
		Right = UDim.new(ROOT_PADDING_X_SCALE, 0),
	})
	addListLayout(root, ROOT_LAYOUT_PADDING_SCALE)

	return root
end

local function createHeader(root, titleText)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.fromScale(1, HEADER_HEIGHT_SCALE)
	title.BackgroundColor3 = THEME.HeaderBackground
	title.BackgroundTransparency = 0
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.Text = tostring(titleText or "Leaderboard")
	title.TextColor3 = THEME.HeaderText
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = root

	addCorner(title, HEADER_CORNER_RADIUS_SCALE)

	addFrameStroke(
		title,
		THEME.HeaderStroke,
		0.12,
		ROW_STROKE_THICKNESS
	)

	addTextStroke(
		title,
		THEME.HeaderTextStroke,
		0,
		TEXT_STROKE_THICKNESS
	)

	return title
end

local function createListFrame(root)
	local list = Instance.new("Frame")
	list.Name = "List"
	list.LayoutOrder = 2
	list.Size = UDim2.fromScale(1, LIST_HEIGHT_SCALE)
	list.BackgroundColor3 = THEME.ListBackground
	list.BackgroundTransparency = 0
	list.BorderSizePixel = 0
	list.Parent = root

	addCorner(list, PANEL_CORNER_RADIUS_SCALE)

	addGradient(
		list,
		THEME.ListGradientA,
		THEME.ListGradientB,
		90
	)

	addFrameStroke(
		list,
		THEME.ListStroke,
		0.48,
		ROW_STROKE_THICKNESS
	)

	addListLayout(list, ROW_LAYOUT_PADDING_SCALE)

	return list
end

local function createRankLabel(row, rank)
	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "Rank"
	rankLabel.Size = UDim2.fromScale(RANK_WIDTH_SCALE, 1)
	rankLabel.Position = UDim2.fromScale(0, 0)
	rankLabel.BackgroundColor3 = THEME.LabelBackground
	rankLabel.BackgroundTransparency = 0.35
	rankLabel.BorderSizePixel = 0
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.Text = "#" .. tostring(rank)
	rankLabel.TextColor3 = THEME.Text
	rankLabel.TextScaled = true
	rankLabel.TextXAlignment = Enum.TextXAlignment.Center
	rankLabel.TextYAlignment = Enum.TextYAlignment.Center
	rankLabel.Parent = row

	addCorner(rankLabel, LABEL_CORNER_RADIUS_SCALE)

	local colorA, colorB = getRankTextGradientColors(rank)
	addGradient(rankLabel, colorA, colorB, 0)
	addTextStroke(rankLabel, THEME.DarkTextStroke, 0.16, TEXT_STROKE_THICKNESS)

	return rankLabel
end

local function createNameLabel(row, playerName)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.fromScale(NAME_WIDTH_SCALE, 1)
	nameLabel.Position = UDim2.fromScale(RANK_WIDTH_SCALE, 0)
	nameLabel.BackgroundColor3 = THEME.LabelBackground
	nameLabel.BackgroundTransparency = 0.55
	nameLabel.BorderSizePixel = 0
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = tostring(playerName or "Unknown")
	nameLabel.TextColor3 = THEME.Text
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row

	addCorner(nameLabel, LABEL_CORNER_RADIUS_SCALE)

	addPadding(nameLabel, "LeftPadding", {
		Left = UDim.new(NAME_LEFT_PADDING_SCALE, 0),
	})

	addGradient(
		nameLabel,
		THEME.Text,
		Color3.fromRGB(170, 230, 255),
		0
	)

	addTextStroke(nameLabel, THEME.DarkTextStroke, 0.2, TEXT_STROKE_THICKNESS)

	return nameLabel
end

local function createValueLabel(row, value)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.fromScale(VALUE_WIDTH_SCALE, 1)
	valueLabel.Position = UDim2.fromScale(RANK_WIDTH_SCALE + NAME_WIDTH_SCALE, 0)
	valueLabel.BackgroundColor3 = THEME.LabelBackground
	valueLabel.BackgroundTransparency = 0.4
	valueLabel.BorderSizePixel = 0
	valueLabel.Font = Enum.Font.GothamBlack
	valueLabel.Text = tostring(sanitizeWholeNumber(value))
	valueLabel.TextColor3 = THEME.Text
	valueLabel.TextScaled = true
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextYAlignment = Enum.TextYAlignment.Center
	valueLabel.Parent = row

	addCorner(valueLabel, LABEL_CORNER_RADIUS_SCALE)

	addPadding(valueLabel, "RightPadding", {
		Right = UDim.new(VALUE_RIGHT_PADDING_SCALE, 0),
	})

	addGradient(
		valueLabel,
		Color3.fromRGB(145, 255, 215),
		Color3.fromRGB(255, 224, 112),
		0
	)

	addTextStroke(valueLabel, THEME.DarkTextStroke, 0.12, TEXT_STROKE_THICKNESS)

	return valueLabel
end

local function createRow(list, rank, playerName, value, rowHeightScale)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. tostring(rank)
	row.LayoutOrder = rank
	row.Size = UDim2.fromScale(1, rowHeightScale)
	row.BackgroundColor3 = THEME.RowBackground
	row.BackgroundTransparency = 0
	row.BorderSizePixel = 0
	row.Parent = list

	addCorner(row, ROW_CORNER_RADIUS_SCALE)

	local rowColorA, rowColorB = getRowGradientColors(rank)
	addGradient(row, rowColorA, rowColorB, 0)

	addFrameStroke(
		row,
		THEME.RowStroke,
		rank <= 3 and 0.16 or 0.4,
		ROW_STROKE_THICKNESS
	)

	createRankLabel(row, rank)
	createNameLabel(row, playerName)
	createValueLabel(row, value)

	return row
end

local function createEmptyRow(list, rowHeightScale, message)
	local row = Instance.new("TextLabel")
	row.Name = "Empty"
	row.LayoutOrder = 1
	row.Size = UDim2.fromScale(1, rowHeightScale)
	row.BackgroundColor3 = THEME.EmptyBackground
	row.BackgroundTransparency = 0.16
	row.BorderSizePixel = 0
	row.Font = Enum.Font.GothamBold
	row.Text = tostring(message or "No entries yet")
	row.TextColor3 = THEME.Text
	row.TextScaled = true
	row.TextXAlignment = Enum.TextXAlignment.Center
	row.TextYAlignment = Enum.TextYAlignment.Center
	row.Parent = list

	addCorner(row, ROW_CORNER_RADIUS_SCALE)

	addGradient(
		row,
		Color3.fromRGB(210, 220, 235),
		Color3.fromRGB(125, 180, 225),
		0
	)

	addFrameStroke(
		row,
		THEME.ListStroke,
		0.5,
		ROW_STROKE_THICKNESS
	)

	addTextStroke(row, THEME.DarkTextStroke, 0.2, TEXT_STROKE_THICKNESS)

	return row
end

local function renderSnapshot(part, snapshot, topCount)
	local surfaceGui = getOrCreateSurfaceGui(part)
	clearChildren(surfaceGui)

	local root = createRootFrame(surfaceGui)

	local titleText = part:GetAttribute("LeaderboardTitle")
	if type(titleText) ~= "string" or titleText == "" then
		titleText = snapshot and snapshot.DisplayName or "Leaderboard"
	end
	if type(snapshot) == "table" and snapshot.Stale == true then
		titleText = tostring(titleText) .. " (cached)"
	end

	createHeader(root, titleText)

	local list = createListFrame(root)
	local rows = type(snapshot) == "table" and snapshot.Rows or {}

	local rowSlotCount = math.max(1, sanitizeWholeNumber(topCount or #rows or DEFAULT_TOP_COUNT))
	local rowHeightScale = getRowHeightScale(rowSlotCount)

	if #rows <= 0 then
		local emptyMessage = "No entries yet"
		if type(snapshot) == "table" and snapshot.Error ~= nil then
			emptyMessage = "Enable API Services or publish a value"
		end

		createEmptyRow(list, rowHeightScale, emptyMessage)
		return
	end

	for index, row in ipairs(rows) do
		createRow(
			list,
			sanitizeWholeNumber(row.Rank or index),
			row.PlayerName,
			row.Value,
			rowHeightScale
		)
	end
end

-- Builds the latest snapshot and renders it immediately for one registered part.
local function refreshDisplayNow(part, entry)
	if not part or not part.Parent or not part:IsA("BasePart") then
		registeredDisplaysByPart[part] = nil
		return
	end

	if type(entry) ~= "table" then
		return
	end

	local leaderboardId = sanitizeLeaderboardId(part:GetAttribute("LeaderboardId"))
	if leaderboardId == nil then
		return
	end

	local period = getLeaderboardPeriod(part)
	local topCount = getTopCount(part)
	local snapshot = LeaderboardService.BuildPeriodSnapshot(leaderboardId, period, topCount)

	if registeredDisplaysByPart[part] == entry then
		renderSnapshot(part, snapshot, topCount)
	end
end

-- Refreshes one display when its per-part cooldown has elapsed.
local function refreshDisplay(part, entry)
	if not part or not part.Parent or not part:IsA("BasePart") then
		registeredDisplaysByPart[part] = nil
		return
	end

	if type(entry) ~= "table" or entry.IsRefreshing == true then
		return
	end

	local now = os.clock()
	if now < entry.NextRefreshAt then
		return
	end

	entry.NextRefreshAt = now + getRefreshSeconds(part)
	entry.IsRefreshing = true

	task.spawn(function()
		local success, err = pcall(function()
			refreshDisplayNow(part, entry)
		end)

		entry.IsRefreshing = false

		if not success then
			local partName = part and part:GetFullName() or "Unknown"
			warn("LeaderboardDisplayService refresh failed:", partName, err)
		end
	end)
end

-- Refreshes all registered display parts once.
local function refreshAllDisplays()
	for part, entry in pairs(registeredDisplaysByPart) do
		refreshDisplay(part, entry)
	end
end

-- Starts the shared refresh loop.
local function startRefreshLoop()
	if refreshLoopRunning then
		return
	end

	refreshLoopRunning = true

	task.spawn(function()
		while refreshLoopRunning do
			refreshAllDisplays()
			task.wait(5)
		end
	end)
end

-- Stops watching a candidate part after it becomes a registered display.
local function disconnectCandidateAttributeWatcher(part)
	local connection = candidateAttributeConnectionsByPart[part]
	if connection ~= nil then
		connection:Disconnect()
		candidateAttributeConnectionsByPart[part] = nil
	end
end

-- Registers parts with LeaderboardId immediately, or watches them until that attribute is set.
local function watchCandidatePart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if registeredDisplaysByPart[part] ~= nil then
		disconnectCandidateAttributeWatcher(part)
		return true
	end

	if sanitizeLeaderboardId(part:GetAttribute("LeaderboardId")) ~= nil then
		local success = LeaderboardDisplayService.RegisterDisplayPart(part)
		if success then
			disconnectCandidateAttributeWatcher(part)
			return true
		end
	end

	if candidateAttributeConnectionsByPart[part] == nil then
		candidateAttributeConnectionsByPart[part] = part:GetAttributeChangedSignal("LeaderboardId"):Connect(function()
			if not part.Parent then
				disconnectCandidateAttributeWatcher(part)
				return
			end

			if sanitizeLeaderboardId(part:GetAttribute("LeaderboardId")) ~= nil then
				local success = LeaderboardDisplayService.RegisterDisplayPart(part)
				if success then
					disconnectCandidateAttributeWatcher(part)
				end
			end
		end)
	end

	return false
end

-- Watches the current Leaderboards folder for parts created after Init runs.
local function watchLeaderboardFolder(folder)
	if not folder or not folder:IsA("Folder") or watchedLeaderboardFolder == folder then
		return
	end

	if folderDescendantConnection ~= nil then
		folderDescendantConnection:Disconnect()
		folderDescendantConnection = nil
	end

	watchedLeaderboardFolder = folder
	folderDescendantConnection = folder.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			task.defer(watchCandidatePart, descendant)
		end
	end)
end

-- Watches Workspace for the Leaderboards folder when it is added after server startup.
local function startWorkspaceFolderWatcher()
	if workspaceFolderConnection ~= nil then
		return
	end

	workspaceFolderConnection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == LEADERBOARDS_FOLDER_NAME and child:IsA("Folder") then
			task.defer(function()
				watchLeaderboardFolder(child)
				LeaderboardDisplayService.RegisterAllWorkspaceDisplays()
			end)
		end
	end)
end

-- Registers one Workspace part as a leaderboard display.
function LeaderboardDisplayService.RegisterDisplayPart(part)
	if not part or not part:IsA("BasePart") then
		return false, "InvalidPart"
	end

	local leaderboardId = sanitizeLeaderboardId(part:GetAttribute("LeaderboardId"))
	if leaderboardId == nil then
		return false, "MissingLeaderboardId"
	end

	local definition = LeaderboardService.GetDefinition(leaderboardId)
	if type(definition) ~= "table" then
		return false, "UnknownLeaderboard"
	end

	local period = getLeaderboardPeriod(part)
	if not LeaderboardService.IsLeaderboardPeriodEnabled(leaderboardId, period) then
		return false, "InvalidPeriod"
	end

	registeredDisplaysByPart[part] = {
		LeaderboardId = leaderboardId,
		Period = period,
		NextRefreshAt = 0,
	}

	refreshDisplay(part, registeredDisplaysByPart[part])
	startRefreshLoop()

	return true, nil
end

-- Stops refreshing one registered display part.
function LeaderboardDisplayService.UnregisterDisplayPart(part)
	if registeredDisplaysByPart[part] == nil then
		return false, "NotRegistered"
	end

	registeredDisplaysByPart[part] = nil
	return true, nil
end

-- Refreshes one registered display part immediately.
function LeaderboardDisplayService.RefreshDisplayPart(part)
	local entry = registeredDisplaysByPart[part]
	if type(entry) ~= "table" then
		return false, "NotRegistered"
	end

	entry.NextRefreshAt = 0
	refreshDisplay(part, entry)

	return true, nil
end

-- Registers all configured parts under Workspace.Leaderboards.
function LeaderboardDisplayService.RegisterAllWorkspaceDisplays()
	local folder = getLeaderboardFolder()
	if not folder then
		return 0
	end

	watchLeaderboardFolder(folder)

	local count = 0

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local success = watchCandidatePart(descendant)
			if success then
				count += 1
			end
		end
	end

	return count
end

-- Starts display discovery, folder watchers, and the refresh loop.
function LeaderboardDisplayService.Init()
	LeaderboardService.Init()
	startWorkspaceFolderWatcher()
	LeaderboardDisplayService.RegisterAllWorkspaceDisplays()
	startRefreshLoop()

	return true
end

return LeaderboardDisplayService
