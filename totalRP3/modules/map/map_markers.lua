----------------------------------------------------------------------------------
-- Total RP 3
-- Map marker and coordinates system
--	---------------------------------------------------------------------------
--	Copyright 2014 Sylvain Cossement (telkostrasz@telkostrasz.be)
--
--	Licensed under the Apache License, Version 2.0 (the "License");
--	you may not use this file except in compliance with the License.
--	You may obtain a copy of the License at
--
--		http://www.apache.org/licenses/LICENSE-2.0
--
--	Unless required by applicable law or agreed to in writing, software
--	distributed under the License is distributed on an "AS IS" BASIS,
--	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--	See the License for the specific language governing permissions and
--	limitations under the License.
----------------------------------------------------------------------------------

---@type TRP3_API
local _, TRP3_API = ...;
---@type AddOn_TotalRP3
local AddOn_TotalRP3 = AddOn_TotalRP3;

TRP3_API.map = {};

-- Ellyb imports
local YELLOW = TRP3_API.Ellyb.ColorManager.YELLOW;

local Ellyb = TRP3_API.Ellyb;
local Utils, Events, Globals = TRP3_API.utils, TRP3_API.events, TRP3_API.globals;
local Comm = TRP3_API.communication;
local setupIconButton = TRP3_API.ui.frame.setupIconButton;
local displayDropDown = TRP3_API.ui.listbox.displayDropDown;
local loc = TRP3_API.loc;
local tinsert, assert, tonumber, pairs, _G, wipe = tinsert, assert, tonumber, pairs, _G, wipe;
local CreateFrame = CreateFrame;
local after = C_Timer.After;
local playAnimation = TRP3_API.ui.misc.playAnimation;
local getConfigValue = TRP3_API.configuration.getValue;

-- Ellyb Imports.
local Color = Ellyb.Color;

local CONFIG_UI_ANIMATIONS = "ui_animations";

---@type Frame
local TRP3_ScanLoaderFrame = TRP3_ScanLoaderFrame;

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Utils
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

function TRP3_API.map.getCurrentCoordinates()
	local mapID = C_Map.GetBestMapForUnit("player");
	local mapVector = C_Map.GetPlayerMapPosition(mapID, "player");
	if mapVector then
		local x, y = mapVector:GetXY();
		return mapID, x, y;
	end
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Marker logic
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
---@type GameTooltip
local WorldMapTooltip = WorldMapTooltip
local WorldMapPOIFrame = WorldMapPOIFrame;
local MARKER_NAME_PREFIX = "TRP3_WordMapMarker";

local MAX_DISTANCE_MARKER = math.sqrt(0.5 * 0.5 + 0.5 * 0.5);

--- TOOLTIP_CATEGORY_TEXT_COLOR is the text color used for category headers
--  in the displayed tooltip.
local TOOLTIP_CATEGORY_TEXT_COLOR = Color.CreateFromRGBAAsBytes(255, 209, 0);

--- TOOLTIP_CATEGORY_SEPARATOR is a texture string displayed as a separator.
local TOOLTIP_CATEGORY_SEPARATOR =
	[[|TInterface\Common\UI-TooltipDivider-Transparent:8:128:0:0:8:8:0:128:0:8:255:255:255|t]];

local function hideAllMarkers()
	local i = 1;
	while(_G[MARKER_NAME_PREFIX .. i]) do
		local marker = _G[MARKER_NAME_PREFIX .. i];
		marker:Hide();
		marker.scanLine = nil;
		i = i + 1;
	end
end

--- Temporary table used by writeMarkerTooltipLines when it queries the marker
--  list for widgets currently under the mouse cursor.
local markerTooltipEntries = {};

