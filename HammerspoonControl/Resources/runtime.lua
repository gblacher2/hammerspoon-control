-- Hammerspoon Control Managed Runtime
-- Managed file stored at ~/.hammerspoon/hammerspoon-control/runtime.lua
-- DO NOT edit manually; managed by Hammerspoon Control macOS app.

local hsControl = {}
_G.hsControlRuntime = hsControl
_G.hsControlSentinel = nil

-- Stop existing watchers/timers idempotently before replacing them
if _G.hsControlRuntime_old then
  if _G.hsControlRuntime_old.screenWatcher then pcall(function() _G.hsControlRuntime_old.screenWatcher:stop() end) end
  if _G.hsControlRuntime_old.caffeinateWatcher then pcall(function() _G.hsControlRuntime_old.caffeinateWatcher:stop() end) end
  if _G.hsControlRuntime_old.externalGammaTimer then pcall(function() _G.hsControlRuntime_old.externalGammaTimer:stop() end) end
  if _G.hsControlRuntime_old.debounceTimer then pcall(function() _G.hsControlRuntime_old.debounceTimer:stop() end) end
  if _G.hsControlRuntime_old.zoomEventtap then pcall(function() _G.hsControlRuntime_old.zoomEventtap:stop() end) end
end
_G.hsControlRuntime_old = hsControl

local settingsPath = hs.configdir .. "/hammerspoon-control/settings.json"
local nightlightExecutable = "/opt/homebrew/bin/nightlight"

local function loadSettings()
  local file = io.open(settingsPath, "r")
  if not file then
    print("Hammerspoon Control: settings.json missing, using internal defaults.")
    return nil
  end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(hs.json.decode, content)
  if ok and type(data) == "table" then
    return data
  else
    print("Hammerspoon Control: Failed to decode settings.json: " .. tostring(data))
    return nil
  end
end

local rawSettings = loadSettings()
local rawWarmth = (type(rawSettings) == "table" and type(rawSettings.warmth) == "table") and rawSettings.warmth or {}
local rawZoom = (type(rawSettings) == "table" and type(rawSettings.zoom) == "table") and rawSettings.zoom or {}

local function sanitizeBool(val, defaultVal)
  if type(val) == "boolean" then return val end
  return defaultVal
end

local function sanitizeNum(val, minVal, maxVal, defaultVal)
  if type(val) == "number" and val >= minVal and val <= maxVal then
    return val
  end
  return defaultVal
end

local function sanitizeEnum(val, allowedMap, defaultVal)
  if type(val) == "string" and allowedMap[val] then
    return val
  end
  return defaultVal
end

local warmthEnabled = sanitizeBool(rawWarmth.enabled, true)
local scheduleMode = sanitizeEnum(rawWarmth.scheduleMode, { sunsetToSunrise=true, alwaysWarm=true, alwaysNeutral=true }, "sunsetToSunrise")
local tempK = sanitizeNum(rawWarmth.temperatureK, 3000, 6500, 4300)
local refreshInterval = sanitizeNum(rawWarmth.refreshIntervalSeconds, 15, 300, 60)
local displayDebounce = sanitizeNum(rawWarmth.displayDebounceSeconds, 0.5, 10.0, 2.0)
local fallbackLat = sanitizeNum(rawWarmth.fallbackLatitude, -90.0, 90.0, -23.5505)
local fallbackLong = sanitizeNum(rawWarmth.fallbackLongitude, -180.0, 180.0, -46.6333)

local builtInNamesSet = {}
if type(rawWarmth.builtInDisplayNames) == "table" and #rawWarmth.builtInDisplayNames > 0 then
  for _, name in ipairs(rawWarmth.builtInDisplayNames) do
    if type(name) == "string" and #name > 0 then
      builtInNamesSet[name] = true
    end
  end
end

if next(builtInNamesSet) == nil then
  builtInNamesSet["Built-in Retina Display"] = true
  builtInNamesSet["Color LCD"] = true
  builtInNamesSet["Liquid Retina XDR Display"] = true
end

