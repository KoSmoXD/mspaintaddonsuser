-- Mr H mspaint addon viewer
-- Standalone Obsidian host. Put this launcher OUTSIDE addonuser/addons.
-- Addon files are executable code, not a sandbox. Only install trusted addons.
local ROOT = "addonuser/addons"
local LIBRARY_URL = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua"
local globals = getgenv and getgenv() or _G
local baseEnvironment = getfenv(1)
for _, name in ipairs({ "listfiles", "readfile", "isfolder", "makefolder", "loadstring", "setfenv" }) do
    assert(type(baseEnvironment[name]) == "function", "Mr H viewer requires " .. name)
end
if not isfolder("addonuser") then makefolder("addonuser") end
if not isfolder(ROOT) then makefolder(ROOT) end
local previous = globals.MrHAddonViewer
if previous and type(previous.Unload) == "function" then previous:Unload() end

local Library = assert(loadstring(game:HttpGet(LIBRARY_URL), "@Obsidian"))()
local Window = Library:CreateWindow({
    Title = "Mr H mspaint addon viewer",
    Footer = "",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = false,
    ToggleKeybind = Enum.KeyCode.RightControl,
})
local viewer = { Library = Library, Window = Window, Addons = {}, Running = true }
globals.MrHAddonViewer = viewer
local serial = 0
local SKIP = {}

local function report(path, message)
    warn("[Mr H addon viewer] " .. path .. ": " .. tostring(message))
end

local function gameMatches(filter)
    if filter == "*" then return true end
    if type(filter) == "number" then return filter == game.PlaceId or filter == game.GameId end
    if type(filter) == "table" then
        for _, value in ipairs(filter) do if gameMatches(value) then return true end end
        return false
    end
    if type(filter) ~= "string" then return false end
    if tonumber(filter) then return gameMatches(tonumber(filter)) end
    if game.GameId == 2440500124 then
        if filter == "doors/lobby" then return game.PlaceId == 6516141723 end
        if filter == "doors/doors" then return game.PlaceId ~= 6516141723 end
    end
    return false
end

local function cleanup(record)
    if record.dead then return end
    record.dead = true
    for i = #record.cleanup, 1, -1 do
        local ok, reason = pcall(record.cleanup[i])
        if not ok then report(record.path, reason) end
    end
    for i = #record.tabs, 1, -1 do
        local tab = record.tabs[i]
        if Library.ActiveTab == tab then tab:Hide() Library.ActiveTab = nil end
        if not tab.Destroyed then pcall(function() tab:Destroy() end) end
    end
    if not Library.ActiveTab and not Library.Unloaded then
        for _, tab in pairs(Library.Tabs) do
            if type(tab) == "table" and not tab.Destroyed and tab.Show then tab:Show() break end
        end
    end
end

local indexed = {
    AddToggle = true, AddCheckbox = true, AddInput = true, AddSlider = true,
    AddDropdown = true, AddColorPicker = true, AddKeyPicker = true,
}