--- Custom sorting function that compares entries. The resulting order is
--  in order of their category priority (descending), or if equal, their
--  sortable name equivalent (ascending).
local function sortMarkerEntries(a, b)
	local categoryA = a.categoryPriority or -math.huge;
	local categoryB = b.categoryPriority or -math.huge;

	local nameA = a.sortName or "";
	local nameB = b.sortName or "";

	return (categoryA > categoryB)
		or (categoryA == categoryB and nameA < nameB);
end

--- Writes the required lines for a world map marker tooltip based on the
--  current location of the cursor.
local function writeMarkerTooltipLines(tooltip)
	-- Iterate over the blips in a first pass to build a list of all the
	-- ones we're mousing over.
	local index = 1;
	while(_G[MARKER_NAME_PREFIX .. index]) do
		local marker = _G[MARKER_NAME_PREFIX .. index];
		if marker:IsVisible() and marker:IsMouseOver() then
			tinsert(markerTooltipEntries, marker);
		end
		index = index + 1;
	end

	-- Sort the entries prior to display.
	table.sort(markerTooltipEntries, sortMarkerEntries);

	-- Tracking variable for our last category inserted into the tip.
	-- If it changes we'll stick in a separator.
	local lastCategory = nil;

	-- This layout will put the category status text above entries
	-- when the type changes. Requires the entries be sorted by category.
	for i = 1, #markerTooltipEntries do
		local marker = markerTooltipEntries[i];
		if marker.categoryName ~= lastCategory then
			-- If the previous category was nil we assume this is
			-- the first, so we'll not put a separating border in.
			if lastCategory ~= nil then
				tooltip:AddLine(TOOLTIP_CATEGORY_SEPARATOR, 1, 1, 1);
			end

			tooltip:AddLine(marker.categoryName or "", TOOLTIP_CATEGORY_TEXT_COLOR:GetRGB());
			lastCategory = marker.categoryName;
		end

		tooltip:AddLine(marker.scanLine or "", 1, 1, 1);

		-- Wipe the table as we go.
		markerTooltipEntries[i] = nil;
	end
end

local function getMarker(i, tooltip)
	---@type Frame
	local marker = _G[MARKER_NAME_PREFIX .. i];

	if not marker then
		marker = CreateFrame("Frame", MARKER_NAME_PREFIX .. i, WorldMapButton, "TRP3_WorldMapUnit");
		marker:SetScript("OnEnter", function(self)
			WorldMapPOIFrame.allowBlobTooltip = false;

			WorldMapTooltip:Hide();
			WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0);
			WorldMapTooltip:AddLine(self.tooltip, 1, 1, 1, true);

			writeMarkerTooltipLines(WorldMapTooltip);

			WorldMapTooltip:Show();
		end);
		marker:SetScript("OnLeave", function()
			WorldMapPOIFrame.allowBlobTooltip = true;
			WorldMapTooltip:Hide();
		end);
	end
	marker.tooltip = YELLOW(tooltip or "");
	return marker;
end

---@param marker Frame
---@param x nubmer
---@param y number
local function placeMarker(marker, x, y)
	x = (x or 0) * WorldMapDetailFrame:GetWidth();
	y = - (y or 0) * WorldMapDetailFrame:GetHeight();
	marker:ClearAllPoints();
	marker:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", x, y);
end

local function animateMarker(marker, x, y, directAnimation)
	if getConfigValue(CONFIG_UI_ANIMATIONS) then

		local distanceX = 0.5 - x;
		local distanceY = 0.5 - y;
		local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY);
		local factor = distance/MAX_DISTANCE_MARKER;

		if not directAnimation then
			after(4 * factor, function()
				marker:Show();
				marker:SetAlpha(0);
				playAnimation(marker.Bounce);
			end);
		else
			marker:Show();
			marker:SetAlpha(0);
			playAnimation(marker.Bounce);
		end
	else
		-- The default alpha on the widget is zero, so need to change it here.
		marker:SetAlpha(1);
		marker:Show();
	end
end

local DECORATION_TYPES = {
	HOUSE = "house",
	CHARACTER = "character"
};
TRP3_API.map.DECORATION_TYPES = DECORATION_TYPES;