local function kelvinToWhitepoint(temp)
  if temp >= 6500 then
    return { red = 1.0, green = 1.0, blue = 1.0 }
  end
  if temp <= 3000 then
    return { red = 1.0, green = 0.7042, blue = 0.4578 }
  end
  if temp == 4300 then
    return { red = 1.0, green = 0.85347859, blue = 0.70281616 }
  end

  local g, b
  if temp <= 4300 then
    local factor = (temp - 3000) / (4300 - 3000)
    g = 0.7042 + factor * (0.85347859 - 0.7042)
    b = 0.4578 + factor * (0.70281616 - 0.4578)
  else
    local factor = (temp - 4300) / (6500 - 4300)
    g = 0.85347859 + factor * (1.0 - 0.85347859)
    b = 0.70281616 + factor * (1.0 - 0.70281616)
  end
  return { red = 1.0, green = g, blue = b }
end

local nightWhitepoint = kelvinToWhitepoint(tempK)
local neutralWhitepoint = { red = 1.0, green = 1.0, blue = 1.0 }
local blackpoint = { red = 0.0, green = 0.0, blue = 0.0 }
local saoPauloFallback = { latitude = fallbackLat, longitude = fallbackLong }

local function externalScreens()
  local result = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    if not builtInNamesSet[screen:name()] then
      table.insert(result, screen)
    end
  end
  return result
end

local function timezoneOffsetHours()
  local offset = os.date("%z")
  local sign = offset:sub(1, 1) == "-" and -1 or 1
  return sign * (tonumber(offset:sub(2, 3)) + tonumber(offset:sub(4, 5)) / 60)
end

local function currentLocation()
  local location = hs.location.get()
  if location and location.horizontalAccuracy and location.horizontalAccuracy >= 0 then
    return location, "macOS Location Services"
  end
  return saoPauloFallback, "Sao Paulo fallback"
end

local function isNighttime()
  if scheduleMode == "alwaysWarm" then return true, "Always warm mode" end
  if scheduleMode == "alwaysNeutral" then return false, "Always neutral mode" end

  local location, source = currentLocation()
  local offset = timezoneOffsetHours()
  local lat = location.latitude
  local long = location.longitude
  local sunrise = hs.location.sunrise(lat, long, offset)
  local sunset = hs.location.sunset(lat, long, offset)

  if type(sunrise) ~= "number" or type(sunset) ~= "number" then
    print("Could not calculate sunrise/sunset; keeping external displays neutral.")
    return false, source
  end

  local now = os.time()
  return (now < sunrise or now >= sunset), source
end

local function applyGamma(screens, whitepoint, description)
  local targetWhitepoint = whitepoint or neutralWhitepoint
  for _, screen in ipairs(screens) do
    local applied = screen:setGamma(targetWhitepoint, blackpoint)
    print(string.format("%s: %s (gamma applied: %s)", screen:name(), description, tostring(applied)))
  end
end

local pauseUntilEpoch = sanitizeNum(rawWarmth.pauseUntilEpoch, 0, 9999999999, 0)

local function writeStatusData(nighttime, source, isPaused)
  local statusPath = hs.configdir .. "/hammerspoon-control/status.json"
  local location, locSource = currentLocation()
  local offset = timezoneOffsetHours()
  local sunrise = hs.location.sunrise(location.latitude, location.longitude, offset)
  local sunset = hs.location.sunset(location.latitude, location.longitude, offset)

  local screensList = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local isBuiltIn = builtInNamesSet[screen:name()] == true
    table.insert(screensList, {
      name = screen:name(),
      isBuiltIn = isBuiltIn,
      gammaApplied = (not isBuiltIn and warmthEnabled and nighttime and not isPaused) and ("warm (" .. tostring(tempK) .. "K)") or "neutral"
    })
  end

  local statusData = {
    updatedAt = os.time(),
    warmthEnabled = warmthEnabled,
    scheduleMode = scheduleMode,
    nighttime = nighttime,
    isPaused = isPaused,
    pauseUntilEpoch = (pauseUntilEpoch > 0 and pauseUntilEpoch or nil),
    locationSource = source or locSource,
    temperatureK = tempK,
    sunriseEpoch = (type(sunrise) == "number" and sunrise or nil),
    sunsetEpoch = (type(sunset) == "number" and sunset or nil),
    displays = screensList
  }

  local file = io.open(statusPath, "w")
  if file then
    file:write(hs.json.encode(statusData))
    file:close()
  end
end