local function runAddon(path, source)
    serial = serial + 1
    local record = { path = path, source = source, cleanup = {}, tabs = {}, dead = false }
    viewer.Addons[path] = record
    local prefix = "MrH_" .. serial .. "_"
    local proxies, originals = {}, {}
    local info, groupbox
    local wrap

    local function unwrap(value, visited)
        if type(value) ~= "table" then return value end
        if originals[value] then return originals[value] end
        visited = visited or {}
        if visited[value] then return visited[value] end
        local result = {}
        visited[value] = result
        for k, v in pairs(value) do result[k] = unwrap(v, visited) end
        return result
    end

    local function newTab(...)
        assert(info, "Set mspaint.AddonInfo before creating UI")
        local args = table.pack(...)
        local name = type(args[1]) == "table" and args[1].Name or args[1]
        name = tostring(name or info.Title)
        if Library.Tabs[name] then name = name .. " [" .. serial .. "]" end
        if type(args[1]) == "table" then args[1].Name = name else args[1] = name end
        local tab = Window:AddTab(table.unpack(args, 1, args.n))
        record.tabs[#record.tabs + 1] = tab
        return tab
    end

    wrap = function(object)
        if type(object) ~= "table" then return object end
        if proxies[object] then return proxies[object] end
        local proxy = {}
        proxies[object], originals[proxy] = proxy, object
        setmetatable(proxy, {
            __index = function(_, key)
                if object == Library and key == "Unloaded" then return record.dead or Library.Unloaded end
                if object == Library and key == "OnUnload" then
                    return function(_, callback)
                        assert(type(callback) == "function", "OnUnload expects a function")
                        if record.dead then callback() else record.cleanup[#record.cleanup + 1] = callback end
                    end
                end
                if object == Library and key == "GiveSignal" then
                    return function(_, connection)
                        assert(not record.dead, "Addon has been unloaded")
                        record.cleanup[#record.cleanup + 1] = function() connection:Disconnect() end
                        return connection
                    end
                end
                local value = object[key]
                if type(value) ~= "function" then return wrap(value) end
                return function(_, ...)
                    assert(not record.dead, "Addon has been unloaded")
                    local args = table.pack(...)
                    for i = 1, args.n do args[i] = unwrap(args[i]) end
                    if indexed[key] then args[1] = prefix .. tostring(args[1]) end
                    -- mspaint's legacy examples use Func for toggle callbacks.
                    if key == "AddToggle" and type(args[2]) == "table" and args[2].Func and not args[2].Callback then
                        args[2].Callback = args[2].Func
                    end
                    if key == "AddButton" and type(args[1]) == "table" and args[1].Idx then
                        args[1].Idx = prefix .. tostring(args[1].Idx)
                    end
                    if object == Window and key == "AddTab" then return wrap(newTab(table.unpack(args, 1, args.n))) end
                    local results = table.pack(value(object, table.unpack(args, 1, args.n)))
                    for i = 1, results.n do results[i] = wrap(results[i]) end
                    return table.unpack(results, 1, results.n)
                end
            end,
            __newindex = function(_, key, value) object[key] = unwrap(value) end,
        })
        return proxy
    end

    local function localRegistry(registry)
        return setmetatable({}, {
            __index = function(_, key) return wrap(registry[prefix .. tostring(key)]) end,
            __newindex = function(_, key, value) registry[prefix .. tostring(key)] = unwrap(value) end,
        })
    end

    local host = setmetatable({}, {
        __index = function(_, key)
            if key == "AddonInfo" then return info end
            if key == "Library" then return wrap(Library) end
            if key == "CurrentLanguage" then return "en" end
            if key == "ExecutorSupport" then
                return setmetatable({}, { __index = function(_, name) return type(baseEnvironment[name]) == "function" end })
            end
            if key == "Groupbox" then
                assert(info, "Set mspaint.AddonInfo before accessing Groupbox")
                if not groupbox then
                    local tab = newTab(info.Title, "puzzle")
                    groupbox = tab:AddLeftGroupbox(info.Title)
                    if info.Description and info.Description ~= "" then groupbox:AddLabel(info.Description, true) end
                end
                return wrap(groupbox)
            end
        end,
        __newindex = function(_, key, value)
            assert(key == "AddonInfo", "Unsupported mspaint field: " .. tostring(key))
            assert(not info, "AddonInfo may only be assigned once")
            assert(type(value) == "table" and type(value.Name) == "string" and value.Name:match("^%S+$"), "AddonInfo.Name must be nonempty without spaces")
            assert(type(value.Title) == "string" and value.Title ~= "", "AddonInfo.Title is required")
            assert(value.Game ~= nil, "AddonInfo.Game is required")
            if not gameMatches(value.Game) then error(SKIP, 0) end
            info = value
        end,
    })
    local environment = setmetatable({
        mspaint = host, Library = wrap(Library),
        Options = localRegistry(Library.Options), Toggles = localRegistry(Library.Toggles),
    }, { __index = baseEnvironment })
    local chunk, syntaxError = loadstring(source, "@" .. path)
    if not chunk then record.error = syntaxError cleanup(record) report(path, syntaxError) return end
    setfenv(chunk, environment)
    local ok, reason = pcall(chunk)
    if not ok or not info then
        cleanup(record)
        if reason ~= SKIP then
            record.error = reason or "Missing mspaint.AddonInfo"
            report(path, record.error)
        end
    end
end

local function scan()
    local ok, paths = pcall(listfiles, ROOT)
    if not ok then report(ROOT, paths) return end
    local files, seen = {}, {}
    for _, rawPath in ipairs(paths) do
        local path = rawPath:gsub("\\", "/"):gsub("^%./", "")
        -- Only direct files, not directories or nested addon trees.
        local name = path:match("([^/]+)$")
        if name and (name:lower():match("%.lua$") or name:lower():match("%.luau$") or name:lower():match("%.txt$"))
            and not isfolder(path) then
            files[#files + 1] = path
        end
    end
    table.sort(files)
    for _, path in ipairs(files) do
        seen[path] = true
        local readOk, source = pcall(readfile, path)
        if readOk then
            local old = viewer.Addons[path]
            if not old or old.source ~= source then
                if old then cleanup(old) end
                runAddon(path, source)
            end
        else
            report(path, source)
        end
    end
    for path, record in pairs(viewer.Addons) do
        if not seen[path] then cleanup(record) viewer.Addons[path] = nil end
    end
end

function viewer:Unload()
    if not self.Running then return end
    self.Running = false
    for _, record in pairs(self.Addons) do cleanup(record) end
    if not Library.Unloaded then Library:Unload() end
    if globals.MrHAddonViewer == self then globals.MrHAddonViewer = nil end
end
Library:OnUnload(function()
    viewer.Running = false
    for _, record in pairs(viewer.Addons) do cleanup(record) end
    if globals.MrHAddonViewer == viewer then globals.MrHAddonViewer = nil end
end)
-- No default tabs, controls, sample addon, settings or credits.
scan()
task.spawn(function()
    while viewer.Running do
        task.wait(2)
        if viewer.Running then
            local ok, reason = pcall(scan)
            if not ok then report("scan", reason) end
        end
    end
end)
return viewer