local function decorateMarker(marker, decorationType)
	-- Custom atlases on the marker take priority; after that we'll fall
	-- back to given decoration types.
	if marker.iconAtlas then
		marker.Icon:SetAtlas(marker.iconAtlas);
	elseif not decorationType or decorationType == DECORATION_TYPES.CHARACTER then
		marker.Icon:SetAtlas("PartyMember");
	elseif decorationType == DECORATION_TYPES.HOUSE then
		marker.Icon:SetAtlas("poi-town");
	end

	-- Set a custom vertex color on the atlas or reset it to normal if not
	-- explicitly overridden.
	if marker.iconColor then
		marker.Icon:SetVertexColor(marker.iconColor:GetRGBA());
	else
		marker.Icon:SetVertexColor(1, 1, 1, 1);
	end

	-- Change the draw layer if requested.
	local layer = marker.Icon:GetDrawLayer();
	marker.Icon:SetDrawLayer(layer, marker.iconSublevel or 0);
end

---@param structure table
local function displayMarkers(structure)
	if not WorldMapFrame:IsVisible() then
		return;
	end

	local i = 1;
	for key, entry in pairs(structure.saveStructure) do
		local marker = getMarker(i, structure.scanTitle);

		-- Implementation can be adapted by decorator.
		--
		-- Do this before the rest so the decorators have more control over
		-- the resulting display.
		if structure.scanMarkerDecorator then
			structure.scanMarkerDecorator(key, entry, marker);
		end

		placeMarker(marker, entry.x, entry.y);
		decorateMarker(marker, DECORATION_TYPES.CHARACTER);
		animateMarker(marker, entry.x, entry.y, structure.noAnim);

		i = i + 1;
	end
end

function TRP3_API.map.placeSingleMarker(x, y, tooltip, decorationType)
	hideAllMarkers();
	local marker = getMarker(1, tooltip);
	placeMarker(marker, x, y);
	animateMarker(marker, x, y, true);
	decorateMarker(marker, decorationType);
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Scan logic
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

local SCAN_STRUCTURES = {};
local currentMapID;
local launchScan;

local function registerScan(structure)
	assert(structure and structure.id, "Must have a structure and a structure.id!");
	SCAN_STRUCTURES[structure.id] = structure;
	if structure.scanResponder and structure.scanCommand then
		AddOn_TotalRP3.Communications.broadcast.registerCommand(structure.scanCommand, structure.scanResponder);
	end
	if not structure.saveStructure then
		structure.saveStructure = {};
	end
	if structure.scanAssembler and structure.scanCommand then
		AddOn_TotalRP3.Communications.broadcast.registerP2PCommand(structure.scanCommand, function(...)
			structure.scanAssembler(structure.saveStructure, ...);
		end)
	end
end
TRP3_API.map.registerScan = registerScan;