local function updateExternalDisplayColor()
  local screens = externalScreens()
  local now = os.time()
  local isPaused = (pauseUntilEpoch > 0 and now < pauseUntilEpoch)

  if not warmthEnabled then
    if #screens > 0 then
      applyGamma(screens, neutralWhitepoint, "warmth disabled (restored neutral gamma)")
    end
    writeStatusData(false, "warmth disabled", false)
    return
  end

  if isPaused then
    if #screens > 0 then
      applyGamma(screens, neutralWhitepoint, "warmth temporarily paused")
    end
    writeStatusData(false, "temporarily paused", true)
    return
  end

  if #screens > 0 then
    if hs.fs.attributes(nightlightExecutable) then
      hs.execute(nightlightExecutable .. " off")
    end
    local nighttime, source = isNighttime()
    if nighttime then
      applyGamma(screens, nightWhitepoint, "night warmth enabled via " .. source)
    else
      applyGamma(screens, neutralWhitepoint, "daytime neutral gamma via " .. source)
    end
    writeStatusData(nighttime, source, false)
  else
    print("Built-in display only. Leaving macOS Night Shift completely in charge.")
    local nighttime, source = isNighttime()
    writeStatusData(nighttime, source, false)
  end
end

if warmthEnabled then
  local function debouncedUpdate()
    print("Display change event detected. Re-evaluating after debounce...")
    if hsControl.debounceTimer then hsControl.debounceTimer:stop() end
    hsControl.debounceTimer = hs.timer.doAfter(displayDebounce, updateExternalDisplayColor)
  end

  hsControl.screenWatcher = hs.screen.watcher.new(debouncedUpdate)
  hsControl.screenWatcher:start()
  hsControl.caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake or event == hs.caffeinate.watcher.screensDidWake or event == hs.caffeinate.watcher.screensDidUnlock then
      print("System/screen wake event detected. Re-evaluating display color immediately...")
      updateExternalDisplayColor()
    end
  end)
  hsControl.caffeinateWatcher:start()
  hs.location.start()
  hsControl.externalGammaTimer = hs.timer.doEvery(refreshInterval, updateExternalDisplayColor)
  updateExternalDisplayColor()
else
  updateExternalDisplayColor()
end

--------------------------------------------------------------------------------
-- Command + Mouse Wheel Zoom
--------------------------------------------------------------------------------
local zoomEnabled = sanitizeBool(rawZoom.enabled, true)
local zoomMinDelta = sanitizeNum(rawZoom.minDelta, 0.01, 1.00, 0.08)
local zoomDebounceSeconds = sanitizeNum(rawZoom.debounceSeconds, 0.00, 0.50, 0.05)
local zoomDirection = sanitizeEnum(rawZoom.direction, { scrollUpZoomsIn=true, scrollUpZoomsOut=true }, "scrollUpZoomsIn")
local lastFireTime = 0

if zoomEnabled then
  hsControl.zoomEventtap = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function(event)
    local flags = event:getFlags()
    if not flags.cmd then return false end
    if flags.shift or flags.alt or flags.ctrl or flags.fn then return false end

    local verticalDelta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
    local horizontalDelta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis2)

    if math.abs(horizontalDelta) > math.abs(verticalDelta) then return false end
    if math.abs(verticalDelta) < zoomMinDelta then return false end

    local now = hs.timer.secondsSinceEpoch()
    if (now - lastFireTime) < zoomDebounceSeconds then
      return true
    end
    lastFireTime = now

    local zoomIn = (verticalDelta > 0)
    if zoomDirection == "scrollUpZoomsOut" then
      zoomIn = not zoomIn
    end

    if zoomIn then
      hs.eventtap.keyStroke({ "cmd" }, "=", 0)
    else
      hs.eventtap.keyStroke({ "cmd" }, "-", 0)
    end

    return true
  end)

  hsControl.zoomEventtap:start()
  print("Hammerspoon Cmd+Scroll zoom watcher initialized.")
end

-- Publish versioned readiness sentinel only after settings load and runtime objects initialize successfully
local currentGen = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
if hs and hs.timer and hs.timer.secondsSinceEpoch then
  currentGen = tostring(hs.timer.secondsSinceEpoch()) .. "_" .. tostring(math.random(100000, 999999))
end

_G.hsControlSentinel = {
  version = 1,
  ready = true,
  loadedAt = os.time(),
  generation = currentGen
}
print("Hammerspoon Control: Runtime initialized successfully, sentinel v1 published (gen: " .. currentGen .. ").")
