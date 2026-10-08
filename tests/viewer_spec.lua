-- Lua 5.3+ host tests. No Roblox or network required.
local files, folders, scanner = {}, {}, nil
local reports, cleanupCount = {}, 0
local function makeUI()
    local ui = { Options = {}, Toggles = {}, Tabs = {}, Unloaded = false, unloaders = {} }
    local window = {}
    local function control(registry, id, config)
        assert(not registry[id], "duplicate global ID")
        local c = { Value = config.Default }
        function c:OnChanged(fn) self.changed = fn end
        function c:SetValue(value)
            self.Value = value
            if config.Callback then config.Callback(value) end
            if self.changed then self.changed(value) end
        end
        registry[id] = c
        return c
    end
    local function group()
        local g = {}
        function g:AddToggle(id, config) return control(ui.Toggles, id, config) end
        function g:AddInput(id, config) return control(ui.Options, id, config) end
        function g:AddLabel(text) return { Text = text } end
        function g:AddDependencyBox() return group() end
        function g:SetupDependencies(deps)
            assert(deps[1][1].Value ~= nil, "dependency control not forwarded")
        end
        return g
    end
    function window:AddTab(name)
        assert(not ui.Tabs[name], "duplicate tab")
        local tab = { Destroyed = false }
        function tab:AddLeftGroupbox() return group() end
        function tab:Show() ui.ActiveTab = self end
        function tab:Hide() ui.ActiveTab = nil end
        function tab:Destroy() self.Destroyed = true ui.Tabs[name] = nil end
        ui.Tabs[name] = tab
        if not ui.ActiveTab then tab:Show() end
        return tab
    end
    function ui:CreateWindow(config)
        assert(config.Title == "Mr H mspaint addon viewer")
        self.Window = window
        return window
    end
    function ui:OnUnload(fn) self.unloaders[#self.unloaders + 1] = fn end
    function ui:Unload()
        self.Unloaded = true
        for _, fn in ipairs(self.unloaders) do fn() end
    end
    return ui
end
_G.__mockLibrary = makeUI()
Enum = { KeyCode = { RightControl = "RightControl" } }
game = { GameId = 2440500124, PlaceId = 6839171747, HttpGet = function() return "return __mockLibrary" end }
getgenv = function() return _G end
getfenv = function() return _G end
setfenv = function(fn, env)
    for i = 1, 20 do
        local name = debug.getupvalue(fn, i)
        if name == "_ENV" then debug.setupvalue(fn, i, env) return fn end
        if not name then break end
    end
    return fn
end
loadstring = load
isfolder = function(path) return folders[path] == true end
makefolder = function(path) local parent=path:match("^(.*)/[^/]+$") assert(not parent or folders[parent], "parent folder missing") folders[path] = true end
listfiles = function(path) assert(path=="addonuser/addons", "wrong scan folder") local result = {} for path in pairs(files) do result[#result + 1] = path end return result end
readfile = function(path) return assert(files[path]) end
warn = function(message) reports[#reports + 1] = message end
task = { wait = coroutine.yield, spawn = function(fn) scanner = coroutine.create(fn) assert(coroutine.resume(scanner)) end }
onCleanup = function() cleanupCount = cleanupCount + 1 end
local viewer = assert(loadfile("viewer.lua"))()
assert(folders["addonuser"] and folders["addonuser/addons"] and next(__mockLibrary.Tabs) == nil, "empty hub created content")
local function scan() local ok, reason = coroutine.resume(scanner) assert(ok, reason) end
local addon = [[
mspaint.AddonInfo = { Name = "Test", Title = "Test", Game = "doors/doors" }
local toggle = mspaint.Groupbox:AddToggle("Enabled", { Default = false, Func = function(v) callbackValue = v end })
local dependencies = mspaint.Groupbox:AddDependencyBox()
dependencies:SetupDependencies({ { toggle, true } })
Toggles.Enabled:SetValue(true)
assert(callbackValue == true)
Library:OnUnload(onCleanup)
]]
files["addonuser/addons/a.lua"] = addon
files["addonuser/addons/b.luau"] = addon
files["addonuser/addons/ignored.md"] = "error('must not execute')"
scan()
local count = 0 for _ in pairs(__mockLibrary.Tabs) do count = count + 1 end
assert(count == 2, "two addons must have independent tabs")
local controls = 0 for _, c in pairs(__mockLibrary.Toggles) do controls = controls + 1 assert(c.Value == true) end
assert(controls == 2, "control IDs collided")
scan() assert(cleanupCount == 0, "unchanged addons reloaded")
files["addonuser/addons/a.lua"] = addon .. "\n-- edited"
scan() assert(cleanupCount == 1, "reload did not clean up")
files["addonuser/addons/b.luau"] = nil
scan() assert(cleanupCount == 2, "removal did not clean up")
files["addonuser/addons/wrong.txt"] = [[mspaint.AddonInfo={Name="Wrong",Title="Wrong",Game="doors/lobby"}; error("continued wrong game")]]
files["addonuser/addons/broken.lua"] = "this is invalid Lua"
files["addonuser/addons/custom.lua"] = [[
mspaint.AddonInfo={Name="Custom",Title="Custom",Game="*"}
Library.Window:AddTab("Custom", "route"):AddLeftGroupbox("Main"):AddInput("Text",{Default="hello"})
assert(Options.Text.Value=="hello")
Library:OnUnload(onCleanup)
]]
scan()
assert(__mockLibrary.Tabs.Wrong == nil and __mockLibrary.Tabs.Custom)
assert(#reports == 1, "syntax error not isolated or wrong-game produced errors")
files["addonuser/addons/fails.lua"] = [[
mspaint.AddonInfo={Name="Fails",Title="Fails",Game="*"}
mspaint.Groupbox:AddLabel("partial")
Library:OnUnload(onCleanup)
error("intentional")
]]
scan() assert(__mockLibrary.Tabs.Fails == nil and cleanupCount == 3)
for path in pairs(files) do files[path] = nil end
scan() assert(next(__mockLibrary.Tabs) == nil and cleanupCount == 5, "removal did not restore empty window")
viewer:Unload()
assert(not viewer.Running and __mockLibrary.Unloaded and MrHAddonViewer == nil)
print("PASS: empty startup, hot add/edit/remove, ID isolation, callback/registry forwarding, dependency controls, game filters, custom tabs, errors, cleanup")