function launchScan(scanID)
	assert(SCAN_STRUCTURES[scanID], ("Unknown scan id %s"):format(scanID));
	local structure = SCAN_STRUCTURES[scanID];
	if structure.scan then
		hideAllMarkers();
		wipe(structure.saveStructure);
		structure.scan(structure.saveStructure);
		if structure.scanDuration then
			local mapID = WorldMapFrame:GetMapID();
			currentMapID = mapID;
			TRP3_WorldMapButton:Disable();
			setupIconButton(TRP3_WorldMapButton, "ability_mage_timewarp");
			TRP3_WorldMapButton.Cooldown:SetCooldown(GetTime(), structure.scanDuration)
			TRP3_ScanLoaderFrame.time = structure.scanDuration;
			TRP3_ScanLoaderFrame:Show();
			TRP3_ScanLoaderAnimationRotation:SetDuration(structure.scanDuration);
			TRP3_ScanLoaderGlowRotation:SetDuration(structure.scanDuration);
			TRP3_ScanLoaderBackAnimation1Rotation:SetDuration(structure.scanDuration);
			TRP3_ScanLoaderBackAnimation2Rotation:SetDuration(structure.scanDuration);
			playAnimation(TRP3_ScanLoaderAnimation);
			playAnimation(TRP3_ScanFadeIn);
			playAnimation(TRP3_ScanLoaderGlow);
			playAnimation(TRP3_ScanLoaderBackAnimation1);
			playAnimation(TRP3_ScanLoaderBackAnimation2);
			TRP3_API.ui.misc.playSoundKit(40216);
			after(structure.scanDuration, function()
				TRP3_WorldMapButton:Enable();
				setupIconButton(TRP3_WorldMapButton, "icon_treasuremap");
				if mapID == WorldMapFrame:GetMapID() then
					if structure.scanComplete then
						structure.scanComplete(structure.saveStructure);
					end
					displayMarkers(structure);
					TRP3_API.ui.misc.playSoundKit(43493);
				end
				playAnimation(TRP3_ScanLoaderBackAnimationGrow1);
				playAnimation(TRP3_ScanLoaderBackAnimationGrow2);
				playAnimation(TRP3_ScanFadeOut);
				if getConfigValue(CONFIG_UI_ANIMATIONS) then
					after(1, function()
						TRP3_ScanLoaderFrame:Hide();
						TRP3_ScanLoaderFrame:SetAlpha(1);
					end);
				else
					TRP3_ScanLoaderFrame:Hide();
				end
			end);
		else
			if structure.scanComplete then
				structure.scanComplete(structure.saveStructure);
			end
			displayMarkers(structure);
			TRP3_API.ui.misc.playSoundKit(43493);
		end
	end
end
TRP3_API.map.launchScan = launchScan;

local function onButtonClicked(self)
	local structure = {};
	for scanID, scanStructure in pairs(SCAN_STRUCTURES) do
		if not scanStructure.canScan or scanStructure.canScan() == true then
			tinsert(structure, { Utils.str.icon(scanStructure.buttonIcon or "Inv_misc_enggizmos_20", 20) .. " " .. (scanStructure.buttonText or scanID), scanID});
		end
	end
	if #structure == 0 then
		tinsert(structure, {loc.MAP_BUTTON_NO_SCAN, nil});
	end
	displayDropDown(self, structure, launchScan, 0, true);
end

TRP3_API.events.listenToEvent(TRP3_API.events.WORKFLOW_ON_LOAD, function()
	setupIconButton(TRP3_WorldMapButton, "icon_treasuremap");
	TRP3_WorldMapButton.title = loc.MAP_BUTTON_TITLE;
	TRP3_WorldMapButton.subtitle = YELLOW(loc.MAP_BUTTON_SUBTITLE);
	--TRP3_WorldMapButton:SetScript("OnClick", onButtonClicked);	-- TODO : Update scans with the 8.0 changes. For now, disabling button and changing the message.
	TRP3_ScanLoaderFrameScanning:SetText(loc.MAP_BUTTON_SCANNING);


	TRP3_ScanLoaderFrame:SetParent(WorldMapFrame.BorderFrame);
	TRP3_ScanLoaderFrame:SetPoint("CENTER", WorldMapFrame.ScrollContainer, "CENTER");
	TRP3_ScanLoaderFrame:SetScript("OnShow", function(self)
		self.refreshTimer = 0;
	end);
	TRP3_ScanLoaderFrame:SetScript("OnUpdate", function(self, elapsed)
		self.refreshTimer = self.refreshTimer + elapsed;
	end);
end);

local CONFIG_MAP_BUTTON_POSITION = "MAP_BUTTON_POSITION";
local getConfigValue, registerConfigKey, setConfigValue = TRP3_API.configuration.getValue, TRP3_API.configuration.registerConfigKey, TRP3_API.configuration.setValue;

