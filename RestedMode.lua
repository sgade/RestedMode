local ADDON = ...
local NO_LAYOUT = ""
local console = LibStub("AceConsole-3.0"):Embed({})
local defaults = {
  desk  = { maxFPS = 120, targetFPS = 60, useScale = false, scale = 1, layout = NO_LAYOUT },
  couch = { maxFPS = 60, targetFPS = 60, useScale = false, scale = 1, layout = "Gamepad" },
}
local interfaceStyles = { desk = "Mkb", couch = "Gamepad" }
local presets = { Modern = 1, Classic = 2, Gamepad = 3 }
local presetCount = 3
local modePresets = {
  desk  = { { "Modern", LAYOUT_STYLE_MODERN }, { "Classic", LAYOUT_STYLE_CLASSIC } },
  couch = { { "Gamepad", LAYOUT_STYLE_GAMEPAD } },
}
local STYLE = "InputDeviceInterfaceStyle"
local DIALOG = "RESTEDMODE_SWITCH_DESK"
local current, detected, pending
local applyToken = 0
local f = CreateFrame("Frame")

local function log(...)
  print("|cff33ccffRestedMode:|r", ...)
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function same(a, b)
  local x, y = tonumber(a), tonumber(b)
  if x and y then return math.abs(x - y) < 0.005 end
  return a == b
end

local function scaleText(p)
  return p.useScale and ("%.2f"):format(p.scale) or "off"
end

local function cvarsFor(mode)
  local p = RestedModeDB.profiles[mode]
  local cvars = {
    useMaxFPS = "1",
    maxFPS = tostring(p.maxFPS),
    useTargetFPS = "1",
    targetFPS = tostring(p.targetFPS),
    useUiScale = p.useScale and "1" or "0",
    [STYLE] = tostring(Enum.InputDeviceInterfaceType[interfaceStyles[mode]]),
  }
  if p.useScale then cvars.uiScale = ("%.2f"):format(p.scale) end
  if mode == "couch" then cvars.GamePadEnable = "1" end
  return cvars
end

local function layoutIndex(info, name)
  if presets[name] then return presets[name] end
  for i, layout in ipairs(info.layouts) do
    if layout.layoutName == name then return i + presetCount end
  end
end

local function layoutName(info, index)
  for name, i in pairs(presets) do
    if i == index then return name end
  end
  local layout = info.layouts[index - presetCount]
  return layout and layout.layoutName or "unknown"
end

local function setLayout(name)
  if InCombatLockdown() then
    C_Timer.After(5, function() setLayout(name) end)
    return
  end

  local info = C_EditMode.GetLayouts()
  local index = layoutIndex(info, name)
  if not index then
    log("layout not found:", name)
  elseif info.activeLayout ~= index then
    C_EditMode.SetActiveLayout(index)
  end
end

local function summarize(mode, quiet)
  local w, h = GetPhysicalScreenSize()
  local p = RestedModeDB.profiles[mode]

  local changes = {}
  local function change(name, old, new)
    if same(old, new) then return end
    changes[#changes + 1] = ("  %s: %s -> %s"):format(name, tostring(old), tostring(new))
  end

  local cvars = cvarsFor(mode)
  for _, k in ipairs(sortedKeys(cvars)) do
    change(k, C_CVar.GetCVar(k), cvars[k])
  end
  local info = C_EditMode.GetLayouts()
  if p.layout ~= NO_LAYOUT then change("layout", layoutName(info, info.activeLayout), p.layout) end

  if quiet and #changes == 0 then return end
  local lines = { ("%s -> %s (%dx%d, scale %s)"):format(current or "none", mode, w, h, scaleText(p)) }
  for _, line in ipairs(changes) do lines[#lines + 1] = line end
  if #changes == 0 then lines[#lines + 1] = "  no changes" end
  for _, line in ipairs(lines) do log(line) end
  return lines
end

local function switch(mode, quiet)
  if InCombatLockdown() then
    log("switch to", mode, "deferred until combat ends")
    pending = mode
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end

  local lines = summarize(mode, quiet)

  local p = RestedModeDB.profiles[mode]
  local cvars = cvarsFor(mode)
  for k, v in pairs(cvars) do
    if k ~= STYLE and not same(C_CVar.GetCVar(k), v) then C_CVar.SetCVar(k, v) end
  end

  current = mode
  pending = nil

  if not same(C_CVar.GetCVar(STYLE), cvars[STYLE]) then
    RestedModeDB.summary = lines
    C_CVar.SetCVar(STYLE, cvars[STYLE])
    return
  end
  if p.layout ~= NO_LAYOUT then C_Timer.After(1, function() setLayout(p.layout) end) end
end

StaticPopupDialogs[DIALOG] = {
  text = "RestedMode detected the desk screen. Switch to desk mode?",
  button1 = YES,
  button2 = NO,
  OnAccept = function() switch("desk") end,
  OnCancel = function() switch("couch", true) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function inferMode()
  return C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad and "couch" or "desk"
end

local function screenMode()
  local desk = RestedModeDB.deskScreen
  if not desk then return nil end
  local w, h = GetPhysicalScreenSize()
  return w == desk.w and h == desk.h and "desk" or "couch"
end

local function showHint()
  if RestedModeDB.hintShown then return end
  RestedModeDB.hintShown = true
  log("automatic switching is off. To turn it on, go to your desk screen and open Options, AddOns, RestedMode.")
end

local function detect()
  local mode = screenMode()
  if not mode then showHint() end
  if current and mode == detected then return end

  detected = mode
  local summary = RestedModeDB.summary
  RestedModeDB.summary = nil
  current = current or inferMode()
  StaticPopup_Hide(DIALOG)

  if summary then
    for _, line in ipairs(summary) do log(line) end
  end

  if mode == current or summary then
    switch(current, true)
  elseif mode == "couch" then
    switch("couch")
  elseif mode == "desk" then
    StaticPopup_Show(DIALOG)
  end
end

local function useCurrentScreen()
  local w, h = GetPhysicalScreenSize()
  RestedModeDB.deskScreen = { w = w, h = h }
  log(("desk screen: %dx%d"):format(w, h))
  detected = nil
  detect()
end

local function forgetDeskScreen()
  RestedModeDB.deskScreen = nil
  detected = nil
  StaticPopup_Hide(DIALOG)
  log("automatic switching is off")
end

local function status()
  local desk = RestedModeDB.deskScreen
  log(("active: %s (detected: %s)"):format(current or "none", detected or "not set up"))
  log("desk screen:", desk and ("%dx%d"):format(desk.w, desk.h) or "not set")
  for _, mode in ipairs(sortedKeys(defaults)) do
    local cvars = cvarsFor(mode)
    local parts = {}
    for _, k in ipairs(sortedKeys(cvars)) do
      parts[#parts + 1] = k .. " " .. cvars[k]
    end
    local layout = RestedModeDB.profiles[mode].layout
    parts[#parts + 1] = "layout " .. (layout == NO_LAYOUT and "no change" or layout)
    log(("  %s: %s"):format(mode, table.concat(parts, ", ")))
  end
end

local function queueApply(mode)
  if mode ~= current then return end
  applyToken = applyToken + 1
  local token = applyToken
  C_Timer.After(0.5, function()
    if token == applyToken then switch(current, true) end
  end)
end

local function layoutOptions(mode)
  return function()
    local container = Settings.CreateControlTextContainer()
    container:Add(NO_LAYOUT, "No layout change")
    for _, preset in ipairs(modePresets[mode]) do
      container:Add(preset[1], preset[2])
    end

    local style = Enum.InputDeviceInterfaceType[interfaceStyles[mode]]
    for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
      if (layout.interfaceStyle or Enum.InputDeviceInterfaceType.Mkb) == style then
        container:Add(layout.layoutName, layout.layoutName)
      end
    end
    return container:GetData()
  end
end

local function addProfile(category, panel, mode, title)
  local function register(key, varType, name)
    local setting = Settings.RegisterAddOnSetting(category, "RestedMode_" .. mode .. "_" .. key, key,
      RestedModeDB.profiles[mode], varType, name, defaults[mode][key])
    setting:SetValueChangedCallback(function() queueApply(mode) end)
    return setting
  end

  local function sliderOptions(minValue, maxValue, step, format)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
    return options
  end

  local function fps(value) return ("%.0f FPS"):format(value) end
  local function percent(value) return ("%.0f%%"):format(value * 100) end

  panel:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))

  Settings.CreateSlider(category, register("maxFPS", Settings.VarType.Number, "Max FPS"),
    sliderOptions(8, 200, 1, fps), "The highest frame rate in this mode.")
  Settings.CreateSlider(category, register("targetFPS", Settings.VarType.Number, "Target FPS"),
    sliderOptions(8, 200, 1, fps), "The game lowers graphics quality if the frame rate is below this value.")

  panel:AddInitializer(CreateSettingsCheckboxSliderInitializer(
    register("useScale", Settings.VarType.Boolean, "Use UI Scale"), "Use UI Scale",
    "If this is off, the game's UI Scale option is off in this mode.",
    register("scale", Settings.VarType.Number, "UI Scale"), sliderOptions(0.65, 1.15, 0.01, percent), "UI Scale",
    "The value for the game's UI Scale option in this mode."))

  Settings.CreateDropdown(category, register("layout", Settings.VarType.String, "Edit Mode layout"),
    layoutOptions(mode), "Only layouts for the interface of this mode are in this list.")
end

local function addSwitching(panel)
  panel:AddInitializer(CreateSettingsListSectionHeaderInitializer("Automatic switching"))
  panel:AddInitializer(CreateSettingsButtonInitializer("Use current screen as desk", "Save", useCurrentScreen,
    "Saves the size of this screen. A screen with a different size then counts as the couch.", true))
  panel:AddInitializer(CreateSettingsButtonInitializer("Forget desk screen", "Forget", forgetDeskScreen,
    "Turns off automatic switching. The slash command continues to work.", true))
end

local function loadProfiles()
  RestedModeDB = RestedModeDB or {}
  RestedModeDB.profiles = RestedModeDB.profiles or {}
  for mode, values in pairs(defaults) do
    local p = RestedModeDB.profiles[mode] or {}
    RestedModeDB.profiles[mode] = p
    for k, v in pairs(values) do
      if p[k] == nil then p[k] = v end
    end
  end
end

local function buildSettings()
  local category, panel = Settings.RegisterVerticalLayoutCategory("RestedMode")
  addSwitching(panel)
  addProfile(category, panel, "desk", "Desk")
  addProfile(category, panel, "couch", "Couch")
  Settings.RegisterAddOnCategory(category)
end

console:RegisterChatCommand("restedmode", function(input)
  local arg = console:GetArgs(input)
  if not arg then
    status()
  elseif defaults[arg:lower()] then
    StaticPopup_Hide(DIALOG)
    switch(arg:lower())
  else
    log("usage: /restedmode [desk|couch]")
  end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, e, arg)
  if e == "ADDON_LOADED" then
    if arg == ADDON then
      self:UnregisterEvent(e)
      loadProfiles()
      buildSettings()
    end
    return
  end

  if e == "PLAYER_REGEN_ENABLED" then
    self:UnregisterEvent(e)
    C_Timer.After(1, function()
      if pending then switch(pending, true) end
    end)
    return
  end

  if e == "PLAYER_ENTERING_WORLD" then
    self:UnregisterEvent(e)
    self:RegisterEvent("DISPLAY_SIZE_CHANGED")
  end
  C_Timer.After(1, detect)
end)