---@param position string
local function placeMapButton(position)
	position = position or "BOTTOMLEFT";

	---@type Frame
	local worldMapButton = TRP3_WorldMapButton;

	worldMapButton:SetParent(WorldMapFrame.BorderFrame);
	worldMapButton:ClearAllPoints();

	local xPadding = 10;
	local yPadding = 10;

	if position == "TOPRIGHT" then
		xPadding = -10;
		yPadding = -45;
	elseif position == "TOPLEFT" then
		yPadding = -30;
	elseif position == "BOTTOMRIGHT" then
		xPadding = -10;
		yPadding = 40;
	end

	worldMapButton:SetPoint(position, WorldMapFrame.ScrollContainer, position, xPadding, yPadding);

	setConfigValue(CONFIG_MAP_BUTTON_POSITION, position);
end

TRP3_API.events.listenToEvent(TRP3_API.events.WORKFLOW_ON_LOADED, function()
	registerConfigKey(CONFIG_MAP_BUTTON_POSITION, "BOTTOMLEFT");

	tinsert(TRP3_API.configuration.CONFIG_FRAME_PAGE.elements, {
		inherit = "TRP3_ConfigH1",
		title = loc.CO_MAP_BUTTON,
	});

	tinsert(TRP3_API.configuration.CONFIG_FRAME_PAGE.elements, {
		inherit = "TRP3_ConfigDropDown",
		widgetName = "TRP3_ConfigurationFrame_MapButtonWidget",
		title = loc.CO_MAP_BUTTON_POS,
		listContent = {
			{loc.CO_ANCHOR_BOTTOM_LEFT, "BOTTOMLEFT"},
			{loc.CO_ANCHOR_TOP_LEFT, "TOPLEFT"},
			{loc.CO_ANCHOR_BOTTOM_RIGHT, "BOTTOMRIGHT"},
			{loc.CO_ANCHOR_TOP_RIGHT, "TOPRIGHT"}
		},
		listCallback = placeMapButton,
		listCancel = true,
		configKey = CONFIG_MAP_BUTTON_POSITION,
	});

	placeMapButton(getConfigValue(CONFIG_MAP_BUTTON_POSITION));

end);

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Broadcast Lifecycle
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

-- When we get BROADCAST_CHANNEL_CONNECTING we'll ensure the button is
-- disabled and tell the user things are firing up.
TRP3_API.events.listenToEvent(TRP3_API.events.BROADCAST_CHANNEL_CONNECTING, function()
	TRP3_WorldMapButton:SetEnabled(false);
	TRP3_WorldMapButton.subtitle = YELLOW(loc.MAP_BUTTON_SUBTITLE_CONNECTING);

	TRP3_WorldMapButtonIcon:SetDesaturated(true);
end);

-- If we get BROADCAST_CHANNEL_OFFLINE we'll ensure the button remains
-- disabled and dump the localised error into the tooltip, to be useful.
TRP3_API.events.listenToEvent(TRP3_API.events.BROADCAST_CHANNEL_OFFLINE, function(reason)
	TRP3_WorldMapButton:SetEnabled(false);
	TRP3_WorldMapButton.subtitle = YELLOW(loc.MAP_BUTTON_SUBTITLE_OFFLINE):format(reason);

	TRP3_WorldMapButtonIcon:SetDesaturated(true);
end);

-- When we get BROADCAST_CHANNEL_READY it's time to enable the button use the
-- standard tooltip description.
TRP3_API.events.listenToEvent(TRP3_API.events.BROADCAST_CHANNEL_READY, function()
	-- TODO : Update scans with the 8.0 changes. For now, disabling button and changing the message.
	TRP3_WorldMapButton:SetEnabled(false);
	TRP3_WorldMapButton.subtitle = TRP3_API.Ellyb.ColorManager.RED(loc.MAP_BUTTON_SUBTITLE_80_DISABLED);

	TRP3_WorldMapButtonIcon:SetDesaturated(true);
end);
