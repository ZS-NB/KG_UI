local IconsURL = "https://raw.githubusercontent.com/ZS-NB/KG_UI/main/Icons.lua"

local Icons = nil
do
    local ok, result = pcall(function()
        local src = game:HttpGetAsync(IconsURL)
        return loadstring(src)()
    end)
    if ok and type(result) == "table" then
        Icons = result
    else
        Icons = {}
        warn("[KG_UI] Icons.lua 加载失败: " .. tostring(result))
    end
end

-- ============================================================
-- ② 图片下载 + 缓存（用户填 GitHub 链接时用）
-- ============================================================
local MediaCache = "KG_UI_Cache"
local HAS_CUSTOMASSET = (type(getcustomasset) == "function") and (type(writefile) == "function")

local function EnsureFolder(path)
    pcall(function()
        if not isfolder(path) then makefolder(path) end
    end)
end

local function HashString(s)
    local h = 0
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 2147483647
    end
    return tostring(h)
end

local function DownloadImage(url)
    if type(url) ~= "string" or not url:match("^https?://") then
        return nil
    end
    if not HAS_CUSTOMASSET then
        warn("[KG_UI] 执行器不支持 getcustomasset，请改用 rbxassetid://")
        return nil
    end

    EnsureFolder(MediaCache)

    local ext = (url:match("%.(%a+)%??[^/]*$") or "png"):lower()
    if not ({ png = 1, jpg = 1, jpeg = 1, webp = 1, gif = 1 })[ext] then
        ext = "png"
    end

    local fileName = HashString(url) .. "." .. ext
    local filePath = MediaCache .. "/" .. fileName

    if isfile(filePath) then
        local ok, asset = pcall(getcustomasset, filePath)
        if ok and asset and asset ~= "" then
            return asset
        end
    end

    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok or not body or #body < 128 then
        warn("[KG_UI] 图片下载失败: " .. url)
        return nil
    end

    local peek = body:sub(1, 15):lower()
    if peek:find("<!doctype") or peek:find("<html") then
        warn("[KG_UI] 下载的不是图片（可能是 GitHub blob 链接，请用 raw 链接）: " .. url)
        return nil
    end

    if not pcall(writefile, filePath, body) then
        warn("[KG_UI] 图片写入失败: " .. filePath)
        return nil
    end

    local assetOk, asset = pcall(getcustomasset, filePath)
    if assetOk and asset and asset ~= "" then
        return asset
    end

    warn("[KG_UI] 图片转资源失败: " .. filePath)
    return nil
end

-- ============================================================
-- ③ 统一解析：名字 / rbxassetid / 数字 / URL
-- ============================================================
local function ResolveIcon(src)
    if src == nil or src == "" then return nil end

    if type(src) == "number" then
        return "rbxassetid://" .. tostring(src)
    end

    if type(src) == "string" then
        -- ① 名字查表
        if Icons[src] then return Icons[src] end
        -- ② URL → 下载
        if src:match("^https?://") then return DownloadImage(src) end
        -- ③ rbxassetid / rbxasset
        if src:match("^rbxassetid://") or src:match("^rbxasset://") then return src end
        -- ④ 纯数字字符串
        if tonumber(src) then return "rbxassetid://" .. src end
        -- ⑤ 未知
        warn("[KG_UI] 无效图标: " .. tostring(src))
        return nil
    end

    return nil
end

-- ============================================================
-- ④ 原来的 KG_UI 代码从这里开始
-- ==========================================================

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local defer = (task and task.defer) or function(fn)
    if type(fn) ~= "function" then return end
    task.spawn(function()
        task.wait()
        local ok, err = pcall(fn)
        if not ok then warn("[defer]", err) end
    end)
end

local DepthOfFieldEffect = Instance.new("DepthOfFieldEffect")
DepthOfFieldEffect.Name = "KGBlurDOF"
DepthOfFieldEffect.Enabled = false

local function safeDisconnect(conn) if conn then pcall(conn.Disconnect, conn) end end

local SectionDragMode = false
local SectionDragListeners = {}

local function SetSectionDragMode(enabled)
    enabled = enabled == true
    if SectionDragMode == enabled then return end
    SectionDragMode = enabled
    for i = #SectionDragListeners, 1, -1 do
        local listener = SectionDragListeners[i]
        if listener then
            pcall(listener, enabled)
        else
            table.remove(SectionDragListeners, i)
        end
    end
end

local Animation = {}
do
    local _RunService = RunService
    local _state = setmetatable({}, {__mode = "k"})
    function Animation.Apply(theme, root, shineEnabled)
        if not root then return end
        local st = _state[root]
        if st and st.conn then safeDisconnect(st.conn) end
        st = {conn = nil}; _state[root] = st
        if not theme or not shineEnabled or not theme.ShineEnabled or not theme.Shine then return end
        local cfg = theme.Shine
        local speed = cfg.Speed or 0.5
        local rotSpeed = cfg.RotationSpeed or 25
        local colorSeq = cfg.ColorSequence
        local doStroke = theme.StrokeShine and theme.StrokeDark and theme.Accent
        st.conn = _RunService.RenderStepped:Connect(function(dt)
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("UIGradient") then
                    local t = (obj:GetAttribute("_t") or 0) + dt * speed
                    obj:SetAttribute("_t", t)
                    obj.Rotation = (t * rotSpeed) % 360
                    obj.Offset = Vector2.new(math.sin(t * 0.6) * 0.18, obj.Offset.Y)
                    if colorSeq then obj.Color = colorSeq end
                elseif doStroke and obj:IsA("UIStroke") then
                    local t = (obj:GetAttribute("_t") or 0) + dt * speed
                    obj:SetAttribute("_t", t)
                    local pulse = (math.sin(t) + 1) / 2
                    obj.Thickness = 1.25 + pulse * 1.25
                    obj.Color = theme.StrokeDark:Lerp(theme.Accent, pulse)
                end
            end
        end)
        return st.conn
    end
end

local Themes = {
    Dark = { Main=Color3.fromRGB(13,13,13), Top=Color3.fromRGB(28,28,30), Text=Color3.fromRGB(240,240,245), Accent=Color3.fromRGB(80,140,255), Stroke=Color3.fromRGB(45,45,48), SubText=Color3.fromRGB(160,160,170), Element=Color3.fromRGB(45,45,50), Hover=Color3.fromRGB(60,60,70), ShineEnabled=true, Shine={Speed=0.4,RotationSpeed=20,ColorSequence=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(40,40,40)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(105,105,105)),ColorSequenceKeypoint.new(1,Color3.fromRGB(40,40,40))})}, StrokeShine=true, StrokeDark=Color3.fromRGB(40,40,40) },
    ["Charcoal"] = { Main=Color3.fromRGB(20,20,20), Top=Color3.fromRGB(35,35,35), Text=Color3.fromRGB(240,240,240), Accent=Color3.fromRGB(102,102,102), Stroke=Color3.fromRGB(45,45,45), SubText=Color3.fromRGB(170,170,170), Element=Color3.fromRGB(35,35,35), Hover=Color3.fromRGB(90,160,255), ShineEnabled=true, Shine={Speed=0.45,RotationSpeed=25,ColorSequence=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(20,20,20)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(150,150,150)),ColorSequenceKeypoint.new(1,Color3.fromRGB(20,20,20))})}, StrokeShine=true, StrokeDark=Color3.fromRGB(60,60,60) },
    ["AMOLED"] = { Main=Color3.fromRGB(0,0,0), Top=Color3.fromRGB(10,10,10), Text=Color3.fromRGB(255,255,255), Accent=Color3.fromRGB(255,255,255), Stroke=Color3.fromRGB(30,30,30), SubText=Color3.fromRGB(150,150,150), Element=Color3.fromRGB(10,10,10), Hover=Color3.fromRGB(22,22,22), ShineEnabled=false, StrokeShine=false, Shine={Speed=0,RotationSpeed=0,ColorSequence=ColorSequence.new(Color3.fromRGB(0,0,0),Color3.fromRGB(0,0,0))}, StrokeDark=Color3.fromRGB(18,18,18) },
}
Themes["红色"] = { Main=Color3.fromRGB(13,13,13), Top=Color3.fromRGB(28,28,30), Text=Color3.fromRGB(240,240,245), Accent=Color3.fromRGB(235,75,85), Stroke=Color3.fromRGB(45,45,48), SubText=Color3.fromRGB(160,160,170), Element=Color3.fromRGB(45,45,50), Hover=Color3.fromRGB(60,60,70), ShineEnabled=true, Shine={Speed=0.4,RotationSpeed=20,ColorSequence=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(40,20,20)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(150,60,65)),ColorSequenceKeypoint.new(1,Color3.fromRGB(40,20,20))})}, StrokeShine=true, StrokeDark=Color3.fromRGB(40,25,25) }
Themes["蓝色"] = { Main=Color3.fromRGB(13,13,13), Top=Color3.fromRGB(28,28,30), Text=Color3.fromRGB(240,240,245), Accent=Color3.fromRGB(80,140,255), Stroke=Color3.fromRGB(45,45,48), SubText=Color3.fromRGB(160,160,170), Element=Color3.fromRGB(45,45,50), Hover=Color3.fromRGB(60,60,70), ShineEnabled=true, Shine={Speed=0.4,RotationSpeed=20,ColorSequence=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(20,25,40)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(60,95,165)),ColorSequenceKeypoint.new(1,Color3.fromRGB(20,25,40))})}, StrokeShine=true, StrokeDark=Color3.fromRGB(25,28,40) }
Themes["绿色"] = { Main=Color3.fromRGB(13,13,13), Top=Color3.fromRGB(28,28,30), Text=Color3.fromRGB(240,240,245), Accent=Color3.fromRGB(85,190,120), Stroke=Color3.fromRGB(45,45,48), SubText=Color3.fromRGB(160,160,170), Element=Color3.fromRGB(45,45,50), Hover=Color3.fromRGB(60,60,70), ShineEnabled=true, Shine={Speed=0.4,RotationSpeed=20,ColorSequence=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(20,40,25)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(65,140,90)),ColorSequenceKeypoint.new(1,Color3.fromRGB(20,40,25))})}, StrokeShine=true, StrokeDark=Color3.fromRGB(25,40,28) }
local CurrentTheme = Themes.Dark

local Registry = {}
local ConfigObjects = {}
local ThemeListeners = {}
local function clamp(v, min, max) return math.max(min, math.min(max, v)) end
local function AddToRegistry(obj, prop, key)
    local val = CurrentTheme[key] or Themes.Dark[key] or Color3.new(1,1,1)
    table.insert(Registry, {Object = obj, Property = prop, Type = key})
    obj[prop] = val
end
local function Tween(obj, props, time)
    TweenService:Create(obj, TweenInfo.new(time or 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local function SerializeValue(v)
    if typeof(v) == "Color3" then
        return { __t = "Color3", hex = v:ToHex() }
    elseif type(v) == "table" then
        local o = {}
        for k, val in pairs(v) do o[k] = SerializeValue(val) end
        return o
    end
    return v
end

local function DeserializeValue(v)
    if type(v) == "table" then
        if v.__t == "Color3" and type(v.hex) == "string" then
            local ok, c = pcall(Color3.fromHex, v.hex)
            return ok and c or Color3.new(1, 1, 1)
        end
        local o = {}
        for k, val in pairs(v) do o[k] = DeserializeValue(val) end
        return o
    end
    return v
end

local ConfigIdCounter = 0
local function NewConfigId(prefix, name)
    ConfigIdCounter = ConfigIdCounter + 1
    return tostring(prefix) .. "::" .. tostring(name or "") .. "::" .. tostring(ConfigIdCounter)
end

local TextGradient = {
    Enabled = true, Time = 0, Accumulator = 0,
    Labels = {}, Objects = {}, Hooks = {}, Skipped = {},
}

function TextGradient:Skip(Label)
    if not Label then return end
    table.insert(TextGradient.Skipped, Label)
    local g = Label:FindFirstChild("KGTextGrad")
    if g then g:Destroy() end
    for i = #TextGradient.Labels, 1, -1 do
        if TextGradient.Labels[i] == Label then table.remove(TextGradient.Labels, i) end
    end
end

function TextGradient:IsSkipped(Label)
    return table.find(TextGradient.Skipped, Label) ~= nil
end

function TextGradient:_Apply(Label)
    if not Label or not Label.Parent then return end
    if TextGradient:IsSkipped(Label) then return end
    local Gradient = Label:FindFirstChild("KGTextGrad")
    if not TextGradient.Enabled then
        if Gradient then Gradient:Destroy() end
        return
    end
    if not Gradient then
        Gradient = Instance.new("UIGradient")
        Gradient.Name = "KGTextGrad"
        Gradient.Parent = Label
    end
    local Accent = CurrentTheme.Accent or Color3.fromRGB(80, 140, 255)
    local SweepX = ((TextGradient.Time * 0.9) % 2) - 1
    Gradient.Rotation = 0
    Gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Accent:Lerp(Color3.new(1, 1, 1), 0.2)),
        ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Accent:Lerp(Color3.new(1, 1, 1), 0.35)),
    })
    Gradient.Offset = Vector2.new(SweepX, 0)
    if not table.find(TextGradient.Objects, Gradient) then
        table.insert(TextGradient.Objects, Gradient)
    end
    return Gradient
end

function TextGradient:Add(Label)
    if not Label then return Label end
    if TextGradient:IsSkipped(Label) then return Label end
    if not table.find(TextGradient.Labels, Label) then
        table.insert(TextGradient.Labels, Label)
    end
    TextGradient:_Apply(Label)
    return Label
end

function TextGradient:RefreshAll()
    table.clear(TextGradient.Objects)
    for Index = #TextGradient.Labels, 1, -1 do
        local Label = TextGradient.Labels[Index]
        if Label and Label.Parent then
            TextGradient:_Apply(Label)
        else
            table.remove(TextGradient.Labels, Index)
        end
    end
end

function TextGradient:SetEnabled(Enabled)
    TextGradient.Enabled = Enabled == true
    if not TextGradient.Enabled then TextGradient.Accumulator = 0 end
    TextGradient:RefreshAll()
end

function TextGradient:Animate(dt)
    if not TextGradient.Enabled then return end
    TextGradient.Accumulator = TextGradient.Accumulator + (dt or 0)
    if TextGradient.Accumulator < (1 / 30) then return end
    local ResolvedDt = TextGradient.Accumulator
    TextGradient.Accumulator = 0
    TextGradient.Time = TextGradient.Time + ResolvedDt
    local SweepX = ((TextGradient.Time * 0.9) % 2) - 1
    local Offset = Vector2.new(SweepX, 0)
    for Index = #TextGradient.Objects, 1, -1 do
        local Gradient = TextGradient.Objects[Index]
        if Gradient and Gradient.Parent then
            Gradient.Rotation = 0
            Gradient.Offset = Offset
        else
            table.remove(TextGradient.Objects, Index)
        end
    end
end

function TextGradient:AttachHook(root)
    if not root then return end
    local conn = root.DescendantAdded:Connect(function(Object)
        if Object:IsA("TextLabel") or Object:IsA("TextBox") or Object:IsA("TextButton") then
            defer(function()
                if Object.Parent then TextGradient:Add(Object) end
            end)
        end
    end)
    table.insert(TextGradient.Hooks, conn)
    task.spawn(function()
        for _, Object in ipairs(root:GetDescendants()) do
            if Object:IsA("TextLabel") or Object:IsA("TextBox") or Object:IsA("TextButton") then
                TextGradient:Add(Object)
            end
        end
    end)
end

RunService.RenderStepped:Connect(function(dt) TextGradient:Animate(dt) end)

local KG_UI = {}
KG_UI.TextGradient = TextGradient

local BaseAccents = {}
for _tn, _tt in pairs(Themes) do BaseAccents[_tn] = _tt.Accent end
local CustomAccent = nil
local CurrentThemeName = "Dark"

function KG_UI:SetTheme(name)
    if Themes[name] then
        CurrentThemeName = name
        CurrentTheme = Themes[name]
        if CustomAccent then CurrentTheme.Accent = CustomAccent end
        for _, r in pairs(Registry) do if r.Object then Tween(r.Object, {[r.Property] = CurrentTheme[r.Type]}) end end
        for _, fn in pairs(ThemeListeners) do pcall(fn) end
        TextGradient:RefreshAll()
    end
end

function KG_UI:SetAccent(color3)
    if color3 == nil then
        CustomAccent = nil
        local base = BaseAccents[CurrentThemeName] or Color3.fromRGB(80, 140, 255)
        CurrentTheme.Accent = base
    else
        if typeof(color3) ~= "Color3" then return end
        CustomAccent = color3
        CurrentTheme.Accent = color3
    end
    for _, r in pairs(Registry) do
        if r.Object and r.Type == "Accent" then
            Tween(r.Object, {[r.Property] = CurrentTheme.Accent})
        end
    end
    for _, fn in pairs(ThemeListeners) do pcall(fn) end
    TextGradient:RefreshAll()
end

-- ============================================================
-- 配置保存 / 加载（KG_UI 原来没有，这里补上）
-- ============================================================
local CONFIG_DIR = "KG_UI_Configs"

function KG_UI:SaveConfig(name, folder)
    name   = tostring(name or "config")
    folder = tostring(folder or CONFIG_DIR)
    local ok, err = pcall(function()
        if not isfolder(folder) then makefolder(folder) end
        local data = {}
        for id, obj in pairs(ConfigObjects) do
            if obj then
                local v
                if type(obj.Get) == "function" then
                    local ok2, got = pcall(obj.Get)
                    if ok2 then v = got end
                else
                    v = obj.Value
                end
                if v ~= nil then
                    data[id] = SerializeValue(v)
                end
            end
        end
        local encoded = HttpService:JSONEncode(data)
        writefile(folder .. "/" .. name .. ".json", encoded)
    end)
    if not ok then warn("[KG_UI] SaveConfig error:", err) end
    return ok
end

function KG_UI:LoadConfig(path)
    if type(path) ~= "string" then return false end
    if not pcall(isfile, path) then return false end
    if not isfile(path) then return false end

    local ok, raw = pcall(readfile, path)
    if not ok or not raw then return false end

    local ok2, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not ok2 or type(decoded) ~= "table" then return false end

    for id, rawVal in pairs(decoded) do
        local obj = ConfigObjects[id]
        if obj and type(obj.Set) == "function" then
            local value = DeserializeValue(rawVal)
            pcall(function() obj.Set(value) end)
        end
    end
    return true
end

local MediaManager = {Folder = "KGMediaCache"}
function MediaManager:SetFolder(f) self.Folder = f end
function MediaManager:_init(sub)
    pcall(function()
        if not isfolder(self.Folder) then makefolder(self.Folder) end
        local p = self.Folder.."/"..sub
        if not isfolder(p) then makefolder(p) end
    end)
end
function MediaManager:_rname(ext)
    local s = "abcdefghijklmnopqrstuvwxyz0123456789"
    local n = ""
    for _=1,12 do local i=math.random(1,#s) n=n..s:sub(i,i) end
    return n.."."..ext
end
function MediaManager:Audio(src, noDownload)
    if type(src) ~= "string" or src == "" then return "" end
    if src:match("^rbxassetid://") or src:match("^rbxasset://") then return src end
    if src:match("^%d+$") then return "rbxassetid://"..src end
    if not src:match("^https?://") then return "" end
    local ext = (src:match("%.(%a+)%??[^/]*$") or "mp3"):lower()
    if not ({mp3=1,ogg=1,wav=1,flac=1})[ext] then ext = "mp3" end
    self:_init("audio")
    local dir = self.Folder.."/audio"
    local mapPath = dir.."/_map.json"
    local hs = HttpService
    local map = {}
    pcall(function() if isfile(mapPath) then local ok,d = pcall(hs.JSONDecode, hs, readfile(mapPath)); if ok and type(d) == "table" then map = d end end end)
    local key = tostring(#src).."_"..src:sub(1,40):gsub("[^%w]","")
    if map[key] then
        local cp = dir.."/"..map[key]
        if isfile(cp) then local ok,a = pcall(getcustomasset, cp); if ok and a and a ~= "" then return a end end
        map[key] = nil
    end
    if noDownload then return nil end
    local fname = self:_rname(ext)
    local path = dir.."/"..fname
    local body = nil
    local reqOk = pcall(function()
        local req = (syn and syn.request) or http_request or request
        local r = req({Url=src, Method="GET", Headers={["User-Agent"]="Roblox/WinInet"}})
        if r and r.Body and #r.Body > 128 then
            local peek = r.Body:sub(1,15):lower()
            if peek:find("<!doctype") or peek:find("<html") then return end
            body = r.Body; writefile(path, body)
        end
    end)
    if reqOk and body and isfile(path) then
        local ok2,a = pcall(getcustomasset, path)
        if ok2 and a and a ~= "" then
            map[key] = fname
            pcall(function() local ok3,enc = pcall(hs.JSONEncode, hs, map); if ok3 then writefile(mapPath, enc) end end)
            return a
        end
    end
    return ""
end
function MediaManager:Video(src)
    if type(src) ~= "string" or src == "" then return "" end
    if src:match("^rbxassetid://") or src:match("^rbxasset://") then return src end
    if src:match("^%d+$") then return "rbxassetid://"..src end
    if not src:match("^https?://") then return "" end
    local ext = (src:match("%.(%a+)%??[^/]*$") or "webm"):lower()
    if not ({webm=1,mp4=1,ogg=1,mov=1})[ext] then ext = "webm" end
    if ext == "mp4" or ext == "mov" then ext = "webm" end
    self:_init("videos")
    local dir = self.Folder.."/videos"
    local mapPath = dir.."/_map.json"
    local hs = HttpService
    local map = {}
    pcall(function() if isfile(mapPath) then local ok,d = pcall(hs.JSONDecode, hs, readfile(mapPath)); if ok and type(d) == "table" then map = d end end end)
    local key = tostring(#src).."_"..src:sub(1,40):gsub("[^%w]","")
    if map[key] then
        local cp = dir.."/"..map[key]
        if isfile(cp) then local ok,a = pcall(getcustomasset, cp); if ok and a and a ~= "" then return a end end
        map[key] = nil
    end
    local fname = self:_rname(ext)
    local path = dir.."/"..fname
    local body = nil
    local reqOk = pcall(function()
        local req = (syn and syn.request) or http_request or request
        local r = req({Url=src, Method="GET", Headers={["User-Agent"]="Roblox/WinInet"}})
        if r and r.Body and #r.Body > 512 then
            local peek = r.Body:sub(1,15):lower()
            if peek:find("<!doctype") or peek:find("<html") then return end
            body = r.Body; writefile(path, body)
        end
    end)
    if reqOk and body and isfile(path) then
        local ok2,a = pcall(getcustomasset, path)
        if ok2 and a and a ~= "" then
            map[key] = fname
            pcall(function() local ok3,enc = pcall(hs.JSONEncode, hs, map); if ok3 then writefile(mapPath, enc) end end)
            return a
        end
    end
    return ""
end
function MediaManager:Image(src)
    if type(src) ~= "string" or src == "" then return "" end
    if src:match("^rbxassetid://") or src:match("^rbxasset://") then return src end
    if src:match("^%d+$") then return "rbxassetid://"..src end
    if not src:match("^https?://") then return "" end
    local ext = (src:match("%.(%a+)%??[^/]*$") or "png"):lower()
    if not ({png=1,jpg=1,jpeg=1,webp=1,gif=1})[ext] then ext = "png" end
    self:_init("images")
    local dir = self.Folder.."/images"
    local mapPath = dir.."/_map.json"
    local hs = HttpService
    local map = {}
    pcall(function() if isfile(mapPath) then local ok,d = pcall(hs.JSONDecode, hs, readfile(mapPath)); if ok and type(d) == "table" then map = d end end end)
    local key = tostring(#src).."_"..src:sub(1,40):gsub("[^%w]","")
    if map[key] then
        local cp = dir.."/"..map[key]
        if isfile(cp) then local ok,a = pcall(getcustomasset, cp); if ok and a and a ~= "" then return a end end
        map[key] = nil
    end
    local fname = self:_rname(ext)
    local path = dir.."/"..fname
    local body = nil
    local reqOk = pcall(function()
        local req = (syn and syn.request) or http_request or request
        local r = req({Url=src, Method="GET", Headers={["User-Agent"]="Roblox/WinInet"}})
        if r and r.Body and #r.Body > 128 then
            local peek = r.Body:sub(1,15):lower()
            if peek:find("<!doctype") or peek:find("<html") then return end
            body = r.Body; writefile(path, body)
        end
    end)
    if reqOk and body and isfile(path) then
        local ok2,a = pcall(getcustomasset, path)
        if ok2 and a and a ~= "" then
            map[key] = fname
            pcall(function() local ok3,enc = pcall(hs.JSONEncode, hs, map); if ok3 then writefile(mapPath, enc) end end)
            return a
        end
    end
    return ""
end

local function createLockOverlay(parent, defaultTitle)
    local cornerRadius = UDim.new(0, 8)
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("UICorner") then cornerRadius = child.CornerRadius; break end
    end
    local lockFrame = Instance.new("TextButton")
    lockFrame.Size = UDim2.new(1, 0, 1, 0)
    lockFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    lockFrame.BackgroundTransparency = 0.6
    lockFrame.Text = ""; lockFrame.AutoButtonColor = false
    lockFrame.Active = true; lockFrame.Visible = false; lockFrame.ZIndex = 10
    lockFrame.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = cornerRadius; corner.Parent = lockFrame
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1; container.Parent = lockFrame
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 8); layout.Parent = container
    local lockIcon = Instance.new("ImageLabel")
    lockIcon.Size = UDim2.new(0, 18, 0, 18)
    lockIcon.BackgroundTransparency = 1
    lockIcon.Image = "rbxassetid://12060512624"
    lockIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    lockIcon.ImageTransparency = 0.1; lockIcon.Parent = container
    local lockLabel = Instance.new("TextLabel")
    lockLabel.Size = UDim2.new(0, 0, 0, 20)
    lockLabel.BackgroundTransparency = 1
    lockLabel.Font = Enum.Font.GothamBold
    lockLabel.Text = defaultTitle or "已锁定"
    lockLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    lockLabel.TextTransparency = 0.2; lockLabel.TextSize = 14
    lockLabel.AutomaticSize = Enum.AutomaticSize.X
    lockLabel.Parent = container
    TextGradient:Skip(lockLabel)
    return lockFrame, lockLabel
end

local function formatIconAsset(asset, default)
    if asset == nil or asset == "" then return default end
    if type(asset) == "number" then
        return "rbxassetid://" .. tostring(asset)
    elseif type(asset) == "string" then
        if tonumber(asset) then
            return "rbxassetid://" .. asset
        elseif asset:match("^rbxassetid://") or asset:match("^rbxasset://") or asset:match("^http") then
            return asset
        else
            return "rbxassetid://" .. asset
        end
    end
    return default
end

local CHESSBOARD_IMAGE = "http://www.roblox.com/asset/?id=14204231522"

local function createSectionBuilder(parent, contentContainer, elementWidth, windowCount, window)
    local win = window
    local padding = parent:FindFirstChild("SectionPadding")
    if not padding then
        padding = Instance.new("UIPadding")
        padding.Name = "SectionPadding"
        padding.PaddingLeft = UDim.new(0.04, 0); padding.Parent = parent
    end
    local child = {}

    local function miRow(parentFrame, height)
        height = height or 42
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, height)
        row.BackgroundTransparency = 1; row.BorderSizePixel = 0
        row.ClipsDescendants = false; row.Parent = parentFrame
        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, -20, 0, 1)
        line.Position = UDim2.new(0, 10, 1, -1)
        line.BackgroundColor3 = CurrentTheme.Stroke
        line.BackgroundTransparency = 0.65; line.BorderSizePixel = 0
        line.Parent = row
        AddToRegistry(line, "BackgroundColor3", "Stroke")
        return row
    end

    local function miIcon(parentFrame, asset, size, x, y)
        size = size or 18
        local icon = Instance.new("ImageLabel")
        icon.Size = UDim2.new(0, size, 0, size)
        icon.Position = UDim2.new(0, x or 15, 0, y or 12)
        icon.BackgroundTransparency = 1; icon.BorderSizePixel = 0
        icon.ImageColor3 = CurrentTheme.Text
        icon.ImageTransparency = 0.25
        icon.ScaleType = Enum.ScaleType.Fit
        if type(asset) == "number" then icon.Image = "rbxassetid://"..tostring(asset)
        elseif type(asset) == "string" and asset ~= "" then
            if tonumber(asset) then icon.Image = "rbxassetid://"..asset
            elseif asset:match("^rbxassetid://") or asset:match("^http") or asset:match("^rbxasset://") then icon.Image = asset
            else icon.Image = "rbxassetid://"..asset end
        end
        icon.Parent = parentFrame
        AddToRegistry(icon, "ImageColor3", "Text")
        return icon
    end

    local function miLabel(parentFrame, text, x, y, w, size)
        local lbl = Instance.new("TextLabel")
        lbl.Text = text or ""
        lbl.Position = UDim2.new(0, x or 15, 0, y or 12)
        lbl.Size = w or UDim2.new(1, -30, 0, 18)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = size or 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Parent = parentFrame
        AddToRegistry(lbl, "TextColor3", "Text")
        return lbl
    end

    local function miDesc(parentFrame, text, x, y, w)
        local lbl = Instance.new("TextLabel")
        lbl.Text = tostring(text or "")
        lbl.Position = UDim2.new(0, x or 15, 0, y or 27)
        lbl.Size = w or UDim2.new(1, -30, 0, 13)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.TextTransparency = 0.35
        lbl.Parent = parentFrame
        AddToRegistry(lbl, "TextColor3", "SubText")
        TextGradient:Skip(lbl)
        return lbl
    end

    local function safeConfig(config)
        if type(config) ~= "table" then
            return { Name = tostring(config or "") }
        end
        return config
    end

child.Button = function(_, config)
    config = safeConfig(config)
    local btnText = config.Name or config.Text or ""
    local callback = config.Callback or function() end
    local parent = config.Parent or contentHolder
    local descText = config.Desc or config.Description
    local rowH = descText and 56 or 42
    local Tile = miRow(parent, rowH)
    local TitleLbl = miLabel(Tile, btnText, 15, descText and 8 or 12, UDim2.new(1, -30, 0, 18), 13)
    if descText then miDesc(Tile, descText, 15, 27, UDim2.new(1, -30, 0, 13)) end
    local locked = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local lockFrame, lockLabel = createLockOverlay(Tile, lockedTitle)
    lockFrame.Visible = locked
    local ClickBtn = Instance.new("TextButton")
    ClickBtn.Size = UDim2.new(1, 0, 1, 0)
    ClickBtn.BackgroundTransparency = 1; ClickBtn.Text = ""
    ClickBtn.AutoButtonColor = false; ClickBtn.Parent = Tile
    ClickBtn.Active = not locked
    local function updateLock(state) locked = state; lockFrame.Visible = state; ClickBtn.Active = not state end
    ClickBtn.MouseEnter:Connect(function() if not locked then Tween(Tile, {BackgroundTransparency = 0.65}, 0.15) end end)
    ClickBtn.MouseLeave:Connect(function() if not locked then Tween(Tile, {BackgroundTransparency = 1}, 0.15) end end)
    ClickBtn.MouseButton1Down:Connect(function() if not locked then Tween(Tile, {BackgroundTransparency = 0.45}, 0.08) end end)
    ClickBtn.MouseButton1Up:Connect(function() if not locked then Tween(Tile, {BackgroundTransparency = 0.65}, 0.08) end end)
    ClickBtn.MouseButton1Click:Connect(function() if not locked then callback() end end)
local self = {}
function self:UpdateText(t) TitleLbl.Text = tostring(t or "") end
function self:SetVisible(v) Tile.Visible = v ~= false end
function self:Lock(title) 
    updateLock(true)
    if title then 
        lockLabel.Text = tostring(title) 
        lockedTitle = title 
    end
end
function self:Unlock() updateLock(false) end
function self:IsLocked() return locked end
return self

child.Toggle = function(_, config)
    config = safeConfig(config)
    local toggleText = config.Name or ""
    local Enabled    = (config.Value ~= nil) and (config.Value == true)
                       or (config.Default == true)
    local callback   = config.Callback or function() end
    local style      = tostring(config.Style or "Slider"):lower()
    local useCheck   = (style == "check" or style == "checkbox" or style == "checkmark")
    local controlId  = NewConfigId("Toggle", toggleText)
    local parent     = config.Parent or contentHolder
    local tgDesc     = config.Desc or config.Description
    local Tile       = miRow(parent, tgDesc and 56 or 42)
    local TitleLbl   = miLabel(Tile, toggleText, 15, tgDesc and 8 or 12, UDim2.new(1, -75, 0, 18), 13)
    if tgDesc then miDesc(Tile, tgDesc, 15, 27, UDim2.new(1, -75, 0, 13)) end

    -- ===== 锁定 =====
    local locked      = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local lockFrame, lockLabel = createLockOverlay(Tile, lockedTitle)
    lockFrame.Visible = locked

    local ClickBtn = Instance.new("TextButton")
    ClickBtn.Size = UDim2.new(1, 0, 1, 0)
    ClickBtn.BackgroundTransparency = 1
    ClickBtn.Text = ""
    ClickBtn.AutoButtonColor = false
    ClickBtn.Parent = Tile
    ClickBtn.Active = not locked

    local function updateLock(state)
        locked = state
        lockFrame.Visible = state
        ClickBtn.Active = not state
    end

    -- ===== 视觉元素声明 =====
    local Switch, SwStroke, Dot          -- 滑块
    local Box, BoxStroke, Check          -- 对勾
    local ApplyUI                        -- 前向声明

    if useCheck then
        -- ---------- 对勾样式 ----------
        Box = Instance.new("Frame")
        Box.Size = UDim2.fromOffset(20, 20)
        Box.AnchorPoint = Vector2.new(1, 0.5)
        Box.Position = UDim2.new(1, -12, 0.5, 0)
        Box.BackgroundColor3 = Enabled and CurrentTheme.Accent or Color3.fromRGB(26, 28, 36)
        Box.BorderSizePixel = 0
        Box.Parent = Tile
        Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 5)

        BoxStroke = Instance.new("UIStroke")
        BoxStroke.Thickness = 1.4
        BoxStroke.Transparency = Enabled and 1 or 0.4
        BoxStroke.Color = Enabled and CurrentTheme.Accent or CurrentTheme.Stroke
        BoxStroke.Parent = Box
        table.insert(ThemeListeners, function()
            if not Enabled then BoxStroke.Color = CurrentTheme.Stroke end
        end)

        Check = Instance.new("ImageLabel")
        Check.Size = UDim2.fromOffset(14, 14)
        Check.AnchorPoint = Vector2.new(0.5, 0.5)
        Check.Position = UDim2.new(0.5, 0, 0.5, 0)
        Check.BackgroundTransparency = 1
        Check.Image = "rbxassetid://10709790644"
        Check.ImageColor3 = Color3.new(1, 1, 1)
        Check.ImageTransparency = Enabled and 0 or 1
        Check.Parent = Box

        ApplyUI = function(v)
            Enabled = v
            if v then
                Tween(Box, {BackgroundColor3 = CurrentTheme.Accent}, 0.18)
                Tween(BoxStroke, {Color = CurrentTheme.Accent, Transparency = 1}, 0.18)
                Tween(Check, {ImageTransparency = 0}, 0.18)
            else
                Tween(Box, {BackgroundColor3 = Color3.fromRGB(26, 28, 36)}, 0.18)
                Tween(BoxStroke, {Color = CurrentTheme.Stroke, Transparency = 0.4}, 0.18)
                Tween(Check, {ImageTransparency = 1}, 0.18)
            end
        end
    else
        -- ---------- 滑块样式 ----------
        Switch = Instance.new("Frame")
        Switch.Size = UDim2.new(0, 30, 0, 18)
        Switch.Position = UDim2.new(1, -41, 0.5, -9)
        Switch.BackgroundColor3 = Enabled and CurrentTheme.Accent or Color3.fromRGB(10, 13, 21)
        Switch.BorderSizePixel = 0
        Switch.Parent = Tile
        Instance.new("UICorner", Switch).CornerRadius = UDim.new(1, 0)

        SwStroke = Instance.new("UIStroke")
        SwStroke.Thickness = 1
        SwStroke.Transparency = Enabled and 1 or 0.65
        SwStroke.Color = CurrentTheme.Stroke
        SwStroke.Parent = Switch
        table.insert(ThemeListeners, function()
            SwStroke.Color = CurrentTheme.Stroke
            if not Enabled then SwStroke.Transparency = 0.65 end
        end)

        Dot = Instance.new("Frame")
        Dot.Size = UDim2.new(0, 16, 0, 16)
        Dot.Position = Enabled and UDim2.new(1, -17, 0.5, -8) or UDim2.new(0, 1, 0.5, -8)
        Dot.BackgroundColor3 = Color3.new(1, 1, 1)
        Dot.BorderSizePixel = 0
        Dot.Parent = Switch
        Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)

        ApplyUI = function(v)
            Enabled = v
            if v then
                Tween(Switch, {BackgroundColor3 = CurrentTheme.Accent}, 0.18)
                Tween(SwStroke, {Transparency = 1}, 0.18)
                Tween(Dot, {Position = UDim2.new(1, -17, 0.5, -8)}, 0.18)
            else
                Tween(Switch, {BackgroundColor3 = Color3.fromRGB(10, 13, 21)}, 0.18)
                Tween(SwStroke, {Transparency = 0.65}, 0.18)
                Tween(Dot, {Position = UDim2.new(0, 1, 0.5, -8)}, 0.18)
            end
        end
    end

    -- ===== 配置注册 =====
    ConfigObjects[controlId] = {
        Type = "Toggle",
        Value = Enabled,
        Get = function() return Enabled end,
        Set = function(v)
            if locked then return end
            v = v == true
            ApplyUI(v)
            ConfigObjects[controlId].Value = v
            callback(v)
        end,
    }

    -- ===== 交互 =====
    ClickBtn.MouseEnter:Connect(function()
        if not locked then Tween(Tile, {BackgroundTransparency = 0.65}, 0.15) end
    end)
    ClickBtn.MouseLeave:Connect(function()
        if not locked then Tween(Tile, {BackgroundTransparency = 1}, 0.15) end
    end)
    ClickBtn.MouseButton1Click:Connect(function()
        if locked then return end
        ApplyUI(not Enabled)
        ConfigObjects[controlId].Value = Enabled
        callback(Enabled)
    end)

    local self = {}
    function self.GetValue() return Enabled end
    function self.SetValue(v) if not locked then ConfigObjects[controlId].Set(v) end end
    function self.Lock(title) updateLock(true); if title then lockLabel.Text = title; lockedTitle = title end end
    function self.Unlock() updateLock(false) end
    function self.IsLocked() return locked end
    function self.SetVisible(v)
        v = v ~= false
        Tile.Visible = v
        Tile.Size = v and UDim2.new(1, 0, 0, tgDesc and 56 or 42) or UDim2.new(1, 0, 0, 0)
    end
    return self
end

child.Slider = function(_, config)
    config = safeConfig(config)
    local sliderText = config.Name or ""
    local valueTable = config.Value or {}
    local min = valueTable.Min
    local max = valueTable.Max
    local default = valueTable.Default
    local callback = config.Callback or function() end
    local unlimited = (min == nil and max == nil)
    min = tonumber(min); max = tonumber(max)
    local Rounding = config.Rounding or 0
    local Val = tonumber(default) or (min or 0)
    local controlId = NewConfigId("Slider", sliderText)
    local parent = config.Parent or contentHolder
    local slDesc = config.Desc or config.Description
    local Tile = miRow(parent, slDesc and 56 or 42)
    local rowH = 22
    local TitleLbl = miLabel(Tile, sliderText, 15, 0, UDim2.new(0, 90, 0, rowH), 13)
    TitleLbl.Position = slDesc and UDim2.new(0, 15, 0, 8) or UDim2.new(0, 15, 0.5, -rowH/2)
    if slDesc then miDesc(Tile, slDesc, 15, 27, UDim2.new(1, -160, 0, 13)) end
    local numW = unlimited and 72 or 52
    local ValueFrame = Instance.new("Frame")
    ValueFrame.Size = UDim2.new(0, numW, 0, rowH)
    ValueFrame.Position = UDim2.new(1, -(numW + 10), 0.5, -rowH/2)
    ValueFrame.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
    ValueFrame.BackgroundTransparency = 0; ValueFrame.BorderSizePixel = 0
    ValueFrame.ClipsDescendants = true; ValueFrame.Parent = Tile
    Instance.new("UICorner", ValueFrame).CornerRadius = UDim.new(0, 4)
    local ValueStroke = Instance.new("UIStroke")
    ValueStroke.Thickness = 1; ValueStroke.Transparency = 0.65
    ValueStroke.Color = CurrentTheme.Stroke; ValueStroke.Parent = ValueFrame
    table.insert(ThemeListeners, function() ValueStroke.Color = CurrentTheme.Stroke end)
    local ValueLabel = Instance.new("TextBox")
    ValueLabel.Text = tostring(Val)
    ValueLabel.Size = UDim2.new(1, 0, 1, 0)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.TextSize = 12
    ValueLabel.TextColor3 = CurrentTheme.Text
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Center
    ValueLabel.TextYAlignment = Enum.TextYAlignment.Center
    ValueLabel.ClearTextOnFocus = false
    ValueLabel.Parent = ValueFrame
    AddToRegistry(ValueLabel, "TextColor3", "Text")
    TextGradient:Skip(ValueLabel)
    ValueLabel.Focused:Connect(function() Tween(ValueStroke, {Transparency = 0.2}, 0.15) end)
    local trackLeft = 15 + 90 + 12
    local trackRight = numW + 10 + 10
    local Track, Fill, Knob, Bar
    if not unlimited then
        Track = Instance.new("Frame")
        Track.Size = UDim2.new(1, -(trackLeft + trackRight), 0, 6)
        Track.Position = UDim2.new(0, trackLeft, 0.5, -3)
        Track.BackgroundColor3 = CurrentTheme.Stroke
        Track.BorderSizePixel = 0; Track.Parent = Tile
        Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)
        AddToRegistry(Track, "BackgroundColor3", "Stroke")
        local initP = (min and max and max ~= min) and ((Val - min) / (max - min)) or 0
        Fill = Instance.new("Frame")
        Fill.Size = UDim2.new(initP, 0, 1, 0)
        Fill.BackgroundColor3 = CurrentTheme.Accent
        Fill.BorderSizePixel = 0; Fill.Parent = Track
        Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)
        AddToRegistry(Fill, "BackgroundColor3", "Accent")
        Knob = Instance.new("Frame")
        Knob.Size = UDim2.new(0, 12, 0, 12)
        Knob.AnchorPoint = Vector2.new(0.5, 0.5)
        Knob.Position = UDim2.new(initP, 0, 0.5, 0)
        Knob.BackgroundColor3 = Color3.new(1, 1, 1)
        Knob.BorderSizePixel = 0; Knob.ZIndex = 3; Knob.Parent = Track
        Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)
        Bar = Instance.new("TextButton")
        Bar.Size = UDim2.new(1, 0, 0, 20)
        Bar.Position = UDim2.new(0, 0, 0.5, -10)
        Bar.BackgroundTransparency = 1; Bar.Text = ""
        Bar.ZIndex = 4; Bar.Parent = Track
    end
    local dragging = false
    local function Round(n, decimals)
        local factor = 10^decimals
        return math.floor(n * factor + 0.5) / factor
    end
    local function UpdateSlider(val)
        if unlimited then
            Val = tonumber(val) or Val
            ValueLabel.Text = tostring(Val)
            if ConfigObjects[controlId] then ConfigObjects[controlId].Value = Val end
            callback(Val)
            return
        end
        val = math.clamp(val, min, max)
        val = Round(val, Rounding)
        local ratio = (val - min) / (max - min)
        TweenService:Create(Fill, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
        TweenService:Create(Knob, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {Position = UDim2.new(ratio, 0, 0.5, 0)}):Play()
        ValueLabel.Text = tostring(val)
        Val = val
        if ConfigObjects[controlId] then ConfigObjects[controlId].Value = val end
        callback(val)
        return val
    end
    local function GetValueFromInput(input)
        if unlimited or not Track then return Val end
        local absX = Track.AbsolutePosition.X
        local absW = Track.AbsoluteSize.X
        local ratio = math.clamp((input.Position.X - absX) / absW, 0, 1)
        return ratio * (max - min) + min
    end
    if Bar then
        Bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                UpdateSlider(GetValueFromInput(input))
            end
        end)
        Bar.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                UpdateSlider(GetValueFromInput(input))
            end
        end)
    end
    ValueLabel.FocusLost:Connect(function()
        Tween(ValueStroke, {Transparency = 0.65}, 0.15)
        local typed = tonumber(ValueLabel.Text)
        if typed then UpdateSlider(typed) else ValueLabel.Text = tostring(Val) end
    end)
    local locked = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local lockFrame, lockLabel = createLockOverlay(Tile, lockedTitle)
    lockFrame.Visible = locked
    if Bar then Bar.Active = not locked end
    ValueLabel.Active = not locked
    local function updateLock(state)
        locked = state
        lockFrame.Visible = state
        if Bar then Bar.Active = not state end
        ValueLabel.Active = not state
    end
    ConfigObjects[controlId] = {
        Type = "Slider",
        Value = Val,
        Get = function() return Val end,
        Set = function(v)
            if locked then return end
            local n = tonumber(v)
            if n then UpdateSlider(n) end
        end,
    }
    table.insert(ThemeListeners, function()
        if Fill then Fill.BackgroundColor3 = CurrentTheme.Accent end
        if Track then Track.BackgroundColor3 = CurrentTheme.Stroke end
        ValueLabel.TextColor3 = CurrentTheme.Text
    end)
    UpdateSlider(Val)
    local self = {}
    function self.GetValue() return Val end
    function self.SetValue(v) if not locked then ConfigObjects[controlId].Set(v) end end
    function self.Lock(title) updateLock(true); if title then lockLabel.Text = title; lockedTitle = title end end
    function self.Unlock() updateLock(false) end
    function self.IsLocked() return locked end
    function self.SetVisible(v) Tile.Visible = v end
    return self
end

child.Dropdown = function(_, config)
    config = safeConfig(config)
    local dropText = config.Name or ""
    local options = config.Values or {}
    local selectedValue = config.Value
    local multi = config.Multi == true
    local callback = config.Callback or function() end
    local controlId = NewConfigId("Dropdown", dropText)
    local parent = config.Parent or contentHolder
    local selected = multi and {} or nil
    local function initSelected()
        if multi then
            if type(selectedValue) == "table" then
                selected = {}
                for _, v in ipairs(selectedValue) do if table.find(options, v) then table.insert(selected, v) end end
            else selected = {} end
        else
            if selectedValue and table.find(options, selectedValue) then selected = selectedValue else selected = options[1] or "" end
        end
    end
    initSelected()
    local Dropped = false
    local ddDesc = config.Desc or config.Description
    local Btn = miRow(parent, ddDesc and 56 or 42)
    local Lbl = miLabel(Btn, "", 15, ddDesc and 8 or 12, UDim2.new(1, -50, 0, 18), 13)
    if ddDesc then miDesc(Btn, ddDesc, 15, 27, UDim2.new(1, -50, 0, 13)) end
    local Icon = Instance.new("ImageLabel")
    Icon.Image = "rbxassetid://18865373378"
    Icon.Size = UDim2.new(0, 20, 0, 20)
    Icon.Position = UDim2.new(1, -30, 0.5, -10)
    Icon.BackgroundTransparency = 1; Icon.Parent = Btn
    AddToRegistry(Icon, "ImageColor3", "Accent")
    local ClickBtn = Instance.new("TextButton")
    ClickBtn.Size = UDim2.new(1, 0, 1, 0)
    ClickBtn.BackgroundTransparency = 1; ClickBtn.Text = ""
    ClickBtn.AutoButtonColor = false; ClickBtn.Parent = Btn
    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 0)
    Container.Visible = false; Container.ClipsDescendants = true
    Container.ZIndex = 10
    Container.BackgroundColor3 = CurrentTheme.Main
    Container.BackgroundTransparency = 0.05
    Container.Parent = parent
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 8)
    local List = Instance.new("UIListLayout")
    List.SortOrder = Enum.SortOrder.LayoutOrder; List.Parent = Container
    local function updateLabel()
        if multi then
            if #selected == 0 then Lbl.Text = dropText..": (无)"
            else Lbl.Text = dropText..": "..table.concat(selected, ", ") end
        else
            Lbl.Text = dropText..": "..tostring(selected)
        end
    end
    updateLabel()
    local optionButtons = {}
    local function rebuildOptions(optList)
        for _, c in ipairs(Container:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        optionButtons = {}
        for _, opt in ipairs(optList) do
            local O = Instance.new("TextButton")
            O.Size = UDim2.new(1, 0, 0, 34)
            O.Text = ""; O.BackgroundTransparency = 1
            O.AutoButtonColor = false; O.Parent = Container
            local check = Instance.new("Frame")
            check.Size = UDim2.new(0, 16, 0, 16)
            check.Position = UDim2.new(0, 10, 0.5, -8)
            check.BackgroundColor3 = CurrentTheme.Accent
            check.BackgroundTransparency = 1
            check.ZIndex = 1; check.Parent = O
            Instance.new("UICorner", check).CornerRadius = UDim.new(0, 4)
            local checkMark = Instance.new("ImageLabel")
            checkMark.Size = UDim2.new(0, 12, 0, 12)
            checkMark.Position = UDim2.new(0.5, 0, 0.5, 0)
            checkMark.AnchorPoint = Vector2.new(0.5, 0.5)
            checkMark.BackgroundTransparency = 1
            checkMark.Image = "rbxassetid://16633109272"
            checkMark.ImageTransparency = 1; checkMark.Parent = check
            AddToRegistry(checkMark, "ImageColor3", "Accent")
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -40, 1, 0)
            label.Position = UDim2.new(0, 36, 0, 0)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamMedium
            label.Text = opt; label.TextSize = 12
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = O
            AddToRegistry(label, "TextColor3", "Text")
            O.MouseEnter:Connect(function() Tween(O, {BackgroundTransparency = 0.1}, 0.15) end)
            O.MouseLeave:Connect(function() Tween(O, {BackgroundTransparency = 1}, 0.15) end)
            local optData = { button = O, label = label, check = check, checkMark = checkMark, value = opt, selected = false }
            table.insert(optionButtons, optData)
            O.MouseButton1Click:Connect(function()
                if locked then return end
                if multi then
                    local idx = table.find(selected, opt)
                    if idx then table.remove(selected, idx); optData.selected = false
                    else table.insert(selected, opt); optData.selected = true end
                    optData.check.BackgroundTransparency = optData.selected and 0 or 1
                    optData.checkMark.ImageTransparency = optData.selected and 0 or 1
                    updateLabel()
                    if ConfigObjects[controlId] then ConfigObjects[controlId].Value = selected end
                    callback(selected)
                else
                    selected = opt
                    for _, d in ipairs(optionButtons) do
                        d.selected = (d.value == opt)
                        d.check.BackgroundTransparency = d.selected and 0 or 1
                        d.checkMark.ImageTransparency = d.selected and 0 or 1
                    end
                    updateLabel()
                    if ConfigObjects[controlId] then ConfigObjects[controlId].Value = selected end
                    callback(selected)
                    Dropped = false
                    Tween(Container, {Size = UDim2.new(1, 0, 0, 0)}, 0.28)
                    Tween(Icon, {Rotation = 0}, 0.28)
                    task.wait(0.3)
                    Container.Visible = false
                end
            end)
        end
        for _, d in ipairs(optionButtons) do
            if multi then d.selected = table.find(selected, d.value) ~= nil else d.selected = (d.value == selected) end
            d.check.BackgroundTransparency = d.selected and 0 or 1
            d.checkMark.ImageTransparency = d.selected and 0 or 1
        end
        if Dropped then
            local targetHeight = #optionButtons * 34
            Tween(Container, {Size = UDim2.new(1, 0, 0, targetHeight)}, 0.2)
        end
    end
    rebuildOptions(options)
    local locked = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local lockFrame, lockLabel = createLockOverlay(Btn, lockedTitle)
    lockFrame.Visible = locked
    ClickBtn.Active = not locked
    local function updateLock(state)
        locked = state; lockFrame.Visible = state; ClickBtn.Active = not state
        if state then Dropped = false; Container.Visible = false; Tween(Container, {Size = UDim2.new(1, 0, 0, 0)}, 0.1) end
    end
    ClickBtn.MouseEnter:Connect(function() if not locked then Tween(Btn, {BackgroundTransparency = 0.65}, 0.15) end end)
    ClickBtn.MouseLeave:Connect(function() if not locked then Tween(Btn, {BackgroundTransparency = 1}, 0.15) end end)
    ClickBtn.MouseButton1Click:Connect(function()
        if locked then return end
        Dropped = not Dropped
        if Dropped then
            Container.Visible = true
            local targetHeight = #optionButtons * 34
            Tween(Container, {Size = UDim2.new(1, 0, 0, targetHeight)}, 0.32)
            Tween(Icon, {Rotation = 180}, 0.32)
        else
            Tween(Container, {Size = UDim2.new(1, 0, 0, 0)}, 0.28)
            Tween(Icon, {Rotation = 0}, 0.28)
            task.wait(0.3)
            Container.Visible = false
        end
    end)
    local function isMouseOver(frame)
        if not frame then return false end
        local m = LocalPlayer:GetMouse()
        local ap, as = frame.AbsolutePosition, frame.AbsoluteSize
        return m.X >= ap.X and m.X <= ap.X + as.X and m.Y >= ap.Y and m.Y <= ap.Y + as.Y
    end
    local globalClickConn
    globalClickConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if Dropped and not locked then
                if not isMouseOver(Container) and not isMouseOver(Btn) then
                    Dropped = false
                    Tween(Container, {Size = UDim2.new(1, 0, 0, 0)}, 0.28)
                    Tween(Icon, {Rotation = 0}, 0.28)
                    task.wait(0.3)
                    Container.Visible = false
                end
            end
        end
    end)
    ConfigObjects[controlId] = {
        Type = "Dropdown",
        Value = multi and selected or selected,
        Get = function()
            if multi then
                local copy = {}
                for _, v in ipairs(selected) do copy[v] = true end
                return copy
            end
            return selected
        end,
        Set = function(val)
            if locked then return end
            if multi then
                if type(val) == "table" then
                    selected = {}
                    for k, v in pairs(val) do
                        if v == true and type(k) == "string" then
                            if table.find(options, k) then table.insert(selected, k) end
                        elseif v ~= true and v ~= false then
                            if table.find(options, v) then table.insert(selected, v) end
                        end
                    end
                else selected = {} end
            else
                if val and table.find(options, val) then selected = val else selected = options[1] or "" end
            end
            for _, d in ipairs(optionButtons) do
                if multi then d.selected = table.find(selected, d.value) ~= nil else d.selected = (d.value == selected) end
                d.check.BackgroundTransparency = d.selected and 0 or 1
                d.checkMark.ImageTransparency = d.selected and 0 or 1
            end
            updateLabel()
            ConfigObjects[controlId].Value = multi and selected or selected
            callback(selected)
        end,
        Refresh = function(newOptions)
            if locked then return end
            options = newOptions or {}
            selected = multi and {} or (options[1] or "")
            rebuildOptions(options)
            updateLabel()
        end
    }
    local self = {}
    function self.GetValue() return selected end
    function self.SetValue(val) if not locked then ConfigObjects[controlId].Set(val) end end
    function self.Refresh(newOptions) if not locked and ConfigObjects[controlId].Refresh then ConfigObjects[controlId].Refresh(newOptions) end end
    function self.SetVisible(state) Btn.Visible = state end
    function self.Lock(title) updateLock(true); if title then lockLabel.Text = title; lockedTitle = title end end
    function self.Unlock() updateLock(false) end
    function self.IsLocked() return locked end
    table.insert(WindowCleanup or {}, function() safeDisconnect(globalClickConn) end)
    return self
end

child.Keybind = function(_, config)
    config = safeConfig(config)
    local keyText = config.Name or ""
    local defaultKey = config.Default or Enum.KeyCode.M
    local mode = config.Mode or "Toggle"
    local callback = config.Callback or function() end
    local controlId = NewConfigId("Keybind", keyText)
    local parent = config.Parent or contentHolder
    local state = { Key = defaultKey.Name, Mode = mode, Toggled = false, IsWaiting = false }
    local kbDesc = config.Desc or config.Description
    local Tile = miRow(parent, kbDesc and 56 or 42)
    local TitleLbl = miLabel(Tile, keyText, 15, kbDesc and 8 or 12, UDim2.new(0.6, 0, 0, 18), 13)
    if kbDesc then miDesc(Tile, kbDesc, 15, 27, UDim2.new(0.6, 0, 0, 13)) end
    local KeyBtn = Instance.new("TextButton")
    KeyBtn.Size = UDim2.new(0, 0, 0, 30)
    KeyBtn.Position = UDim2.new(1, -10, 0.5, 0)
    KeyBtn.AnchorPoint = Vector2.new(1, 0.5)
    KeyBtn.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
    KeyBtn.BackgroundTransparency = 0; KeyBtn.Text = ""
    KeyBtn.AutoButtonColor = false; KeyBtn.Parent = Tile
    KeyBtn.AutomaticSize = Enum.AutomaticSize.X
    Instance.new("UICorner", KeyBtn).CornerRadius = UDim.new(0, 5)
    local keyStroke = Instance.new("UIStroke")
    keyStroke.Thickness = 1; keyStroke.Transparency = 0.65
    keyStroke.Color = CurrentTheme.Stroke; keyStroke.Parent = KeyBtn
    table.insert(ThemeListeners, function() keyStroke.Color = CurrentTheme.Stroke end)
    local innerLayout = Instance.new("UIListLayout")
    innerLayout.FillDirection = Enum.FillDirection.Horizontal
    innerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    innerLayout.Padding = UDim.new(0, 4)
    innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    innerLayout.Parent = KeyBtn
    local keyPadding = Instance.new("UIPadding")
    keyPadding.PaddingLeft = UDim.new(0, 7); keyPadding.PaddingRight = UDim.new(0, 8)
    keyPadding.Parent = KeyBtn
    local mouseIco = Instance.new("ImageLabel")
    mouseIco.Size = UDim2.fromOffset(13, 13)
    mouseIco.BackgroundTransparency = 1
    mouseIco.Image = "rbxassetid://10734898592"
    mouseIco.ImageTransparency = 0.35
    mouseIco.LayoutOrder = 1; mouseIco.Parent = KeyBtn
    AddToRegistry(mouseIco, "ImageColor3", "Text")
    local KeyLabel = Instance.new("TextLabel")
    KeyLabel.Text = state.Key
    KeyLabel.Size = UDim2.new(0, 0, 0, 14)
    KeyLabel.BackgroundTransparency = 1
    KeyLabel.Font = Enum.Font.GothamMedium
    KeyLabel.TextSize = 13
    KeyLabel.TextColor3 = CurrentTheme.Text
    KeyLabel.AutomaticSize = Enum.AutomaticSize.X
    KeyLabel.LayoutOrder = 2; KeyLabel.Parent = KeyBtn
    AddToRegistry(KeyLabel, "TextColor3", "Text")
    TextGradient:Skip(KeyLabel)
    local locked = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local lockFrame, lockLabel = createLockOverlay(Tile, lockedTitle)
    lockFrame.Visible = locked
    KeyBtn.Active = not locked
    local function updateLock(st) locked = st; lockFrame.Visible = st; KeyBtn.Active = not st end
    ConfigObjects[controlId] = {
        Type = "Keybind",
        Value = { Key = state.Key, Mode = state.Mode },
        Get = function() return { Key = state.Key, Mode = state.Mode } end,
        Set = function(val)
            if locked then return end
            if type(val) == "table" then
                state.Key = val.Key or state.Key
                state.Mode = val.Mode or state.Mode
                KeyLabel.Text = state.Key
                ConfigObjects[controlId].Value = { Key = state.Key, Mode = state.Mode }
            elseif type(val) == "string" then
                state.Key = val; KeyLabel.Text = val
                ConfigObjects[controlId].Value = { Key = val, Mode = state.Mode }
            end
        end
    }
    local function updateKeyDisplay(newKey)
        if locked then return end
        state.Key = newKey; KeyLabel.Text = newKey
        ConfigObjects[controlId].Value = { Key = newKey, Mode = state.Mode }
        if type(config.OnKeyChanged) == "function" then pcall(config.OnKeyChanged, newKey) end
    end
    KeyBtn.MouseButton1Click:Connect(function()
        if locked or state.IsWaiting then return end
        state.IsWaiting = true; KeyLabel.Text = "..."
        local input = UserInputService.InputBegan:Wait()
        state.IsWaiting = false
        local newKey = nil
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode.Name ~= "Unknown" then newKey = input.KeyCode.Name end
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then newKey = "MouseLeft"
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then newKey = "MouseRight" end
        if newKey then updateKeyDisplay(newKey) else KeyLabel.Text = state.Key end
    end)
    local inputConn, inputEndConn
    inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe or locked or state.IsWaiting then return end
        if UserInputService:GetFocusedTextBox() then return end
        local key = state.Key
        if state.Mode == "Toggle" then
            if key == "MouseLeft" and input.UserInputType == Enum.UserInputType.MouseButton1 then state.Toggled = not state.Toggled; pcall(callback, state.Toggled)
            elseif key == "MouseRight" and input.UserInputType == Enum.UserInputType.MouseButton2 then state.Toggled = not state.Toggled; pcall(callback, state.Toggled)
            elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == key then state.Toggled = not state.Toggled; pcall(callback, state.Toggled) end
        elseif state.Mode == "Hold" then
            if key == "MouseLeft" and input.UserInputType == Enum.UserInputType.MouseButton1 then pcall(callback, true)
            elseif key == "MouseRight" and input.UserInputType == Enum.UserInputType.MouseButton2 then pcall(callback, true)
            elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == key then pcall(callback, true) end
        end
    end)
    inputEndConn = UserInputService.InputEnded:Connect(function(input, gpe)
        if gpe or locked or state.IsWaiting then return end
        if state.Mode == "Hold" then
            local key = state.Key
            if key == "MouseLeft" and input.UserInputType == Enum.UserInputType.MouseButton1 then pcall(callback, false)
            elseif key == "MouseRight" and input.UserInputType == Enum.UserInputType.MouseButton2 then pcall(callback, false)
            elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == key then pcall(callback, false) end
        end
    end)
    local self = {}
    function self.SetValue(val, newMode) if not locked then ConfigObjects[controlId].Set(val, newMode) end end
    function self.GetValue() return { Key = state.Key, Mode = state.Mode } end
    function self.GetState() return state.Toggled end
    function self.SetMode(newMode) if not locked then state.Mode = newMode; ConfigObjects[controlId].Value = { Key = state.Key, Mode = state.Mode } end end
    function self.Destroy() safeDisconnect(inputConn); safeDisconnect(inputEndConn); Tile:Destroy(); ConfigObjects[controlId] = nil end
    function self.SetVisible(vis) Tile.Visible = vis end
    function self.Lock(title) updateLock(true); if title then lockLabel.Text = title; lockedTitle = title end end
    function self.Unlock() updateLock(false) end
    function self.IsLocked() return locked end
    return self
end

child.Input = function(_, config)
    config = safeConfig(config)
    local inputText = config.Name or ""
    local default   = config.Value or config.Default or ""
    local callback  = config.Callback or function() end
    local onChanged = config.OnChanged
    local placeholder = config.Placeholder or ""
    local numeric   = config.Numeric == true
    local maxLength = config.MaxLength or config.CharacterLimit
    local acceptedChars = config.AcceptedCharacters
    local locked    = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local parent    = config.Parent or contentHolder
    local controlId = NewConfigId("Input", inputText)

    local layout    = tostring(config.Layout or "Inline"):lower()
    local isBlock   = (layout == "block" or layout == "large" or layout == "big")
    local blockDesc   = config.Desc or config.Description
    local blockHeight = tonumber(config.Height) or (blockDesc and 88 or 70)
    local blockBoxH   = math.max(28, blockHeight - (blockDesc and 46 or 42))

    local finished = config.Finished
    if finished == nil then finished = isBlock end

    local function filterText(text)
        text = tostring(text or "")
        if maxLength then text = text:sub(1, maxLength) end
        if numeric then
            local filtered = text:gsub("[^%d%-]", "")
            if filtered:match("^-") then filtered = "-"..filtered:gsub("-", "") else filtered = filtered:gsub("-", "") end
            return filtered
        end
        if type(acceptedChars) == "function" then return acceptedChars(text)
        elseif acceptedChars == "Alphabetic" then return text:gsub("[^a-zA-Z]", "")
        elseif acceptedChars == "AlphaNumeric" then return text:gsub("[^a-zA-Z0-9]", "") end
        return text
    end

    local InputBox, boxStroke, TitleLbl, Container

    if not isBlock then
        local ipDesc = config.Desc or config.Description
        Container = miRow(parent, ipDesc and 56 or 42)
        TitleLbl = miLabel(Container, inputText, 15, ipDesc and 8 or 12, UDim2.new(0.6, 0, 0, 18), 13)
        if ipDesc then miDesc(Container, ipDesc, 15, 27, UDim2.new(0.6, 0, 0, 13)) end
        local BoxContainer = Instance.new("Frame")
        BoxContainer.Size = UDim2.new(0.3, 0, 0, 28)
        BoxContainer.Position = UDim2.new(0.7, -10, 0.5, -14)
        BoxContainer.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
        BoxContainer.BackgroundTransparency = 0
        BoxContainer.ClipsDescendants = true
        BoxContainer.BorderSizePixel = 0
        BoxContainer.Parent = Container
        Instance.new("UICorner", BoxContainer).CornerRadius = UDim.new(0, 6)

        boxStroke = Instance.new("UIStroke")
        boxStroke.Thickness = 1
        boxStroke.Transparency = 0.65
        boxStroke.Color = CurrentTheme.Stroke
        boxStroke.Parent = BoxContainer
        table.insert(ThemeListeners, function() boxStroke.Color = CurrentTheme.Stroke end)

        InputBox = Instance.new("TextBox")
        InputBox.Text = tostring(default)
        InputBox.PlaceholderText = placeholder
        InputBox.Size = UDim2.new(1, -10, 1, 0)
        InputBox.Position = UDim2.new(0, 5, 0, 0)
        InputBox.Font = Enum.Font.GothamBold
        InputBox.TextSize = 13
        InputBox.TextXAlignment = Enum.TextXAlignment.Left
        InputBox.ClearTextOnFocus = false
        InputBox.BackgroundTransparency = 1
        InputBox.Parent = BoxContainer
        AddToRegistry(InputBox, "TextColor3", "Accent")
        TextGradient:Skip(InputBox)
    else
        Container = Instance.new("Frame")
        Container.Size = UDim2.new(1, 0, 0, blockHeight)
        Container.BackgroundTransparency = 1
        Container.BorderSizePixel = 0
        Container.Parent = parent

        TitleLbl = miLabel(Container, inputText, 15, 8, UDim2.new(1, -30, 0, 20), 13)
        if blockDesc then miDesc(Container, blockDesc, 15, 26, UDim2.new(1, -30, 0, 13)) end

        local BoxContainer = Instance.new("Frame")
        BoxContainer.Size = UDim2.new(1, -30, 0, blockBoxH)
        BoxContainer.Position = UDim2.new(0, 15, 0, blockDesc and 44 or 35)
        BoxContainer.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
        BoxContainer.BackgroundTransparency = 0
        BoxContainer.BorderSizePixel = 0
        BoxContainer.ClipsDescendants = true
        BoxContainer.Parent = Container
        Instance.new("UICorner", BoxContainer).CornerRadius = UDim.new(0, 6)

        boxStroke = Instance.new("UIStroke")
        boxStroke.Thickness = 1
        boxStroke.Transparency = 0.65
        boxStroke.Color = CurrentTheme.Stroke
        boxStroke.Parent = BoxContainer
        table.insert(ThemeListeners, function() boxStroke.Color = CurrentTheme.Stroke end)

        InputBox = Instance.new("TextBox")
        InputBox.Text = tostring(default)
        InputBox.PlaceholderText = placeholder
        InputBox.Size = UDim2.new(1, -10, 1, -6)
        InputBox.Position = UDim2.new(0, 5, 0, 3)
        InputBox.Font = Enum.Font.GothamMedium
        InputBox.TextSize = 12
        InputBox.TextXAlignment = Enum.TextXAlignment.Left
        InputBox.TextYAlignment = Enum.TextYAlignment.Top
        InputBox.ClearTextOnFocus = false
        InputBox.MultiLine = true
        InputBox.BackgroundTransparency = 1
        InputBox.Parent = BoxContainer
        AddToRegistry(InputBox, "TextColor3", "Text")
        TextGradient:Skip(InputBox)
    end

    local lockFrame, lockLabel = createLockOverlay(Container, lockedTitle)
    lockFrame.Visible = locked
    InputBox.Active = not locked
    local function updateLock(st)
        locked = st
        lockFrame.Visible = st
        InputBox.Active = not st
    end

    InputBox.Focused:Connect(function()
        if not locked then Tween(boxStroke, {Transparency = 0.2}, 0.15) end
    end)

    local function updateValue(triggerCallback)
        if locked then return end
        local filtered = filterText(InputBox.Text)
        if filtered ~= InputBox.Text then InputBox.Text = filtered end
        if ConfigObjects[controlId] then ConfigObjects[controlId].Value = filtered end
        if triggerCallback then
            if callback then pcall(callback, filtered) end
            if onChanged then pcall(onChanged, filtered) end
        end
    end

    InputBox.FocusLost:Connect(function()
        Tween(boxStroke, {Transparency = 0.65}, 0.15)
        updateValue(true)
    end)

    if not finished then
        InputBox:GetPropertyChangedSignal("Text"):Connect(function()
            if locked then return end
            local raw = InputBox.Text
            local filtered = filterText(raw)
            if filtered ~= raw then InputBox.Text = filtered end
            if ConfigObjects[controlId] then ConfigObjects[controlId].Value = InputBox.Text end
            if callback then pcall(callback, InputBox.Text) end
            if onChanged then pcall(onChanged, InputBox.Text) end
        end)
    end

    ConfigObjects[controlId] = {
        Type = "Input",
        Value = InputBox.Text,
        Get = function() return InputBox.Text end,
        Set = function(val)
            if locked then return end
            local filtered = filterText(tostring(val))
            InputBox.Text = filtered
            ConfigObjects[controlId].Value = filtered
            if callback then pcall(callback, filtered) end
        end,
    }

    local self = {}
    function self.UpdateText(t)
        if locked then return end
        local f = filterText(tostring(t or ""))
        InputBox.Text = f
        ConfigObjects[controlId].Value = f
    end
    function self.GetText() return InputBox.Text end
    function self.SetValue(v) self.UpdateText(v) end
    function self.GetValue() return InputBox.Text end
    function self.UpdatePlaceholder(p) InputBox.PlaceholderText = tostring(p or "") end
    function self.SetVisible(v)
        v = v ~= false
        Container.Visible = v
        if not isBlock then
            Container.Size = v and UDim2.new(1, 0, 0, ipDesc and 56 or 42) or UDim2.new(1, 0, 0, 0)
        else
            Container.Size = v and UDim2.new(1, 0, 0, blockHeight) or UDim2.new(1, 0, 0, 0)
        end
    end
    function self.SetHeight(h)
        if not isBlock then return end
        blockHeight = tonumber(h) or blockHeight
        Container.Size = UDim2.new(1, 0, 0, blockHeight)
    end
    function self.Lock(t) updateLock(true); if t then lockLabel.Text = t; lockedTitle = t end end
    function self.Unlock() updateLock(false) end
    function self.IsLocked() return locked end
    return self
end

child.Paragraph = function(_, config)
    config = safeConfig(config)

    -- ===== 参数归一化 =====
    local title     = config.Name or config.Title or config.Text or ""
    local desc      = config.Content or config.Desc or ""
    if type(desc) == "table" then desc = table.concat(desc, "\n") end
    local thumbnail = config.Thumbnail or config.Icon or config.ImageLink or ""
    local thumbSize = config.ThumbnailSize or config.ImageSize or 80
    local imageLayout = tostring(config.ImageLayout or config.ImageSide or "Right"):lower()
    -- 兼容旧写法：ImageSide = "Left"/"Right"
    if imageLayout == "left" then imageLayout = "left"
    elseif imageLayout == "right" then imageLayout = "right"
    elseif imageLayout == "top" then imageLayout = "top"
    else imageLayout = "right" end

    local richText  = config.RichText ~= false
    local parent    = config.Parent or contentHolder
    local locked    = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"

    local hasDesc  = tostring(desc) ~= ""
    local hasThumb = tostring(thumbnail) ~= ""
    local mode
    if hasThumb then mode = "card"
    elseif hasDesc then mode = "paragraph"
    else mode = "line" end

    ---------------------------------------------------------------
    -- 模式 1：单行文字
    ---------------------------------------------------------------
    if mode == "line" then
        local H = 42
        local Tile = miRow(parent, H)
        local TextLabel = miLabel(Tile, title, 15, 12, UDim2.new(1, -30, 0, 18), 13)
        TextLabel.RichText = richText == true
        TextLabel.TextWrapped = false

        local lockFrame, lockLabel = createLockOverlay(Tile, lockedTitle)
        lockFrame.Visible = locked
        local function updateLock(st) locked = st; lockFrame.Visible = st end

        local self = {}
        function self.UpdateText(t) TextLabel.Text = tostring(t or "") end
        function self.SetTitle(t) TextLabel.Text = tostring(t or "") end
        function self.SetName(t) TextLabel.Text = tostring(t or "") end
        function self.SetContent(c) TextLabel.Text = tostring(c or "") end
        function self.SetDesc(c) TextLabel.Text = tostring(c or "") end
        function self.SetVisible(v)
            v = v ~= false
            Tile.Visible = v
            Tile.Size = v and UDim2.new(1, 0, 0, H) or UDim2.new(1, 0, 0, 0)
        end
        function self.Lock(t) updateLock(true); if t then lockLabel.Text = t; lockedTitle = t end end
        function self.Unlock() updateLock(false) end
        function self.IsLocked() return locked end
        return self
    end

    ---------------------------------------------------------------
    -- 模式 2 & 3：段落 / 图文卡片
    ---------------------------------------------------------------
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Parent = parent
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 13)
    pad.PaddingBottom = UDim.new(0, 13)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = frame

    -- 外层容器：横向(左/右图) 或 纵向(上图)
    local isTop = (imageLayout == "top")
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1
    row.Parent = frame
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = isTop and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
    rowLayout.VerticalAlignment = isTop and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center
    rowLayout.HorizontalAlignment = isTop and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Left
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Padding = UDim.new(0, 10)
    rowLayout.Parent = row

    -- 文字块
    local textHolder = Instance.new("Frame")
    if isTop then
        textHolder.Size = UDim2.new(1, 0, 0, 0)
    else
        textHolder.Size = UDim2.new(1, hasThumb and -(thumbSize + 10) or 0, 0, 0)
    end
    textHolder.AutomaticSize = Enum.AutomaticSize.Y
    textHolder.BackgroundTransparency = 1
    textHolder.Parent = row
    local textLayout = Instance.new("UIListLayout")
    textLayout.SortOrder = Enum.SortOrder.LayoutOrder
    textLayout.Padding = UDim.new(0, 2)
    textLayout.Parent = textHolder

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 14)
    titleLabel.AutomaticSize = Enum.AutomaticSize.Y
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.Text = tostring(title)
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextWrapped = true
    titleLabel.RichText = richText
    titleLabel.Parent = textHolder
    AddToRegistry(titleLabel, "TextColor3", "Text")

    local contentLabel = Instance.new("TextLabel")
    contentLabel.Size = UDim2.new(1, 0, 0, 14)
    contentLabel.AutomaticSize = Enum.AutomaticSize.Y
    contentLabel.BackgroundTransparency = 1
    contentLabel.Font = Enum.Font.Gotham
    contentLabel.Text = tostring(desc)
    contentLabel.TextSize = 12
    contentLabel.TextXAlignment = Enum.TextXAlignment.Left
    contentLabel.TextWrapped = true
    contentLabel.RichText = richText
    contentLabel.Parent = textHolder
    AddToRegistry(contentLabel, "TextColor3", "SubText")
    TextGradient:Skip(contentLabel)

    -- 缩略图
    local thumbImg = nil
    if hasThumb then
        thumbImg = Instance.new("ImageLabel")
        if isTop then
            -- 上图模式：宽度撑满，高度 = 宽度 * (ThumbnailSize 作为高度比例? 这里直接用固定高度)
            -- 用 ThumbnailSize 作为高度像素，宽度撑满整个 row
            thumbImg.Size = UDim2.new(1, 0, 0, thumbSize)
        else
            thumbImg.Size = UDim2.new(0, thumbSize, 0, thumbSize)
        end
        thumbImg.BackgroundTransparency = 1
        thumbImg.ScaleType = Enum.ScaleType.Crop   -- 大图用 Crop 填满
        thumbImg.Parent = row
        Instance.new("UICorner", thumbImg).CornerRadius = UDim.new(0, 8)

        local function normalizeAsset(src)
            if type(src) == "number" then return "rbxassetid://"..src end
            if type(src) ~= "string" then return "" end
            if src:match("^rbxasset") or src:match("^http") then return src end
            if tonumber(src) then return "rbxassetid://"..src end
            return src
        end
        local src = normalizeAsset(thumbnail)
        if src:match("^https?://") then
            task.spawn(function()
                local ok, asset = pcall(function() return MediaManager:Image(src) end)
                if ok and asset and asset ~= "" then thumbImg.Image = asset end
            end)
        else
            thumbImg.Image = src
        end

        -- 布局顺序
        if isTop then
            thumbImg.LayoutOrder = 1
            textHolder.LayoutOrder = 2
        elseif imageLayout == "left" then
            thumbImg.LayoutOrder = 1
            textHolder.LayoutOrder = 2
        else -- right
            textHolder.LayoutOrder = 1
            thumbImg.LayoutOrder = 2
        end
    else
        textHolder.LayoutOrder = 1
    end

    -- 锁定遮罩
    local lockFrame, lockLabel = createLockOverlay(frame, lockedTitle)
    lockFrame.Visible = locked
    local function updateLock(st) locked = st; lockFrame.Visible = st end

    local self = {}
    function self.SetTitle(t) titleLabel.Text = tostring(t or "") end
    function self.SetName(t) titleLabel.Text = tostring(t or "") end
    function self.UpdateText(t) titleLabel.Text = tostring(t or "") end
    function self.SetContent(c) contentLabel.Text = tostring(c or "") end
    function self.SetDesc(c) contentLabel.Text = tostring(c or "") end
    function self.SetThumbnail(src)
        if not thumbImg then return end
        local ok, asset = pcall(function() return MediaManager:Image(tostring(src or "")) end)
        thumbImg.Image = (ok and asset and asset ~= "") and asset or tostring(src or "")
    end

    function self.SetVisible(v)
        v = v ~= false
        if v then
            frame.Visible = true
            frame.AutomaticSize = Enum.AutomaticSize.Y
            frame.Size = UDim2.new(1, 0, 0, 0)
        else
            frame.Visible = false
            frame.AutomaticSize = Enum.AutomaticSize.None
            frame.Size = UDim2.new(1, 0, 0, 0)
        end
    end

    function self.Lock(t) updateLock(true); if t then lockLabel.Text = t; lockedTitle = t end end
    function self.Unlock() updateLock(false) end
    function self.IsLocked() return locked end
    function self.Destroy() frame:Destroy() end
    return self
end

child.Divider = function(_, config)
    config = safeConfig(config)
    local parent    = config.Parent or contentHolder
    local labelText = tostring(config.Text or config.Name or "")

    local container = Instance.new("Frame")
    container.Size              = UDim2.new(1, 0, 0, 10)
    container.BackgroundTransparency = 1
    container.BorderSizePixel   = 0
    container.Parent            = parent

    do
        local siblings = parent:GetChildren()
        for i, sib in ipairs(siblings) do
            if sib == container then
                if i > 1 then
                    local prev = siblings[i - 1]
                    for _, c in ipairs(prev:GetChildren()) do
                        if c:IsA("Frame")
                            and c.Size.Y.Offset == 1
                            and c.Position.Y.Scale == 1
                            and c.BackgroundTransparency < 1 then
                            c.Visible = false
                        end
                    end
                end
                break
            end
        end
    end

    local leftLine = Instance.new("Frame")
    leftLine.AnchorPoint          = Vector2.new(0, 0.5)
    leftLine.BackgroundColor3     = CurrentTheme.Stroke
    leftLine.BackgroundTransparency = 0.650
    leftLine.BorderSizePixel      = 0
    leftLine.Position             = UDim2.new(0, 10, 0.5, 0)
    leftLine.Size                 = UDim2.new(0.5, -20, 0, 1)
    leftLine.Parent               = container
    AddToRegistry(leftLine, "BackgroundColor3", "Stroke")

    local textLabel = Instance.new("TextLabel")
    textLabel.AnchorPoint          = Vector2.new(0.5, 0.5)
    textLabel.BackgroundTransparency = 1.000
    textLabel.BorderSizePixel      = 0
    textLabel.Position             = UDim2.fromScale(0.5, 0.5)
    textLabel.Size                 = UDim2.new(0, 0, 0, 10)
    textLabel.Font                 = Enum.Font.GothamMedium
    textLabel.Text                 = labelText
    textLabel.TextColor3           = CurrentTheme.Text
    textLabel.TextSize             = 10.000
    textLabel.TextTransparency     = 0.500
    textLabel.Parent               = container
    AddToRegistry(textLabel, "TextColor3", "Text")

    local rightLine = Instance.new("Frame")
    rightLine.AnchorPoint          = Vector2.new(1, 0.5)
    rightLine.BackgroundColor3     = CurrentTheme.Stroke
    rightLine.BackgroundTransparency = 0.650
    rightLine.BorderSizePixel      = 0
    rightLine.Position             = UDim2.new(1, -10, 0.5, 0)
    rightLine.Size                 = UDim2.new(0.5, -20, 0, 1)
    rightLine.Parent               = container
    AddToRegistry(rightLine, "BackgroundColor3", "Stroke")

    local function UpdateDivider()
        local Text = textLabel.Text

        if Text == "" then
            textLabel.Visible = false
            leftLine.Size     = UDim2.new(1, -20, 0, 1)
            rightLine.Visible = false
            return
        end

        textLabel.Visible = true
        rightLine.Visible = true

        local MaxTextWidth = math.max(40, container.AbsoluteSize.X - 70)
        local TextWidth = math.min(
            TextService:GetTextSize(
                Text,
                textLabel.TextSize,
                textLabel.Font,
                Vector2.new(math.huge, math.huge)
            ).X + 16,
            MaxTextWidth
        )

        textLabel.Size = UDim2.new(0, TextWidth, 0, 10)
        leftLine.Size  = UDim2.new(0.5, -(TextWidth / 2) - 12, 0, 1)
        rightLine.Size = UDim2.new(0.5, -(TextWidth / 2) - 12, 0, 1)
    end

    UpdateDivider()
    container:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateDivider)

    local self = {}
    function self.SetVisible(state) container.Visible = state end
    function self.SetText(newText)
        textLabel.Text = tostring(newText or "")
        UpdateDivider()
        return self
    end
    function self.GetText() return textLabel.Text end
    function self.UpdateText(newText)
        textLabel.Text = tostring(newText or "")
        UpdateDivider()
        return self
    end
    function self.Destroy() container:Destroy() end
    return self
end

child.Space = function(_, config)
    config = safeConfig(config)
    local height = (config and config.Height) or 8
    local parent = config and config.Parent or contentHolder
    local sp = Instance.new("Frame")
    sp.Size = UDim2.new(1, 0, 0, height)
    sp.BackgroundTransparency = 1; sp.BorderSizePixel = 0
    sp.Parent = parent
    local self = {}
    function self.SetHeight(h) height = h; sp.Size = UDim2.new(1, 0, 0, height) end
    function self.SetVisible(state) sp.Visible = state end
    function self.Destroy() sp:Destroy() end
    return self
end


    child.Tabbox = function(_, config)
        if type(config) == "string" then config = { Name = config } end
        config = config or {}
        local tabboxName = config.Name or "Tabbox"
        local parent = config.Parent or contentContainer or parent
        if not parent then return nil end

        local tabboxObj = { Tabs = {}, ActiveTab = nil }

        local tabboxFrame = Instance.new("Frame")
        tabboxFrame.Name = "TabboxFrame"
        tabboxFrame.Size = UDim2.new(1, -5, 0, 0)
        tabboxFrame.BackgroundColor3 = CurrentTheme.Main
        tabboxFrame.BackgroundTransparency = 0.5
        tabboxFrame.BorderSizePixel = 0
        tabboxFrame.ClipsDescendants = true
        tabboxFrame.Parent = parent
        Instance.new("UICorner", tabboxFrame).CornerRadius = UDim.new(0, 10)
        AddToRegistry(tabboxFrame, "BackgroundColor3", "Main")

        local tabboxStroke = Instance.new("UIStroke")
        tabboxStroke.Thickness = 1
        tabboxStroke.Transparency = 0.65
        tabboxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        tabboxStroke.Parent = tabboxFrame
        AddToRegistry(tabboxStroke, "Color", "Stroke")

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name = "TabboxTitle"
        titleLbl.Size = UDim2.new(1, -20, 0, 15)
        titleLbl.Position = UDim2.new(0, 10, 0, 5)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamMedium
        titleLbl.TextSize = 11
        titleLbl.Text = tabboxName
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.TextTransparency = 0.5
        titleLbl.Parent = tabboxFrame
        AddToRegistry(titleLbl, "TextColor3", "Text")
        TextGradient:Skip(titleLbl)

        local buttonHolder = Instance.new("Frame")
        buttonHolder.Name = "TabboxButtons"
        buttonHolder.Size = UDim2.new(1, -16, 0, 26)
        buttonHolder.Position = UDim2.new(0, 8, 0, 24)
        buttonHolder.BackgroundTransparency = 1
        buttonHolder.Parent = tabboxFrame
        local buttonLayout = Instance.new("UIListLayout")
        buttonLayout.FillDirection = Enum.FillDirection.Horizontal
        buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
        buttonLayout.Padding = UDim.new(0, 5)
        buttonLayout.Parent = buttonHolder

        local contentWrap = Instance.new("Frame")
        contentWrap.Name = "TabboxContent"
        contentWrap.Size = UDim2.new(1, -10, 0, 0)
        contentWrap.Position = UDim2.new(0, 5, 0, 56)
        contentWrap.BackgroundTransparency = 1
        contentWrap.Parent = tabboxFrame

        local HEADER_H = 56

        local function refreshHeight()
            local contentH = 0
            if tabboxObj.ActiveTab and tabboxObj.ActiveTab.ContentLayout then
                contentH = tabboxObj.ActiveTab.ContentLayout.AbsoluteContentSize.Y
            end
            local totalH = HEADER_H + contentH + 8
            TweenService:Create(tabboxFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint), {
                Size = UDim2.new(1, -5, 0, totalH)
            }):Play()
            contentWrap.Size = UDim2.new(1, -10, 0, contentH)
        end

        tabboxObj.AddTab = function(_, tabConfig)
            if type(tabConfig) == "string" then tabConfig = { Name = tabConfig } end
            tabConfig = tabConfig or {}
            local tabName = tabConfig.Name or "Tab"

            local subTab = { Name = tabName, Icon = tabConfig.Icon }

            local btn = Instance.new("TextButton")
            btn.Name = "SubTabButton"
            btn.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.AutoButtonColor = false
            btn.Parent = buttonHolder
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

            local btnStroke = Instance.new("UIStroke")
            btnStroke.Thickness = 1
            btnStroke.Transparency = 1
            btnStroke.Color = CurrentTheme.Stroke
            btnStroke.Parent = btn
            table.insert(ThemeListeners, function() btnStroke.Color = CurrentTheme.Stroke end)

            local btnLabel = Instance.new("TextLabel")
            btnLabel.Size = UDim2.new(1, 0, 1, 0)
            btnLabel.BackgroundTransparency = 1
            btnLabel.Font = Enum.Font.GothamMedium
            btnLabel.Text = tabName
            btnLabel.TextSize = 11
            btnLabel.TextTransparency = 0.5
            btnLabel.Parent = btn
            AddToRegistry(btnLabel, "TextColor3", "Text")

            local txtSize = TextService:GetTextSize(tabName, 11, Enum.Font.GothamMedium, Vector2.new(math.huge, math.huge))
            btn.Size = UDim2.new(0, txtSize.X + 24, 1, 0)

            local contentFrame = Instance.new("Frame")
            contentFrame.Name = "SubTabContent"
            contentFrame.Size = UDim2.new(1, 0, 0, 0)
            contentFrame.AutomaticSize = Enum.AutomaticSize.Y
            contentFrame.BackgroundTransparency = 1
            contentFrame.Visible = false
            contentFrame.Parent = contentWrap

            local contentList = Instance.new("UIListLayout")
            contentList.Padding = UDim.new(0, 0)
            contentList.SortOrder = Enum.SortOrder.LayoutOrder
            contentList.HorizontalAlignment = Enum.HorizontalAlignment.Center
            contentList.Parent = contentFrame

            subTab.ContentLayout = contentList
            subTab.ContentFrame = contentFrame

            local function setActive(active)
                if active then
                    btn.BackgroundTransparency = 0.5
                    btnStroke.Transparency = 0.65
                    btnLabel.TextTransparency = 0
                    contentFrame.Visible = true
                else
                    btn.BackgroundTransparency = 1
                    btnStroke.Transparency = 1
                    btnLabel.TextTransparency = 0.5
                    contentFrame.Visible = false
                end
            end
            subTab.SetActive = function(_, a) setActive(a) end

            btn.MouseButton1Click:Connect(function()
                tabboxObj.ActiveTab = subTab
                for _, t in ipairs(tabboxObj.Tabs) do
                    t:SetActive(t == subTab)
                end
                refreshHeight()
            end)

            table.insert(tabboxObj.Tabs, subTab)

            if not tabboxObj.ActiveTab then
                tabboxObj.ActiveTab = subTab
                setActive(true)
            else
                setActive(false)
            end

            contentList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                if tabboxObj.ActiveTab == subTab then
                    refreshHeight()
                end
            end)

            local subBuilder = createSectionBuilder(contentFrame, contentFrame, elementWidth, windowCount, win)
            return setmetatable({}, {
                __index = function(_, key)
                    local fn = subBuilder[key]
                    if key == "Section" then
                        return function(self, cfg) return fn(subBuilder, cfg) end
                    end
                    if type(fn) == "function" then
                        return function(self, cfg)
                            cfg = cfg or {}
                            if type(cfg) == "table" and cfg.Parent == nil then
                                cfg.Parent = contentFrame
                            end
                            return fn(subBuilder, cfg)
                        end
                    end
                    return fn
                end
            })
        end

        tabboxObj.SetVisible = function(_, vis) tabboxFrame.Visible = vis end
        tabboxObj.Destroy = function(_) tabboxFrame:Destroy() end

        refreshHeight()
        return tabboxObj
    end

-- home_hero.lua
-- 顶部主页大卡片（横幅 + 品牌 + 问候）
-- 依赖：CurrentTheme, ThemeListeners, TextGradient, TextService, RunService, LocalPlayer

child = child or {}

child.HomeHero = function(_, config)
    config = config or {}

    local Parent = config.Parent
    local LayoutOrder = config.LayoutOrder or 1
    local Height = config.Height or 170
    local BannerImage = config.BannerImage or "rbxassetid://135781374174090"
    local BrandText = config.BrandText or "KG_UI"
    local CornerRadius = config.CornerRadius or 8

    local Player = LocalPlayer

    local HourText = config.GreetingTable or {
        [0]="零点啦，该睡了",[1]="凌晨一点，还不睡？",
        [2]="两点多了，眼皮打架了吧",[3]="三点，夜猫子上线",
        [4]="四点，天快亮了",[5]="五点，你不会通宵了吧",
        [6]="六点，早安",[7]="七点，该吃早饭了",
        [8]="八点，上午开始了",[9]="九点，干活时间",
        [10]="十点，喝口水吧",[11]="十一点，快到中午了",
        [12]="十二点，该吃午饭了",[13]="一点了，午休一下吧",
        [14]="两点，下午茶时间",[15]="三点，下午过半了",
        [16]="四点，摸摸鱼",[17]="五点，快吃晚饭了",
        [18]="六点，晚饭时间",[19]="七点，晚上好",
        [20]="八点，夜生活开始",[21]="九点，该洗澡了",
        [22]="十点，要睡觉了哦",[23]="十一点了，困不困呀",
    }

    local function Greeting()
        if type(config.GetGreeting) == "function" then
            return config.GetGreeting()
        end
        local h = math.floor(workspace:GetServerTimeNow() % 86400 / 3600)
        return HourText[h] or ""
    end

    -- 根卡片
    local Root = Instance.new("Frame")
    Root.Name = "HomeHero"
    Root.Size = UDim2.new(1, 0, 0, Height)
    Root.BackgroundColor3 = CurrentTheme.Top
    Root.BackgroundTransparency = 0.25
    Root.BorderSizePixel = 0
    Root.ClipsDescendants = true
    Root.LayoutOrder = LayoutOrder
    Root.Parent = Parent
    Instance.new("UICorner", Root).CornerRadius = UDim.new(0, CornerRadius)

    local Stroke = Instance.new("UIStroke")
    Stroke.Color = CurrentTheme.Stroke
    Stroke.Transparency = 0.68
    Stroke.Parent = Root
    table.insert(ThemeListeners, function()
        Root.BackgroundColor3 = CurrentTheme.Top
        Stroke.Color = CurrentTheme.Stroke
    end)

    -- 右侧横幅图（底部留 14px 美观间距）
    local Banner = Instance.new("ImageLabel")
    Banner.Name = "Banner"
    Banner.BackgroundTransparency = 1
    Banner.BorderSizePixel = 0
    Banner.Image = BannerImage
    Banner.ScaleType = Enum.ScaleType.Crop
    Banner.Size = UDim2.new(0.62, 0, 1, -14) -- 【改】原来 -40
    Banner.Position = UDim2.fromScale(1, 0)
    Banner.AnchorPoint = Vector2.new(1, 0)
    Banner.ImageTransparency = 0.25
    Banner.Parent = Root
    Instance.new("UICorner", Banner).CornerRadius = UDim.new(0, CornerRadius)

    local BannerFade = Instance.new("UIGradient")
    BannerFade.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.55, 0.35),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    BannerFade.Parent = Banner

    -- 左侧文字区（底部留 14px）
    local HeroText = Instance.new("Frame")
    HeroText.Name = "Text"
    HeroText.BackgroundTransparency = 1
    HeroText.Size = UDim2.new(0.66, 0, 1, -14) -- 【改】原来 -40
    HeroText.Parent = Root

    local TP = Instance.new("UIPadding")
    TP.PaddingTop = UDim.new(0, 14)
    TP.PaddingBottom = UDim.new(0, 14) -- 文字离底留 14px，好看
    TP.PaddingLeft = UDim.new(0, 24)
    TP.Parent = HeroText

    local TL = Instance.new("UIListLayout")
    TL.SortOrder = Enum.SortOrder.LayoutOrder
    TL.VerticalAlignment = Enum.VerticalAlignment.Bottom
    TL.Padding = UDim.new(0, 6)
    TL.Parent = HeroText

    -- 品牌行
    local Eyebrow = Instance.new("Frame")
    Eyebrow.Name = "Eyebrow"
    Eyebrow.BackgroundTransparency = 1
    Eyebrow.Size = UDim2.new(1, 0, 0, 20)
    Eyebrow.LayoutOrder = 1
    Eyebrow.Parent = HeroText

    local EL = Instance.new("UIListLayout")
    EL.FillDirection = Enum.FillDirection.Horizontal
    EL.VerticalAlignment = Enum.VerticalAlignment.Center
    EL.Padding = UDim.new(0, 8)
    EL.SortOrder = Enum.SortOrder.LayoutOrder
    EL.Parent = Eyebrow

    -- 呼吸点
    local Pip = Instance.new("Frame")
    Pip.Size = UDim2.fromOffset(7, 7)
    Pip.BorderSizePixel = 0
    Pip.BackgroundColor3 = CurrentTheme.Accent
    Pip.Parent = Eyebrow
    Instance.new("UICorner", Pip).CornerRadius = UDim.new(1, 0)

    local PipRing = Instance.new("Frame")
    PipRing.AnchorPoint = Vector2.new(0.5, 0.5)
    PipRing.Position = UDim2.fromScale(0.5, 0.5)
    PipRing.Size = UDim2.fromScale(1, 1)
    PipRing.BackgroundColor3 = CurrentTheme.Accent
    PipRing.BackgroundTransparency = 0.5
    PipRing.BorderSizePixel = 0
    PipRing.Parent = Pip
    Instance.new("UICorner", PipRing).CornerRadius = UDim.new(1, 0)

    table.insert(ThemeListeners, function()
        Pip.BackgroundColor3 = CurrentTheme.Accent
        PipRing.BackgroundColor3 = CurrentTheme.Accent
    end)

    local pipPhase, pipConn = 0, nil
    pipConn = RunService.RenderStepped:Connect(function(dt)
        if not (Pip.Parent and PipRing.Parent) then
            if pipConn then pipConn:Disconnect(); pipConn = nil end
            return
        end
        pipPhase = (pipPhase + dt / 1.8) % 1
        local p = 1 - (1 - pipPhase) ^ 3
        PipRing.Size = UDim2.fromScale(1 + p * 2.4, 1 + p * 2.4)
        PipRing.BackgroundTransparency = 0.5 + 0.5 * p
    end)

    -- 品牌文字
    local EyebrowText = Instance.new("TextLabel")
    EyebrowText.BackgroundTransparency = 1
    EyebrowText.BorderSizePixel = 0
    EyebrowText.Font = Enum.Font.GothamBold
    EyebrowText.TextSize = 10
    EyebrowText.Text = BrandText
    EyebrowText.TextColor3 = CurrentTheme.Accent
    EyebrowText.TextXAlignment = Enum.TextXAlignment.Left
    EyebrowText.Size = UDim2.new(0, 0, 0, 14)
    EyebrowText.AutomaticSize = Enum.AutomaticSize.X
    EyebrowText.Parent = Eyebrow

    -- 主标题
    local HeroTitle = Instance.new("TextLabel")
    HeroTitle.Name = "HeroTitle"
    HeroTitle.BackgroundTransparency = 1
    HeroTitle.BorderSizePixel = 0
    HeroTitle.Font = Enum.Font.GothamBold
    HeroTitle.TextSize = 46
    HeroTitle.Text = "你好，" .. Player.DisplayName
    HeroTitle.TextColor3 = CurrentTheme.Text
    HeroTitle.TextXAlignment = Enum.TextXAlignment.Left
    HeroTitle.TextTruncate = Enum.TextTruncate.AtEnd
    HeroTitle.Size = UDim2.new(1, 0, 0, 0)
    HeroTitle.AutomaticSize = Enum.AutomaticSize.Y
    HeroTitle.LayoutOrder = 2
    HeroTitle.Parent = HeroText
    if TextGradient then TextGradient:Add(HeroTitle) end

    -- 副标题
    local HeroSub = Instance.new("TextLabel")
    HeroSub.Name = "HeroSub"
    HeroSub.BackgroundTransparency = 1
    HeroSub.BorderSizePixel = 0
    HeroSub.Font = Enum.Font.GothamMedium
    HeroSub.TextSize = 13
    HeroSub.Text = "@" .. Player.Name
    HeroSub.TextColor3 = CurrentTheme.Text
    HeroSub.TextTransparency = 0.25
    HeroSub.TextXAlignment = Enum.TextXAlignment.Left
    HeroSub.TextWrapped = true
    HeroSub.Size = UDim2.new(1, 0, 0, 0)
    HeroSub.AutomaticSize = Enum.AutomaticSize.Y
    HeroSub.LayoutOrder = 3
    HeroSub.Parent = HeroText
    if TextGradient then TextGradient:Skip(HeroSub) end

    -- 定时刷新问候和名字
    local acc = 0
    local updateConn = RunService.RenderStepped:Connect(function(dt)
        acc += dt
        if acc < 0.5 then return end
        acc = 0
        HeroTitle.Text = "你好，" .. Player.DisplayName
        HeroSub.Text = Greeting() .. " | @" .. Player.Name
    end)

    local API = {
        Root = Root,
        Banner = Banner,
        Title = HeroTitle,
        Subtitle = HeroSub,
        Destroy = function()
            if updateConn then updateConn:Disconnect(); updateConn = nil end
            if pipConn then pipConn:Disconnect(); pipConn = nil end
            Root:Destroy()
        end
    }

    return API
end

child.Colorpicker = function(_, config)
    config = safeConfig(config)
    local cpTitle       = config.Name or config.Title or "Colorpicker"
    local defaultColor  = config.Default or config.Value or Color3.fromRGB(255, 255, 255)
    local callback      = config.Callback or function() end
    local transCfg      = config.Transparency
    local hasTransparency = (transCfg ~= nil)
    local controlId     = NewConfigId("Colorpicker", cpTitle)
    local parent        = config.Parent or contentHolder

    local state = { Default = defaultColor, Transparency = transCfg, Hue = 0, Sat = 0, Vib = 0 }
    state.Hue, state.Sat, state.Vib = Color3.toHSV(defaultColor)

    local cpDesc = config.Desc or config.Description
    local Tile = miRow(parent, cpDesc and 56 or 42)
    local TitleLbl = miLabel(Tile, cpTitle, 15, cpDesc and 8 or 12, UDim2.new(1, -70, 0, 18), 13)
    if cpDesc then miDesc(Tile, cpDesc, 15, 27, UDim2.new(1, -70, 0, 13)) end

    local PreviewWrap = Instance.new("Frame")
    PreviewWrap.Size = UDim2.fromOffset(40, 26)
    PreviewWrap.Position = UDim2.new(1, -50, 0.5, -13)
    PreviewWrap.BackgroundTransparency = 1
    PreviewWrap.BorderSizePixel = 0
    PreviewWrap.Parent = Tile
    Instance.new("UICorner", PreviewWrap).CornerRadius = UDim.new(0, 6)

    local PreviewChecker = Instance.new("ImageLabel")
    PreviewChecker.Size = UDim2.fromScale(1, 1)
    PreviewChecker.BackgroundTransparency = 1
    PreviewChecker.Image = CHESSBOARD_IMAGE
    PreviewChecker.ImageTransparency = 0.35
    PreviewChecker.ScaleType = Enum.ScaleType.Tile
    PreviewChecker.TileSize = UDim2.fromOffset(10, 10)
    PreviewChecker.ZIndex = 1
    PreviewChecker.Parent = PreviewWrap
    Instance.new("UICorner", PreviewChecker).CornerRadius = UDim.new(0, 6)

    local PreviewBtn = Instance.new("TextButton")
    PreviewBtn.Size = UDim2.fromScale(1, 1)
    PreviewBtn.BackgroundColor3 = state.Default
    PreviewBtn.BackgroundTransparency = hasTransparency and state.Transparency or 0
    PreviewBtn.BorderSizePixel = 0
    PreviewBtn.Text = ""
    PreviewBtn.AutoButtonColor = false
    PreviewBtn.ZIndex = 2
    PreviewBtn.Parent = PreviewWrap
    Instance.new("UICorner", PreviewBtn).CornerRadius = UDim.new(0, 6)

    local previewStroke = Instance.new("UIStroke")
    previewStroke.Thickness = 1.5
    previewStroke.Color = CurrentTheme.Stroke
    previewStroke.Transparency = 0.3
    previewStroke.Parent = PreviewBtn
    table.insert(ThemeListeners, function() previewStroke.Color = CurrentTheme.Stroke end)

    local locked      = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local lockFrame, lockLabel = createLockOverlay(Tile, lockedTitle)
    lockFrame.Visible = locked
    PreviewBtn.Active = not locked

    local dialogOpen = false
    local function OpenColorpicker()
        if locked or dialogOpen then return end
        local sg = parent
        while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
        if not sg then return end
        dialogOpen = true

        local W = { Hue = state.Hue, Sat = state.Sat, Vib = state.Vib, Transparency = state.Transparency or 0 }
        local function CurColor() return Color3.fromHSV(W.Hue, W.Sat, W.Vib) end
        local TextPadding = 10

        local Overlay = Instance.new("Frame")
        Overlay.Size = UDim2.fromScale(1, 1)
        Overlay.BackgroundColor3 = Color3.new(0, 0, 0)
        Overlay.BackgroundTransparency = 1
        Overlay.ZIndex = 500
        Overlay.Active = true
        Overlay.Parent = sg

        local MainContainer = Instance.new("ImageLabel")
        MainContainer.Image = "rbxassetid://8992230677"
        MainContainer.ScaleType = Enum.ScaleType.Slice
        MainContainer.SliceCenter = Rect.new(99, 99, 99, 99)
        MainContainer.ImageTransparency = 1
        MainContainer.ImageColor3 = CurrentTheme.Main
        MainContainer.BackgroundTransparency = 1
        MainContainer.AnchorPoint = Vector2.new(0.5, 0.5)
        MainContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
        MainContainer.AutomaticSize = Enum.AutomaticSize.XY
        MainContainer.Visible = false
        MainContainer.ZIndex = 501
        MainContainer.Parent = Overlay
        Instance.new("UICorner", MainContainer).CornerRadius = UDim.new(0, 26)

        local Main = Instance.new("Frame")
        Main.Size = UDim2.new(0, 280, 0, 0)
        Main.AutomaticSize = Enum.AutomaticSize.Y
        Main.BackgroundTransparency = 1
        Main.Visible = false
        Main.ZIndex = 502
        Main.Parent = MainContainer

        local Title = Instance.new("TextLabel")
        Title.Text = cpTitle
        Title.TextSize = 20
        local fontOk = pcall(function()
            Title.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold)
        end)
        if not fontOk then Title.Font = Enum.Font.GothamBold end
        Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Size = UDim2.new(1, 0, 0, 0)
        Title.AutomaticSize = Enum.AutomaticSize.Y
        Title.TextColor3 = CurrentTheme.Text
        Title.BackgroundTransparency = 1
        Title.Parent = Main
        AddToRegistry(Title, "TextColor3", "Text")
        local titlePad = Instance.new("UIPadding")
        titlePad.PaddingTop    = UDim.new(0, TextPadding / 2)
        titlePad.PaddingLeft   = UDim.new(0, TextPadding / 2)
        titlePad.PaddingRight  = UDim.new(0, TextPadding / 2)
        titlePad.PaddingBottom = UDim.new(0, TextPadding / 2)
        titlePad.Parent = Title

        local SatVibMap = Instance.new("ImageLabel")
        SatVibMap.Size = UDim2.fromOffset(160, 158)
        SatVibMap.Position = UDim2.fromOffset(0, 40 + TextPadding)
        SatVibMap.Image = "rbxassetid://4155801252"
        SatVibMap.BackgroundColor3 = Color3.fromHSV(W.Hue, 1, 1)
        SatVibMap.BackgroundTransparency = 0
        SatVibMap.ZIndex = 3
        SatVibMap.Parent = Main
        Instance.new("UICorner", SatVibMap).CornerRadius = UDim.new(0, 8)

        local SatVibDot = Instance.new("Frame")
        SatVibDot.Size = UDim2.fromOffset(14, 14)
        SatVibDot.AnchorPoint = Vector2.new(0.5, 0.5)
        SatVibDot.Position = UDim2.new(W.Sat, 0, 1 - W.Vib, 0)
        SatVibDot.BackgroundColor3 = CurColor()
        SatVibDot.BorderSizePixel = 0
        SatVibDot.ZIndex = 4
        SatVibDot.Parent = SatVibMap
        Instance.new("UICorner", SatVibDot).CornerRadius = UDim.new(1, 0)
        local dotStroke = Instance.new("UIStroke")
        dotStroke.Thickness = 2
        dotStroke.Transparency = 0.1
        dotStroke.Color = CurrentTheme.Text
        dotStroke.Parent = SatVibDot
        table.insert(ThemeListeners, function() dotStroke.Color = CurrentTheme.Text end)

        local HueSlider = Instance.new("Frame")
        HueSlider.Size = UDim2.fromOffset(6, 192)
        HueSlider.Position = UDim2.fromOffset(180, 40 + TextPadding)
        HueSlider.BackgroundTransparency = 1
        HueSlider.Parent = Main

        local HueBar = Instance.new("Frame")
        HueBar.Size = UDim2.fromScale(1, 1)
        HueBar.BorderSizePixel = 0
        HueBar.Parent = HueSlider
        Instance.new("UICorner", HueBar).CornerRadius = UDim.new(1, 0)
        local hueKeys = {}
        for i = 0, 10 do
            table.insert(hueKeys, ColorSequenceKeypoint.new(i / 10, Color3.fromHSV(i / 10, 1, 1)))
        end
        local hueGrad = Instance.new("UIGradient")
        hueGrad.Color = ColorSequence.new(hueKeys)
        hueGrad.Rotation = 90
        hueGrad.Parent = HueBar

        local HueGrip = Instance.new("Frame")
        HueGrip.Size = UDim2.fromOffset(14, 14)
        HueGrip.AnchorPoint = Vector2.new(0.5, 0.5)
        HueGrip.Position = UDim2.new(0.5, 0, W.Hue, 0)
        HueGrip.BackgroundColor3 = Color3.fromHSV(W.Hue, 1, 1)
        HueGrip.BorderSizePixel = 0
        HueGrip.ZIndex = 3
        HueGrip.Parent = HueSlider
        Instance.new("UICorner", HueGrip).CornerRadius = UDim.new(1, 0)
        local hueGripStroke = Instance.new("UIStroke")
        hueGripStroke.Thickness = 2
        hueGripStroke.Transparency = 0.1
        hueGripStroke.Color = CurrentTheme.Text
        hueGripStroke.Parent = HueGrip
        table.insert(ThemeListeners, function() hueGripStroke.Color = CurrentTheme.Text end)

        local AlphaSlider, AlphaGrip, AlphaBar
        if hasTransparency then
            AlphaSlider = Instance.new("Frame")
            AlphaSlider.Size = UDim2.fromOffset(6, 192)
            AlphaSlider.Position = UDim2.fromOffset(210, 40 + TextPadding)
            AlphaSlider.BackgroundTransparency = 1
            AlphaSlider.Parent = Main

            local Checker = Instance.new("Frame")
            Checker.Size = UDim2.fromScale(1, 1)
            Checker.BackgroundColor3 = Color3.new(1, 1, 1)
            Checker.BorderSizePixel = 0
            Checker.Parent = AlphaSlider
            Instance.new("UICorner", Checker).CornerRadius = UDim.new(1, 0)

            local CheckerImg = Instance.new("ImageLabel")
            CheckerImg.Size = UDim2.fromScale(1, 1)
            CheckerImg.BackgroundTransparency = 1
            CheckerImg.Image = CHESSBOARD_IMAGE
            CheckerImg.ImageTransparency = 0.35
            CheckerImg.ScaleType = Enum.ScaleType.Tile
            CheckerImg.TileSize = UDim2.fromOffset(10, 10)
            CheckerImg.Parent = Checker
            Instance.new("UICorner", CheckerImg).CornerRadius = UDim.new(1, 0)

            AlphaBar = Instance.new("Frame")
            AlphaBar.Size = UDim2.fromScale(1, 1)
            AlphaBar.BackgroundColor3 = CurColor()
            AlphaBar.BackgroundTransparency = W.Transparency
            AlphaBar.BorderSizePixel = 0
            AlphaBar.ZIndex = 2
            AlphaBar.Parent = AlphaSlider
            Instance.new("UICorner", AlphaBar).CornerRadius = UDim.new(1, 0)
            local alphaGrad = Instance.new("UIGradient")
            alphaGrad.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            })
            alphaGrad.Rotation = 270
            alphaGrad.Parent = AlphaBar

            AlphaGrip = Instance.new("Frame")
            AlphaGrip.Size = UDim2.fromOffset(14, 14)
            AlphaGrip.AnchorPoint = Vector2.new(0.5, 0.5)
            AlphaGrip.Position = UDim2.new(0.5, 0, 1 - W.Transparency, 0)
            AlphaGrip.BackgroundColor3 = CurColor()
            AlphaGrip.BorderSizePixel = 0
            AlphaGrip.ZIndex = 3
            AlphaGrip.Parent = AlphaSlider
            Instance.new("UICorner", AlphaGrip).CornerRadius = UDim.new(1, 0)
            local alphaGripStroke = Instance.new("UIStroke")
            alphaGripStroke.Thickness = 2
            alphaGripStroke.Transparency = 0.1
            alphaGripStroke.Color = CurrentTheme.Text
            alphaGripStroke.Parent = AlphaGrip
            table.insert(ThemeListeners, function() alphaGripStroke.Color = CurrentTheme.Text end)
        end

        local Preview1 = Instance.new("Frame")
        Preview1.Size = UDim2.fromOffset(75, 24)
        Preview1.Position = UDim2.fromOffset(0, 208 + TextPadding)
        Preview1.BackgroundTransparency = 1
        Preview1.BorderSizePixel = 0
        Preview1.Parent = Main
        Instance.new("UICorner", Preview1).CornerRadius = UDim.new(0, 8)

        local P1Checker = Instance.new("ImageLabel")
        P1Checker.Size = UDim2.fromScale(1, 1)
        P1Checker.BackgroundTransparency = 1
        P1Checker.Image = CHESSBOARD_IMAGE
        P1Checker.ImageTransparency = 0.35
        P1Checker.ScaleType = Enum.ScaleType.Tile
        P1Checker.TileSize = UDim2.fromOffset(10, 10)
        P1Checker.ZIndex = 1
        P1Checker.Parent = Preview1
        Instance.new("UICorner", P1Checker).CornerRadius = UDim.new(0, 8)

        local P1Color = Instance.new("Frame")
        P1Color.Size = UDim2.fromScale(1, 1)
        P1Color.BackgroundColor3 = CurColor()
        P1Color.BackgroundTransparency = hasTransparency and W.Transparency or 0
        P1Color.BorderSizePixel = 0
        P1Color.ZIndex = 2
        P1Color.Parent = Preview1
        Instance.new("UICorner", P1Color).CornerRadius = UDim.new(0, 8)

        local Preview2 = Instance.new("Frame")
        Preview2.Size = UDim2.fromOffset(75, 24)
        Preview2.Position = UDim2.fromOffset(85, 208 + TextPadding)
        Preview2.BackgroundColor3 = CurColor()
        Preview2.BackgroundTransparency = 0
        Preview2.BorderSizePixel = 0
        Preview2.Parent = Main
        Instance.new("UICorner", Preview2).CornerRadius = UDim.new(0, 8)

        local InputsFrame = Instance.new("Frame")
        InputsFrame.AutomaticSize = Enum.AutomaticSize.XY
        InputsFrame.Size = UDim2.new(0, 0, 0, 0)
        InputsFrame.Position = UDim2.fromOffset(hasTransparency and 240 or 210, 40 + TextPadding)
        InputsFrame.BackgroundTransparency = 1
        InputsFrame.Parent = Main
        local inputsList = Instance.new("UIListLayout")
        inputsList.FillDirection = Enum.FillDirection.Vertical
        inputsList.Padding = UDim.new(0, 4)
        inputsList.Parent = InputsFrame

        local function CreateNewInput(labelText, defaultText)
            local holder = Instance.new("Frame")
            holder.Size = UDim2.fromOffset(150, 42)
            holder.BackgroundTransparency = 1
            holder.Parent = InputsFrame

            local scale = Instance.new("UIScale")
            scale.Scale = 0.85
            scale.Parent = holder

            local box = Instance.new("Frame")
            box.Size = UDim2.fromScale(1, 1)
            box.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
            box.BorderSizePixel = 0
            box.Parent = holder
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

            local boxStroke = Instance.new("UIStroke")
            boxStroke.Thickness = 1
            boxStroke.Transparency = 0.65
            boxStroke.Color = CurrentTheme.Stroke
            boxStroke.Parent = box
            table.insert(ThemeListeners, function() boxStroke.Color = CurrentTheme.Stroke end)

            local tb = Instance.new("TextBox")
            tb.Size = UDim2.new(1, -20, 1, 0)
            tb.Position = UDim2.new(0, 10, 0, 0)
            tb.BackgroundTransparency = 1
            tb.Font = Enum.Font.GothamBold
            tb.TextSize = 14
            tb.TextColor3 = CurrentTheme.Text
            tb.TextXAlignment = Enum.TextXAlignment.Left
            tb.ClearTextOnFocus = false
            tb.Text = tostring(defaultText)
            tb.Parent = box
            AddToRegistry(tb, "TextColor3", "Text")
            TextGradient:Skip(tb)

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.fromOffset(30, 20)
            lbl.Position = UDim2.new(1, -40, 0.5, -10)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 12
            lbl.Text = labelText
            lbl.TextColor3 = CurrentTheme.Text
            lbl.TextTransparency = 0.4
            lbl.TextXAlignment = Enum.TextXAlignment.Right
            lbl.Parent = box
            AddToRegistry(lbl, "TextColor3", "Text")
            TextGradient:Skip(lbl)

            return tb
        end

        local c0 = CurColor()
        local HexInput = CreateNewInput("Hex", "#" .. c0:ToHex())
        local RInput  = CreateNewInput("R",  math.floor(c0.R * 255 + 0.5))
        local GInput  = CreateNewInput("G",  math.floor(c0.G * 255 + 0.5))
        local BInput  = CreateNewInput("B",  math.floor(c0.B * 255 + 0.5))
        local AlphaInput
        if hasTransparency then
            AlphaInput = CreateNewInput("A", math.floor((1 - W.Transparency) * 100 + 0.5))
        end

        local InputsX = hasTransparency and 240 or 210
        local InputsVisualRight = InputsX + 150 * 0.85

        local ButtonsFrame = Instance.new("Frame")
        ButtonsFrame.Size = UDim2.new(0, InputsVisualRight, 0, 40)
        ButtonsFrame.Position = UDim2.fromOffset(0, 254 + TextPadding)
        ButtonsFrame.BackgroundTransparency = 1
        ButtonsFrame.Parent = Main

        local suppressInput = false
        local function SyncUI()
            local cur = CurColor()
            SatVibMap.BackgroundColor3 = Color3.fromHSV(W.Hue, 1, 1)
            SatVibDot.Position = UDim2.new(W.Sat, 0, 1 - W.Vib, 0)
            SatVibDot.BackgroundColor3 = cur
            HueGrip.Position = UDim2.new(0.5, 0, W.Hue, 0)
            HueGrip.BackgroundColor3 = Color3.fromHSV(W.Hue, 1, 1)
            if AlphaBar then
                AlphaBar.BackgroundColor3 = cur
                AlphaBar.BackgroundTransparency = W.Transparency
            end
            if AlphaGrip then
                AlphaGrip.Position = UDim2.new(0.5, 0, 1 - W.Transparency, 0)
                AlphaGrip.BackgroundColor3 = cur
            end
            P1Color.BackgroundColor3 = cur
            P1Color.BackgroundTransparency = hasTransparency and W.Transparency or 0
            Preview2.BackgroundColor3 = cur
            PreviewBtn.BackgroundColor3 = cur
            PreviewBtn.BackgroundTransparency = hasTransparency and W.Transparency or 0

            if not suppressInput then
                suppressInput = true
                HexInput.Text = "#" .. cur:ToHex()
                RInput.Text = tostring(math.floor(cur.R * 255 + 0.5))
                GInput.Text = tostring(math.floor(cur.G * 255 + 0.5))
                BInput.Text = tostring(math.floor(cur.B * 255 + 0.5))
                if AlphaInput then
                    AlphaInput.Text = tostring(math.floor((1 - W.Transparency) * 100 + 0.5))
                end
                suppressInput = false
            end
        end

        local Mouse = Players.LocalPlayer:GetMouse()

        local function UpdateFromMap()
            local apX = SatVibMap.AbsolutePosition.X
            local apW = apX + SatVibMap.AbsoluteSize.X
            local mx  = math.clamp(Mouse.X, apX, apW)

            local apY = SatVibMap.AbsolutePosition.Y
            local apH = apY + SatVibMap.AbsoluteSize.Y
            local my  = math.clamp(Mouse.Y, apY, apH)

            W.Sat = (mx - apX) / (apW - apX)
            W.Vib = 1 - ((my - apY) / (apH - apY))
            SyncUI()
        end

        local function UpdateFromHue()
            local apY = HueSlider.AbsolutePosition.Y
            local apH = apY + HueSlider.AbsoluteSize.Y
            local my  = math.clamp(Mouse.Y, apY, apH)
            W.Hue = (my - apY) / (apH - apY)
            SyncUI()
        end

        local function UpdateFromAlpha()
            if not AlphaSlider then return end
            local apY = AlphaSlider.AbsolutePosition.Y
            local apH = apY + AlphaSlider.AbsoluteSize.Y
            local my  = math.clamp(Mouse.Y, apY, apH)
            W.Transparency = 1 - ((my - apY) / (apH - apY))
            SyncUI()
        end

        SatVibMap.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    UpdateFromMap()
                    RunService.RenderStepped:Wait()
                end
            end
        end)

        HueSlider.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    UpdateFromHue()
                    RunService.RenderStepped:Wait()
                end
            end
        end)

        if AlphaSlider then
            AlphaSlider.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                    while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                        UpdateFromAlpha()
                        RunService.RenderStepped:Wait()
                    end
                end
            end)
        end

        local function ApplyFromRGB()
            if suppressInput then return end
            local r = math.clamp(tonumber(RInput.Text) or 0, 0, 255)
            local g = math.clamp(tonumber(GInput.Text) or 0, 0, 255)
            local b = math.clamp(tonumber(BInput.Text) or 0, 0, 255)
            W.Hue, W.Sat, W.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
            SyncUI()
        end
        HexInput.FocusLost:Connect(function()
            if suppressInput then return end
            local txt = HexInput.Text:gsub("#", "")
            local ok, col = pcall(Color3.fromHex, txt)
            if ok and typeof(col) == "Color3" then
                W.Hue, W.Sat, W.Vib = Color3.toHSV(col)
                SyncUI()
            end
        end)
        RInput.FocusLost:Connect(ApplyFromRGB)
        GInput.FocusLost:Connect(ApplyFromRGB)
        BInput.FocusLost:Connect(ApplyFromRGB)
        if AlphaInput then
            AlphaInput.FocusLost:Connect(function()
                if suppressInput then return end
                local a = math.clamp(tonumber(AlphaInput.Text) or 0, 0, 100)
                W.Transparency = 1 - a / 100
                SyncUI()
            end)
        end

        local function CloseDialog()
            dialogOpen = false
            Tween(Main, {BackgroundTransparency = 1}, 0.1)
            Tween(MainContainer, {ImageTransparency = 1}, 0.12)
            Tween(Overlay, {BackgroundTransparency = 1}, 0.12)
            task.delay(0.16, function() Overlay:Destroy() end)
        end

        local function MakeDialogButton(text, isPrimary, onClick, side)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromOffset(100, 40)
            btn.BackgroundColor3 = isPrimary and CurrentTheme.Accent or Color3.fromRGB(26, 28, 36)
            btn.BorderSizePixel = 0
            btn.Text = text
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 14
            btn.TextColor3 = Color3.new(1, 1, 1)
            btn.AutoButtonColor = false
            if side == "right" then
                btn.AnchorPoint = Vector2.new(1, 0)
                btn.Position = UDim2.new(1, 0, 0, 0)
            else
                btn.AnchorPoint = Vector2.new(0, 0)
                btn.Position = UDim2.new(0, 0, 0, 0)
            end
            btn.Parent = ButtonsFrame
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
            if not isPrimary then
                local s = Instance.new("UIStroke")
                s.Color = CurrentTheme.Stroke
                s.Thickness = 1
                s.Transparency = 0.5
                s.Parent = btn
                table.insert(ThemeListeners, function() s.Color = CurrentTheme.Stroke end)
            end
            btn.MouseEnter:Connect(function() Tween(btn, {BackgroundTransparency = 0.15}, 0.12) end)
            btn.MouseLeave:Connect(function() Tween(btn, {BackgroundTransparency = 0}, 0.12) end)
            btn.MouseButton1Click:Connect(onClick)
            return btn
        end

        MakeDialogButton("取消", false, function()
            CloseDialog()
        end, "left")

        MakeDialogButton("确认", true, function()
            local cur = CurColor()
            state.Default = cur
            state.Hue, state.Sat, state.Vib = W.Hue, W.Sat, W.Vib
            if hasTransparency then state.Transparency = W.Transparency end
            PreviewBtn.BackgroundColor3 = cur
            PreviewBtn.BackgroundTransparency = hasTransparency and state.Transparency or 0
            ConfigObjects[controlId].Value = { Color = cur, Transparency = state.Transparency }
            pcall(callback, cur, state.Transparency)
            CloseDialog()
        end, "right")

        Tween(Overlay, {BackgroundTransparency = 0.35}, 0.15)
        MainContainer.Visible = true
        Tween(MainContainer, {ImageTransparency = 0}, 0.15)
        task.spawn(function()
            task.wait(0.05)
            Main.Visible = true
        end)
    end

    PreviewBtn.MouseButton1Click:Connect(OpenColorpicker)

    ConfigObjects[controlId] = {
        Type = "Colorpicker",
        Value = { Color = state.Default, Transparency = state.Transparency },
        Get = function()
            return { Color = state.Default, Transparency = state.Transparency }
        end,
        Set = function(val)
            if locked then return end
            if type(val) == "table" and val.Color then
                state.Default = val.Color
                state.Hue, state.Sat, state.Vib = Color3.toHSV(val.Color)
                if val.Transparency ~= nil then state.Transparency = val.Transparency end
            elseif typeof(val) == "Color3" then
                state.Default = val
                state.Hue, state.Sat, state.Vib = Color3.toHSV(val)
            end
            PreviewBtn.BackgroundColor3 = state.Default
            PreviewBtn.BackgroundTransparency = hasTransparency and state.Transparency or 0
            ConfigObjects[controlId].Value = { Color = state.Default, Transparency = state.Transparency }
            pcall(callback, state.Default, state.Transparency)
        end,
    }

    local self = {}
    function self.GetValue() return state.Default, state.Transparency end
    function self.SetValue(col, tr)
        if locked then return end
        if col then
            state.Default = col
            state.Hue, state.Sat, state.Vib = Color3.toHSV(col)
        end
        if tr ~= nil then state.Transparency = tr end
        PreviewBtn.BackgroundColor3 = state.Default
        PreviewBtn.BackgroundTransparency = hasTransparency and state.Transparency or 0
        ConfigObjects[controlId].Value = { Color = state.Default, Transparency = state.Transparency }
        pcall(callback, state.Default, state.Transparency)
    end
    function self.SetVisible(v) Tile.Visible = v end
    function self.Lock(title)
        locked = true; lockFrame.Visible = true; PreviewBtn.Active = false
        if title then lockLabel.Text = title; lockedTitle = title end
    end
    function self.Unlock() locked = false; lockFrame.Visible = false; PreviewBtn.Active = true end
    function self.IsLocked() return locked end
    function self.Destroy() Tile:Destroy(); ConfigObjects[controlId] = nil end
    return self
end

    child.UserFrame = function(_, config)
        config = safeConfig(config)
        local name         = config.Name    or "用户"
        local profile      = config.Profile or ""
        local expires      = config.Expires or ""
        local parent       = config.Parent  or contentHolder
        local buttonIcon   = config.ButtonIcon
        local names        = config.Names        or { "输入框 1", "输入框 2" }
        local placeholders = config.Placeholders or { "", "" }
        local defaults     = config.Defaults     or { "", "" }
        local onChanged    = config.OnChanged

        local TOP_H = 60
        local ROW_H = 42
        local GAP   = 4
        local EXPANDED_H = GAP + ROW_H + GAP + ROW_H + GAP

        local UserFrame = Instance.new("Frame")
        UserFrame.Size = UDim2.new(1, 0, 0, TOP_H)
        UserFrame.BackgroundTransparency = 1
        UserFrame.BorderSizePixel = 0
        UserFrame.ClipsDescendants = true
        UserFrame.Parent = parent

        local TopBar = Instance.new("Frame")
        TopBar.Size = UDim2.new(1, 0, 0, TOP_H)
        TopBar.BackgroundTransparency = 1
        TopBar.BorderSizePixel = 0
        TopBar.Parent = UserFrame

        local LogoImage = Instance.new("ImageLabel")
        LogoImage.Size = UDim2.fromOffset(45, 45)
        LogoImage.Position = UDim2.fromOffset(10, 7)
        LogoImage.BackgroundTransparency = 1
        LogoImage.Image = (profile ~= "" and profile) or "rbxasset://textures/ui/clb_robux_20@3x.png"
        LogoImage.Parent = TopBar
        Instance.new("UICorner", LogoImage).CornerRadius = UDim.new(1, 0)

        local UserLabel = Instance.new("TextLabel")
        UserLabel.Size = UDim2.new(1, -110, 0, 15)
        UserLabel.Position = UDim2.new(0, 65, 0, 12)
        UserLabel.BackgroundTransparency = 1
        UserLabel.Font = Enum.Font.GothamMedium
        UserLabel.Text = name
        UserLabel.TextColor3 = CurrentTheme.Text
        UserLabel.TextSize = 13
        UserLabel.TextTransparency = 0.2
        UserLabel.TextXAlignment = Enum.TextXAlignment.Left
        UserLabel.TextTruncate = Enum.TextTruncate.AtEnd
        UserLabel.Parent = TopBar
        AddToRegistry(UserLabel, "TextColor3", "Text")

        local UserStatusLabel = Instance.new("TextLabel")
        UserStatusLabel.Size = UDim2.new(1, -110, 0, 15)
        UserStatusLabel.Position = UDim2.new(0, 65, 0, 27)
        UserStatusLabel.BackgroundTransparency = 1
        UserStatusLabel.Font = Enum.Font.GothamMedium
        UserStatusLabel.Text = expires
        UserStatusLabel.TextColor3 = CurrentTheme.Text
        UserStatusLabel.TextSize = 13
        UserStatusLabel.TextTransparency = 0.2
        UserStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
        UserStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
        UserStatusLabel.Parent = TopBar
        AddToRegistry(UserStatusLabel, "TextColor3", "Text")
        TextGradient:Skip(UserStatusLabel)

        local Btn, BtnIcon = nil, nil
        if buttonIcon and tostring(buttonIcon) ~= "" then
            Btn = Instance.new("TextButton")
            Btn.Size = UDim2.new(0, 26, 0, 26)
            Btn.Position = UDim2.new(1, -10, 0, 17)
            Btn.AnchorPoint = Vector2.new(1, 0)
            Btn.BackgroundTransparency = 1
            Btn.Text = ""
            Btn.AutoButtonColor = false
            Btn.Parent = TopBar

            BtnIcon = Instance.new("ImageLabel")
            BtnIcon.Size = UDim2.new(1, -2, 1, -2)
            BtnIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
            BtnIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            BtnIcon.BackgroundTransparency = 1
            BtnIcon.Image = ResolveIcon(buttonIcon) or ("rbxassetid://" .. tostring(buttonIcon))
            BtnIcon.ImageColor3 = CurrentTheme.Text
            BtnIcon.ImageTransparency = 0.4
            BtnIcon.ScaleType = Enum.ScaleType.Fit
            BtnIcon.Parent = Btn
            AddToRegistry(BtnIcon, "ImageColor3", "Text")

            Btn.MouseEnter:Connect(function() Tween(BtnIcon, {ImageTransparency = 0.1}, 0.15) end)
            Btn.MouseLeave:Connect(function() Tween(BtnIcon, {ImageTransparency = 0.4}, 0.15) end)
        end

        local Expanded = Instance.new("Frame")
        Expanded.Size = UDim2.new(1, 0, 0, 0)
        Expanded.Position = UDim2.new(0, 0, 0, TOP_H)
        Expanded.BackgroundTransparency = 1
        Expanded.BorderSizePixel = 0
        Expanded.ClipsDescendants = true
        Expanded.Parent = UserFrame

        local Boxes = {}
        for i = 1, 2 do
            local Row = Instance.new("Frame")
            Row.Size = UDim2.new(1, 0, 0, ROW_H)
            Row.Position = UDim2.new(0, 0, 0, GAP + (i - 1) * (ROW_H + GAP))
            Row.BackgroundTransparency = 1
            Row.BorderSizePixel = 0
            Row.Parent = Expanded

            local Line = Instance.new("Frame")
            Line.Size = UDim2.new(1, -20, 0, 1)
            Line.Position = UDim2.new(0, 10, 1, -1)
            Line.BackgroundColor3 = CurrentTheme.Stroke
            Line.BackgroundTransparency = 0.65
            Line.BorderSizePixel = 0
            Line.Parent = Row
            AddToRegistry(Line, "BackgroundColor3", "Stroke")

            local NameLbl = Instance.new("TextLabel")
            NameLbl.Size = UDim2.new(0.6, 0, 0, 18)
            NameLbl.Position = UDim2.new(0, 15, 0, 12)
            NameLbl.BackgroundTransparency = 1
            NameLbl.Font = Enum.Font.GothamMedium
            NameLbl.TextSize = 13
            NameLbl.Text = names[i] or ("输入框 " .. i)
            NameLbl.TextXAlignment = Enum.TextXAlignment.Left
            NameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            NameLbl.Parent = Row
            AddToRegistry(NameLbl, "TextColor3", "Text")

            local BoxContainer = Instance.new("Frame")
            BoxContainer.Size = UDim2.new(0.3, 0, 0, 28)
            BoxContainer.Position = UDim2.new(0.7, -10, 0.5, -14)
            BoxContainer.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
            BoxContainer.BackgroundTransparency = 0
            BoxContainer.ClipsDescendants = true
            BoxContainer.BorderSizePixel = 0
            BoxContainer.Parent = Row
            Instance.new("UICorner", BoxContainer).CornerRadius = UDim.new(0, 6)

            local boxStroke = Instance.new("UIStroke")
            boxStroke.Thickness = 1
            boxStroke.Transparency = 0.65
            boxStroke.Color = CurrentTheme.Stroke
            boxStroke.Parent = BoxContainer
            table.insert(ThemeListeners, function() boxStroke.Color = CurrentTheme.Stroke end)

            local Box = Instance.new("TextBox")
            Box.Text = defaults[i] or ""
            Box.PlaceholderText = placeholders[i] or ""
            Box.Size = UDim2.new(1, -10, 1, 0)
            Box.Position = UDim2.new(0, 5, 0, 0)
            Box.Font = Enum.Font.GothamBold
            Box.TextSize = 13
            Box.TextXAlignment = Enum.TextXAlignment.Left
            Box.ClearTextOnFocus = false
            Box.BackgroundTransparency = 1
            Box.TextColor3 = CurrentTheme.Accent
            Box.Parent = BoxContainer
            AddToRegistry(Box, "TextColor3", "Accent")
            TextGradient:Skip(Box)

            Box.Focused:Connect(function() Tween(boxStroke, {Transparency = 0.2}, 0.15) end)
            Box.FocusLost:Connect(function() Tween(boxStroke, {Transparency = 0.65}, 0.15) end)

            Box:GetPropertyChangedSignal("Text"):Connect(function()
                local txt = Box.Text
                if i == 1 then
                    UserLabel.Text = txt
                elseif i == 2 then
                    UserStatusLabel.Text = txt
                end
                if onChanged then pcall(onChanged, i, txt) end
            end)

            Boxes[i] = Box
        end

        local opened = false
        local function toggle()
            opened = not opened
            local targetH = opened and EXPANDED_H or 0
            Tween(Expanded, {Size = UDim2.new(1, 0, 0, targetH)}, 0.28)
            Tween(UserFrame, {Size = UDim2.new(1, 0, 0, TOP_H + targetH)}, 0.28)
            if BtnIcon then
                Tween(BtnIcon, {Rotation = opened and 180 or 0}, 0.28)
            end
        end

        if Btn then Btn.MouseButton1Click:Connect(toggle) end

        local self = {}
        function self:SetUsername(n)
            local t = tostring(n or "")
            if Boxes[2] then Boxes[2].Text = t end
            UserStatusLabel.Text = t
        end
        function self:SetExpires(e)
            local t = tostring(e or "")
            if Boxes[1] then Boxes[1].Text = t end
            UserLabel.Text = t
        end
        function self:SetProfile(p) LogoImage.Image = p or "rbxasset://textures/ui/clb_robux_20@3x.png" end
        function self:SetVisible(v) UserFrame.Visible = v ~= false end
        function self:GetValue(idx) return Boxes[idx] and Boxes[idx].Text or "" end
        function self:SetValue(idx, text) if Boxes[idx] then Boxes[idx].Text = tostring(text or "") end end
        function self:GetOpened() return opened end
        function self:SetOpened(v)
            v = v == true
            if v ~= opened then toggle() end
        end
        return self
    end


child.CodeBlock = function(_, config)
    config = safeConfig(config)

    local codeName    = config.Name or "Code"
    local codeText    = tostring(config.Code or "")
    local richText    = config.RichText == true
    local copyEnabled = config.Copy ~= false
    local copyText    = config.CopyText or "Copy"
    local locked      = config.Locked == true
    local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
    local parent      = config.Parent or contentHolder
    local controlId   = NewConfigId("CodeBlock", codeName)

    local CodeFrame   = Instance.new("Frame")
    local UICorner    = Instance.new("UICorner")
    local CodeLabel   = Instance.new("TextLabel")
    local CodeCorner  = Instance.new("UICorner")
    local CodePadding = Instance.new("UIPadding")
    local CopyButton  = Instance.new("Frame")
    local CopyCorner  = Instance.new("UICorner")
    local CopyStroke  = Instance.new("UIStroke")
    local CopyIcon    = Instance.new("ImageLabel")
    local LineFrame   = Instance.new("Frame")

    CodeFrame.Name = "CodeBlock_Frame"
    CodeFrame.Parent = parent
    CodeFrame.BackgroundColor3 = CurrentTheme.Main
    CodeFrame.BackgroundTransparency = 1.000
    CodeFrame.BorderSizePixel = 0
    CodeFrame.ClipsDescendants = true
    CodeFrame.Size = UDim2.new(1, 0, 0, 60)
    AddToRegistry(CodeFrame, "BackgroundColor3", "Main")

    UICorner.CornerRadius = UDim.new(0, 10)
    UICorner.Parent = CodeFrame

    CodeLabel.Name = "CodeBlock_Label"
    CodeLabel.Parent = CodeFrame
    CodeLabel.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
    CodeLabel.BackgroundTransparency = 0.150
    CodeLabel.BorderSizePixel = 0
    CodeLabel.Position = UDim2.new(0, 10, 0, 7)
    CodeLabel.Size = UDim2.new(1, -20, 0, 40)
    CodeLabel.Font = Enum.Font.Code
    CodeLabel.RichText = richText
    CodeLabel.Text = codeText
    CodeLabel.TextColor3 = CurrentTheme.Text
    CodeLabel.TextSize = 12.000
    CodeLabel.TextTransparency = 0.200
    CodeLabel.TextWrapped = true
    CodeLabel.TextXAlignment = Enum.TextXAlignment.Left
    CodeLabel.TextYAlignment = Enum.TextYAlignment.Top
    AddToRegistry(CodeLabel, "TextColor3", "Text")
    TextGradient:Skip(CodeLabel)

    CodeCorner.CornerRadius = UDim.new(0, 5)
    CodeCorner.Parent = CodeLabel

    CodePadding.PaddingTop    = UDim.new(0, 7)
    CodePadding.PaddingBottom = UDim.new(0, 7)
    CodePadding.PaddingLeft   = UDim.new(0, 7)
    CodePadding.PaddingRight  = UDim.new(0, copyEnabled and 35 or 7)
    CodePadding.Parent = CodeLabel

    CopyButton.Name = "CodeBlock_CopyButton"
    CopyButton.Parent = CodeFrame
    CopyButton.AnchorPoint = Vector2.new(1, 0)
    CopyButton.BackgroundColor3 = CurrentTheme.Element or Color3.fromRGB(26, 28, 36)
    CopyButton.BackgroundTransparency = copyEnabled and 0.100 or 1
    CopyButton.BorderSizePixel = 0
    CopyButton.ClipsDescendants = true
    CopyButton.Position = UDim2.new(1, -16, 0, 13)
    CopyButton.Size = UDim2.new(0, 24, 0, 24)
    CopyButton.Visible = copyEnabled
    CopyButton.ZIndex = 12
    AddToRegistry(CopyButton, "BackgroundColor3", "Element")

    CopyCorner.CornerRadius = UDim.new(0, 5)
    CopyCorner.Parent = CopyButton

    CopyStroke.Transparency = 0.650
    CopyStroke.Color = CurrentTheme.Stroke
    CopyStroke.Parent = CopyButton
    table.insert(ThemeListeners, function() CopyStroke.Color = CurrentTheme.Stroke end)

    CopyIcon.Name = "CodeBlock_CopyIcon"
    CopyIcon.Parent = CopyButton
    CopyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    CopyIcon.BackgroundTransparency = 1
    CopyIcon.BorderSizePixel = 0
    CopyIcon.Position = UDim2.fromScale(0.5, 0.5)
    CopyIcon.Size = UDim2.new(0, 15, 0, 15)
    CopyIcon.ZIndex = 13
    CopyIcon.Image = "rbxassetid://103287906385313"
    CopyIcon.ImageColor3 = CurrentTheme.Text
    CopyIcon.ImageTransparency = 0.250
    CopyIcon.ScaleType = Enum.ScaleType.Fit
    AddToRegistry(CopyIcon, "ImageColor3", "Text")

    LineFrame.Name = "CodeBlock_Line"
    LineFrame.Parent = CodeFrame
    LineFrame.AnchorPoint = Vector2.new(0.5, 1)
    LineFrame.BackgroundColor3 = CurrentTheme.Stroke
    LineFrame.BackgroundTransparency = 0.650
    LineFrame.BorderSizePixel = 0
    LineFrame.Position = UDim2.new(0.5, 0, 1, 0)
    LineFrame.Size = UDim2.new(1, -20, 0, 1)
    AddToRegistry(LineFrame, "BackgroundColor3", "Stroke")

    local function UpdateCodeSize()
        if not CodeFrame.Parent then return end
        local Width = math.max(120, CodeFrame.AbsoluteSize.X - 32)
        local Size = TextService:GetTextSize(
            CodeLabel.Text, CodeLabel.TextSize, CodeLabel.Font,
            Vector2.new(Width, math.huge)
        )
        local Height = math.max(40, Size.Y + 14)
        CodeLabel.Size = UDim2.new(1, -20, 0, Height)
        CodeFrame.Size = UDim2.new(1, 0, 0, Height + 15)
    end

    local function GetClipboardWriter()
        return setclipboard or toclipboard or set_clipboard or (syn and syn.write_clipboard) or nil
    end

    local ICON_COPY  = "rbxassetid://103287906385313"
    local ICON_CHECK = "rbxassetid://10709790644"

    local function Copy()
        local Writer = GetClipboardWriter()
        if not Writer then
            CopyIcon.Image = ICON_COPY
            return false
        end
        local Success = pcall(function() Writer(codeText) end)
        CopyIcon.Image = Success and ICON_CHECK or ICON_COPY
        task.delay(0.85, function()
            if CopyIcon and CopyIcon.Parent then
                CopyIcon.Image = ICON_COPY
            end
        end)
        return Success
    end

    local CopyInput = Instance.new("TextButton")
    CopyInput.Name = "CodeBlock_CopyInput"
    CopyInput.Size = UDim2.fromScale(1, 1)
    CopyInput.BackgroundTransparency = 1
    CopyInput.Text = ""
    CopyInput.AutoButtonColor = false
    CopyInput.Parent = CopyButton
    CopyInput.MouseButton1Click:Connect(Copy)

    CopyInput.MouseEnter:Connect(function()
        Tween(CopyButton, { BackgroundTransparency = 0 }, 0.175)
        Tween(CopyIcon, { ImageTransparency = 0 }, 0.175)
    end)
    CopyInput.MouseLeave:Connect(function()
        Tween(CopyButton, { BackgroundTransparency = 0.100 }, 0.175)
        Tween(CopyIcon, { ImageTransparency = 0.250 }, 0.175)
    end)

    local lockFrame, lockLabel = createLockOverlay(CodeFrame, lockedTitle)
    lockFrame.Visible = locked
    local function updateLock(state)
        locked = state
        lockFrame.Visible = state
    end

    task.defer(UpdateCodeSize)
    CodeFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateCodeSize)

    ConfigObjects[controlId] = {
        Type = "CodeBlock",
        Value = codeText,
        Get = function() return codeText end,
        Set = function(v)
            if locked then return end
            codeText = tostring(v or "")
            CodeLabel.Text = codeText
            UpdateCodeSize()
        end,
    }

    local self = {}
    function self:Copy()
        return Copy()
    end
    function self:SetCode(code)
        codeText = tostring(code or "")
        CodeLabel.Text = codeText
        ConfigObjects[controlId].Value = codeText
        UpdateCodeSize()
        return self
    end
    function self:GetCode()
        return codeText
    end
    function self:SetRichText(value)
        richText = value == true
        CodeLabel.RichText = richText
        UpdateCodeSize()
        return self
    end
    function self:SetVisible(value)
        CodeFrame.Visible = value ~= false
        return self
    end
    function self:SetCopyEnabled(value)
        copyEnabled = value == true
        CopyButton.Visible = copyEnabled
        CodePadding.PaddingRight = UDim.new(0, copyEnabled and 35 or 7)
        return self
    end
    function self:SetCopyText(value)
        copyText = tostring(value or "Copy")
        return self
    end
    function self:Lock(title)
        updateLock(true)
        if title then lockLabel.Text = title; lockedTitle = title end
        return self
    end
    function self:Unlock()
        updateLock(false)
        return self
    end
    function self:IsLocked()
        return locked
    end
    function self:Destroy()
        CodeFrame:Destroy()
        ConfigObjects[controlId] = nil
    end
    return self
end

    child.Video = function(_, config)
        config = safeConfig(config)
        local opts = config or {}
        local parent = opts.Parent or contentHolder
        if not parent then return end
        local radius = opts.Radius or 8
        local src = opts.Video or ""
        local looped = opts.Looped ~= false
        local vol = opts.Volume or 0
        local auto = opts.AutoPlay ~= false
        local aspect = opts.AspectRatio or "16:9"
        local function resolveMedia(s)
            if type(s) ~= "string" or s == "" then return "" end
            if s:match("^rbxassetid://") or s:match("^rbxasset://") then return s end
            if s:match("^%d+$") then return "rbxassetid://"..s end
            if s:match("^https?://") then return MediaManager:Video(s) end
            return ""
        end
        local function applyIcon(imgLabel, iconName)
            if not imgLabel then return end
            local imageMap = {play="rbxassetid://10734923549", pause="rbxassetid://10734919336", stop="rbxassetid://10734972621", volume="rbxassetid://10747376008", external="rbxassetid://10747366266"}
            imgLabel.Image = imageMap[iconName] or ""
        end
        local function parseRatio(r)
            if type(r) == "number" then return r end
            if type(r) == "string" then
                local rw, rh = r:match("(%d+):(%d+)")
                if rw and rh and tonumber(rh) ~= 0 then return tonumber(rw)/tonumber(rh) end
            end
            return 16/9
        end
        local ratioNum = parseRatio(aspect)
        local wrap = Instance.new("Frame")
        wrap.Size = UDim2.new(1,-16,0,180)
        wrap.BackgroundColor3 = CurrentTheme.Main
        wrap.BackgroundTransparency = 0.6
        wrap.BorderSizePixel = 0; wrap.ClipsDescendants = true
        wrap.Parent = parent
        AddToRegistry(wrap, "BackgroundColor3", "Main")
        local function recalcAspect()
            local w = wrap.AbsoluteSize.X
            if w > 0 and ratioNum and ratioNum > 0 then
                wrap.Size = UDim2.new(1,-16,0,math.floor(w/ratioNum))
            end
        end
        wrap:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalcAspect)
        defer(recalcAspect)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0,radius); corner.Parent = wrap
        local resolved = resolveMedia(src)
        local hasVideo = (resolved ~= "")
        local vid = nil
        if hasVideo then
            local vfOk, vf = pcall(Instance.new, "VideoFrame")
            if vfOk and vf then
                vid = vf
                vid.Size = UDim2.fromScale(1,1)
                vid.BackgroundTransparency = 1
                vid.Looped = looped; vid.Volume = vol
                vid.ZIndex = 1; vid.Video = resolved; vid.Parent = wrap
                local vidCorner = Instance.new("UICorner")
                vidCorner.CornerRadius = UDim.new(0,radius); vidCorner.Parent = vid
            else
                hasVideo = false
            end
        end
        local placeholder = Instance.new("Frame")
        placeholder.Size = UDim2.fromScale(1,1)
        placeholder.BackgroundTransparency = 1
        placeholder.Visible = not hasVideo
        placeholder.ZIndex = 2; placeholder.Parent = wrap
        local phImg = Instance.new("ImageLabel")
        phImg.Size = UDim2.fromOffset(32,32)
        phImg.Position = UDim2.new(0.5,0,0.5,-14)
        phImg.AnchorPoint = Vector2.new(0.5,0.5)
        phImg.BackgroundTransparency = 1
        phImg.ImageTransparency = 0.4
        phImg.ZIndex = 3; phImg.Parent = placeholder
        AddToRegistry(phImg, "ImageColor3", "SubText")
        applyIcon(phImg, "play")
        local phText = Instance.new("TextLabel")
        phText.Size = UDim2.new(1,0,0,16)
        phText.Position = UDim2.new(0,0,0.5,20)
        phText.AnchorPoint = Vector2.new(0,0)
        phText.BackgroundTransparency = 1
        phText.Text = "视频不可用"
        phText.TextSize = 11
        phText.Font = Enum.Font.GothamMedium
        phText.TextTransparency = 0.5
        phText.ZIndex = 3; phText.Parent = placeholder
        AddToRegistry(phText, "TextColor3", "SubText")
        if not hasVideo then
            local mod = {Frame=wrap, Type="Video", VideoFrame=nil}
            function mod:Destroy() wrap:Destroy() end
            function mod:SetVideo(s) end
            function mod:SetVolume(v) end
            function mod:Play() end
            function mod:Pause() end
            function mod:Stop() end
            function mod:SetAspectRatio(r) end
            return mod
        end
        local cgOk, overlay = pcall(Instance.new, "CanvasGroup")
        if not cgOk or not overlay then
            if vid then vid:Destroy() vid = nil end
            placeholder.Visible = true
            local mod = {Frame=wrap, Type="Video", VideoFrame=nil}
            function mod:Destroy() wrap:Destroy() end
            function mod:SetVideo(s) end
            function mod:SetVolume(v) end
            function mod:Play() end
            function mod:Pause() end
            function mod:Stop() end
            function mod:SetAspectRatio(r) end
            return mod
        end
        overlay.Size = UDim2.new(1,0,0,54)
        overlay.Position = UDim2.new(0,0,1,0)
        overlay.AnchorPoint = Vector2.new(0,1)
        overlay.BackgroundTransparency = 1
        overlay.GroupTransparency = 1
        overlay.ZIndex = 5; overlay.Parent = wrap
        local gradFr = Instance.new("Frame")
        gradFr.Size = UDim2.fromScale(1,1)
        gradFr.BackgroundColor3 = Color3.fromRGB(0,0,0)
        gradFr.BackgroundTransparency = 0
        gradFr.BorderSizePixel = 0
        gradFr.ZIndex = 5; gradFr.Parent = overlay
        local grad = Instance.new("UIGradient")
        grad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1)})
        grad.Rotation = 90; grad.Parent = gradFr
        local seekRow = Instance.new("Frame")
        seekRow.Size = UDim2.new(1,-12,0,16)
        seekRow.Position = UDim2.new(0,6,0,4)
        seekRow.BackgroundTransparency = 1
        seekRow.ZIndex = 6; seekRow.Parent = overlay
        local timeCur = Instance.new("TextLabel")
        timeCur.Size = UDim2.fromOffset(36,16)
        timeCur.BackgroundTransparency = 1
        timeCur.Text = "0:00"; timeCur.TextSize = 10
        timeCur.Font = Enum.Font.GothamMedium
        timeCur.TextColor3 = Color3.fromRGB(220,220,220)
        timeCur.ZIndex = 7; timeCur.Parent = seekRow
        TextGradient:Skip(timeCur)
        local seekContainer = Instance.new("Frame")
        seekContainer.Size = UDim2.new(1,-84,0,16)
        seekContainer.Position = UDim2.fromOffset(40,0)
        seekContainer.BackgroundTransparency = 1
        seekContainer.ZIndex = 6; seekContainer.Parent = seekRow
        local seekRail = Instance.new("TextButton")
        seekRail.Size = UDim2.new(1,0,0,5)
        seekRail.Position = UDim2.new(0,0,0.5,-2)
        seekRail.BackgroundColor3 = Color3.fromRGB(80,80,90)
        seekRail.BorderSizePixel = 0
        seekRail.ZIndex = 7; seekRail.Text = ""
        seekRail.AutoButtonColor = false; seekRail.Parent = seekContainer
        Instance.new("UICorner", seekRail).CornerRadius = UDim.new(1,0)
        local seekFill = Instance.new("Frame")
        seekFill.Size = UDim2.new(0,0,1,0)
        seekFill.BackgroundColor3 = CurrentTheme.Accent
        seekFill.BorderSizePixel = 0
        seekFill.ZIndex = 8; seekFill.Parent = seekRail
        Instance.new("UICorner", seekFill).CornerRadius = UDim.new(1,0)
        local seekKnob = Instance.new("Frame")
        seekKnob.Size = UDim2.fromOffset(12,12)
        seekKnob.Position = UDim2.new(0,0,0.5,0)
        seekKnob.AnchorPoint = Vector2.new(0.5,0.5)
        seekKnob.BackgroundColor3 = Color3.fromRGB(255,255,255)
        seekKnob.BorderSizePixel = 0
        seekKnob.ZIndex = 9; seekKnob.Parent = seekRail
        Instance.new("UICorner", seekKnob).CornerRadius = UDim.new(1,0)
        local timeDur = Instance.new("TextLabel")
        timeDur.Size = UDim2.fromOffset(36,16)
        timeDur.Position = UDim2.new(1,-36,0,0)
        timeDur.BackgroundTransparency = 1
        timeDur.Text = "0:00"; timeDur.TextSize = 10
        timeDur.Font = Enum.Font.GothamMedium
        timeDur.TextColor3 = Color3.fromRGB(160,160,170)
        timeDur.ZIndex = 7; timeDur.Parent = seekRow
        TextGradient:Skip(timeDur)
        local ctrlRow = Instance.new("Frame")
        ctrlRow.Size = UDim2.new(1,-12,0,26)
        ctrlRow.Position = UDim2.new(0,6,0,24)
        ctrlRow.BackgroundTransparency = 1
        ctrlRow.ZIndex = 6; ctrlRow.Parent = overlay
        local function ctrlBtn(iconName, cb)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromOffset(22,22)
            btn.BackgroundTransparency = 1; btn.Text = ""
            btn.ZIndex = 7; btn.AutoButtonColor = false; btn.Parent = ctrlRow
            local ic = Instance.new("ImageLabel")
            ic.Size = UDim2.fromOffset(16,16)
            ic.Position = UDim2.new(0.5,0,0.5,0)
            ic.AnchorPoint = Vector2.new(0.5,0.5)
            ic.BackgroundTransparency = 1; ic.ZIndex = 8; ic.Parent = btn
            AddToRegistry(ic, "ImageColor3", "Text")
            applyIcon(ic, iconName)
            btn.MouseButton1Click:Connect(function() pcall(cb) end)
            return btn, ic
        end
        local playing = auto
        local playBtn, playIco = ctrlBtn("play", function() end)
        local pauseBtn, pauseIco = ctrlBtn("pause", function() end)
        local stopBtn, stopIco = ctrlBtn("stop", function() end)
        local volIco = Instance.new("ImageLabel")
        volIco.Size = UDim2.fromOffset(14,14)
        volIco.Position = UDim2.fromOffset(68,4)
        volIco.BackgroundTransparency = 1; volIco.ZIndex = 7; volIco.Parent = ctrlRow
        AddToRegistry(volIco, "ImageColor3", "SubText")
        applyIcon(volIco, "volume")
        local volLbl = Instance.new("TextLabel")
        volLbl.Size = UDim2.fromOffset(32,22)
        volLbl.Position = UDim2.fromOffset(84,0)
        volLbl.BackgroundTransparency = 1
        volLbl.Text = tostring(math.floor(vol*100)).."%"
        volLbl.TextSize = 10
        volLbl.Font = Enum.Font.Gotham
        volLbl.ZIndex = 7; volLbl.Parent = ctrlRow
        AddToRegistry(volLbl, "TextColor3", "SubText")
        TextGradient:Skip(volLbl)
        local btnLayout = Instance.new("UIListLayout")
        btnLayout.FillDirection = Enum.FillDirection.Horizontal
        btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        btnLayout.Padding = UDim.new(0,2); btnLayout.Parent = ctrlRow
        local ctrlVisible = false
        local fadeTimer = 0
        local function showOverlay()
            ctrlVisible = true; fadeTimer = 3
            Tween(overlay, {GroupTransparency=0}, 0.18)
        end
        local function hideOverlay()
            ctrlVisible = false
            Tween(overlay, {GroupTransparency=1}, 0.3)
        end
        local vidClickBtn = Instance.new("TextButton")
        vidClickBtn.Size = UDim2.fromScale(1,1)
        vidClickBtn.BackgroundTransparency = 1
        vidClickBtn.Text = ""; vidClickBtn.ZIndex = 4
        vidClickBtn.AutoButtonColor = false; vidClickBtn.Parent = wrap
        vidClickBtn.MouseButton1Click:Connect(function()
            if ctrlVisible then fadeTimer = 3 else showOverlay() end
        end)
        local function resetFade() fadeTimer = 3 end
        playBtn.MouseButton1Click:Connect(function()
            if vid then pcall(function() vid:Play() end) end
            playing = true; playBtn.Visible = false; pauseBtn.Visible = true; resetFade()
        end)
        pauseBtn.MouseButton1Click:Connect(function()
            if vid then pcall(function() vid:Pause() end) end
            playing = false; playBtn.Visible = true; pauseBtn.Visible = false; resetFade()
        end)
        stopBtn.MouseButton1Click:Connect(function()
            if vid then pcall(function() vid:Stop() end) end
            playing = false; playBtn.Visible = true; pauseBtn.Visible = false; resetFade()
        end)
        pauseBtn.Visible = auto; playBtn.Visible = not auto
        local seeking = false
        local function vidSeek(posX)
            resetFade()
            local rx = seekRail.AbsolutePosition.X
            local rw = seekRail.AbsoluteSize.X
            local pct = math.clamp((posX-rx)/rw,0,1)
            seekFill.Size = UDim2.new(pct,0,1,0)
            seekKnob.Position = UDim2.new(pct,0,0.5,0)
            if vid and vid.TimeLength and vid.TimeLength>0 then
                pcall(function() vid.TimePosition = vid.TimeLength * pct end)
            end
        end
        seekRail.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
                seeking = true
                vidSeek(inp.Position.X)
                resetFade()
                inp.Changed:Connect(function()
                    if inp.UserInputState==Enum.UserInputState.End then seeking = false end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if seeking and (inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch) then
                vidSeek(inp.Position.X)
            end
        end)
        local function fmtTime(s) s = math.max(0, math.floor(s or 0)); return string.format("%d:%02d", math.floor(s/60), s%60) end
        local hbConn = RunService.Heartbeat:Connect(function(dt)
            if not wrap.Parent then return end
            if ctrlVisible then
                fadeTimer = fadeTimer - dt
                if fadeTimer <= 0 and not seeking then hideOverlay() end
            end
            if not vid then return end
            local dur = vid.TimeLength or 0
            local pos = 0; pcall(function() pos = vid.TimePosition end)
            if dur > 0 and not seeking then
                local pct = math.clamp(pos/dur,0,1)
                seekFill.Size = UDim2.new(pct,0,1,0)
                seekKnob.Position = UDim2.new(pct,0,0.5,0)
            end
            timeCur.Text = fmtTime(pos)
            timeDur.Text = fmtTime(dur)
        end)
        if auto and hasVideo then
            task.spawn(function()
                task.wait(0.08)
                if vid and vid.Parent then
                    pcall(function() vid:Play() end)
                    playing = true
                    pauseBtn.Visible = true
                    playBtn.Visible = false
                end
            end)
        end
        local mod = {Frame=wrap, Type="Video", VideoFrame=vid}
        function mod:Play() if vid then pcall(function() vid:Play() end); playing=true; playBtn.Visible=false; pauseBtn.Visible=true end end
        function mod:Pause() if vid then pcall(function() vid:Pause() end); playing=false; playBtn.Visible=true; pauseBtn.Visible=false end end
        function mod:Stop() if vid then pcall(function() vid:Stop() end); playing=false; playBtn.Visible=true; pauseBtn.Visible=false end end
        function mod:SetVideo(s) if vid then local r=resolveMedia(s); if r~="" then vid.Video=r; placeholder.Visible=false else placeholder.Visible=true end end end
        function mod:SetVolume(v) if vid then vid.Volume=math.clamp(v,0,1) end; volLbl.Text=tostring(math.floor(math.clamp(v,0,1)*100)).."%" end
        function mod:SetAspectRatio(r) ratioNum=parseRatio(r); recalcAspect() end
        function mod:Destroy() safeDisconnect(hbConn); wrap:Destroy() end
        return mod
    end

    child.Audio = function(_, config)
        config = safeConfig(config)
        local opts = config or {}
        local parent = opts.Parent or contentHolder
        if not parent then return end
        local title = opts.Name or opts.Title or "音频"
        local subtitle = opts.SubName or opts.SubTitle or ""
        local src = opts.Audio or opts.Sound or ""
        local vol = (opts.Volume ~= nil) and math.clamp(opts.Volume, 0, 10) or 0.5
        local looped = opts.Looped ~= false
        local auto = opts.AutoPlay ~= false
        local playOutside = opts.PlayOutsideWindow == true
        local function resolve(s, noDownload)
            local mm = MediaManager
            if mm then return mm:Audio(s, noDownload) end
            if type(s) ~= "string" or s == "" then return "" end
            if s:match("^rbxassetid://") or s:match("^rbxasset://") then return s end
            if s:match("^%d+$") then return "rbxassetid://"..s end
            return ""
        end
        local isHttp = type(src) == "string" and src:match("^https?://")
        local resolved = isHttp and resolve(src, true) or resolve(src, false)
        local pendingDownload = isHttp and (not resolved or resolved == "")
        local hasAudio = (resolved ~= nil and resolved ~= "") or pendingDownload
        local snd = nil
        local function initSound(resolvedId)
            local s2 = Instance.new("Sound")
            s2.Name = "KGAudio"
            pcall(function() s2.SoundId = resolvedId end)
            s2.Volume = vol; s2.Looped = looped
            if playOutside then s2.RollOffMaxDistance = 10000; s2.Parent = game:GetService("SoundService")
            else s2.Parent = workspace end
            return s2
        end
        if hasAudio and not pendingDownload then snd = initSound(resolved) end
        local wrapHeight = (title ~= "" or subtitle ~= "") and 118 or 96
        local wrap = Instance.new("Frame")
        wrap.Size = UDim2.new(1, -16, 0, wrapHeight)
        wrap.BackgroundColor3 = CurrentTheme.Top
        wrap.BackgroundTransparency = 0.6; wrap.BorderSizePixel = 0
        wrap.Parent = parent
        Instance.new("UICorner", wrap).CornerRadius = UDim.new(0, 8)
        AddToRegistry(wrap, "BackgroundColor3", "Top")
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 10); padding.PaddingRight = UDim.new(0, 10)
        padding.PaddingTop = UDim.new(0, 10); padding.PaddingBottom = UDim.new(0, 10)
        padding.Parent = wrap
        local topRow = Instance.new("Frame")
        topRow.Size = UDim2.new(1, 0, 0, (title ~= "" or subtitle ~= "") and 38 or 28)
        topRow.BackgroundTransparency = 1; topRow.Parent = wrap
        local audioIcon = Instance.new("ImageLabel")
        audioIcon.Size = UDim2.fromOffset(20, 20)
        audioIcon.Position = UDim2.new(0, 0, 0.5, 0)
        audioIcon.AnchorPoint = Vector2.new(0, 0.5)
        audioIcon.BackgroundTransparency = 1
        audioIcon.Image = "rbxassetid://10747376008"
        audioIcon.ZIndex = 2; audioIcon.Parent = topRow
        AddToRegistry(audioIcon, "ImageColor3", hasAudio and "Accent" or "SubText")
        local titleHolder = Instance.new("Frame")
        titleHolder.Size = UDim2.new(1, -110, 1, 0)
        titleHolder.Position = UDim2.new(0, 28, 0, 0)
        titleHolder.BackgroundTransparency = 1
        titleHolder.ZIndex = 2; titleHolder.Parent = topRow
        local statusLbl = Instance.new("TextLabel")
        statusLbl.Size = UDim2.new(1, 0, 0, 16)
        statusLbl.Position = UDim2.new(0, 0, 0, (title ~= "" or subtitle ~= "") and 2 or 0)
        statusLbl.BackgroundTransparency = 1
        statusLbl.Text = (title ~= "" and title) or (hasAudio and "音频" or "无音频源")
        statusLbl.TextSize = (title ~= "" or subtitle ~= "") and 12 or 11
        statusLbl.Font = (title ~= "" or subtitle ~= "") and Enum.Font.GothamBold or Enum.Font.Gotham
        statusLbl.TextXAlignment = Enum.TextXAlignment.Left
        statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
        statusLbl.ZIndex = 2; statusLbl.Parent = titleHolder
        AddToRegistry(statusLbl, "TextColor3", "Text")
        if subtitle ~= "" then
            local subtitleLbl = Instance.new("TextLabel")
            subtitleLbl.Size = UDim2.new(1, 0, 0, 13)
            subtitleLbl.Position = UDim2.new(0, 0, 0, 20)
            subtitleLbl.BackgroundTransparency = 1
            subtitleLbl.Text = subtitle; subtitleLbl.TextSize = 10
            subtitleLbl.Font = Enum.Font.Gotham
            subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
            subtitleLbl.ZIndex = 2; subtitleLbl.Parent = titleHolder
            AddToRegistry(subtitleLbl, "TextColor3", "SubText")
        end
        local controls = Instance.new("Frame")
        controls.Size = UDim2.new(0, 116, 1, 0)
        controls.Position = UDim2.new(1, 0, 0, 0)
        controls.AnchorPoint = Vector2.new(1, 0)
        controls.BackgroundTransparency = 1
        controls.Visible = hasAudio; controls.Parent = topRow
        local ctrlLayout = Instance.new("UIListLayout")
        ctrlLayout.FillDirection = Enum.FillDirection.Horizontal
        ctrlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        ctrlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        ctrlLayout.Padding = UDim.new(0, 4); ctrlLayout.Parent = controls
        local function ctrlBtn(iconId, cb)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromOffset(24, 24)
            btn.BackgroundTransparency = 1; btn.Text = ""
            btn.AutoButtonColor = false; btn.ZIndex = 3; btn.Parent = controls
            local ic = Instance.new("ImageLabel")
            ic.Size = UDim2.fromOffset(16, 16)
            ic.Position = UDim2.new(0.5, 0, 0.5, 0)
            ic.AnchorPoint = Vector2.new(0.5, 0.5)
            ic.BackgroundTransparency = 1; ic.ZIndex = 4; ic.Parent = btn
            AddToRegistry(ic, "ImageColor3", "Text")
            local icons = { play = "rbxassetid://10734923549", pause = "rbxassetid://10734919336", stop = "rbxassetid://10734972621" }
            ic.Image = icons[iconId] or ""
            btn.MouseButton1Click:Connect(function() pcall(cb) end)
            return btn, ic
        end
        local playing = false
        local playBtn, pauseBtn
        if hasAudio then
            local _downloading = false
            local function _doPlay()
                if not snd then return end
                pcall(function() snd:Play() end)
                playing = true
                if playBtn then playBtn.Visible = false end
                if pauseBtn then pauseBtn.Visible = true end
            end
            local function _triggerPlay()
                if _downloading then return end
                if snd then _doPlay(); return end
                if pendingDownload then
                    _downloading = true
                    task.spawn(function()
                        local got = resolve(src, false)
                        _downloading = false
                        if got and got ~= "" then
                            pendingDownload = false
                            snd = initSound(got)
                            _doPlay()
                        end
                    end)
                end
            end
            playBtn = ctrlBtn("play", _triggerPlay)
            pauseBtn = ctrlBtn("pause", function()
                if snd then snd:Pause() end
                playing = false
                if playBtn then playBtn.Visible = true end
                if pauseBtn then pauseBtn.Visible = false end
            end)
            pauseBtn.Visible = false
            ctrlBtn("stop", function()
                if snd then pcall(function() snd:Stop(); snd.TimePosition = 0 end) end
                playing = false
                if playBtn then playBtn.Visible = true end
                if pauseBtn then pauseBtn.Visible = false end
            end)
            if auto and snd then _doPlay() end
        end
        local seekRowOffset = (title ~= "" or subtitle ~= "") and 56 or 36
        local seekRow = Instance.new("Frame")
        seekRow.Size = UDim2.new(1, 0, 0, 24)
        seekRow.Position = UDim2.new(0, 0, 0, seekRowOffset)
        seekRow.BackgroundTransparency = 1
        seekRow.Visible = hasAudio; seekRow.Parent = wrap
        local curLbl = Instance.new("TextLabel")
        curLbl.Size = UDim2.fromOffset(34, 20)
        curLbl.Position = UDim2.new(0, 0, 0.5, 0)
        curLbl.AnchorPoint = Vector2.new(0, 0.5)
        curLbl.BackgroundTransparency = 1
        curLbl.Text = "0:00"; curLbl.TextSize = 10
        curLbl.Font = Enum.Font.Gotham
        curLbl.TextXAlignment = Enum.TextXAlignment.Left
        curLbl.Parent = seekRow
        AddToRegistry(curLbl, "TextColor3", "SubText")
        TextGradient:Skip(curLbl)
        local durLbl = Instance.new("TextLabel")
        durLbl.Size = UDim2.fromOffset(34, 20)
        durLbl.Position = UDim2.new(1, 0, 0.5, 0)
        durLbl.AnchorPoint = Vector2.new(1, 0.5)
        durLbl.BackgroundTransparency = 1
        durLbl.Text = "0:00"; durLbl.TextSize = 10
        durLbl.Font = Enum.Font.Gotham
        durLbl.TextXAlignment = Enum.TextXAlignment.Right
        durLbl.Parent = seekRow
        AddToRegistry(durLbl, "TextColor3", "SubText")
        TextGradient:Skip(durLbl)
        local rail = Instance.new("Frame")
        rail.Size = UDim2.new(1, -76, 0, 4)
        rail.Position = UDim2.new(0, 38, 0.5, 0)
        rail.AnchorPoint = Vector2.new(0, 0.5)
        rail.BackgroundColor3 = CurrentTheme.SubText
        rail.BackgroundTransparency = 0.65
        rail.Parent = seekRow
        AddToRegistry(rail, "BackgroundColor3", "SubText")
        Instance.new("UICorner", rail).CornerRadius = UDim.new(1, 0)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = CurrentTheme.Accent
        fill.Parent = rail
        AddToRegistry(fill, "BackgroundColor3", "Accent")
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(12, 12)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = CurrentTheme.Accent
        knob.Parent = rail
        AddToRegistry(knob, "BackgroundColor3", "Accent")
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
        local function fmtTime(s) s = math.max(0, math.floor(s or 0)); return string.format("%d:%02d", math.floor(s/60), s%60) end
        local dragging = false
        local function seekTo(inputX)
            if not snd then return end
            local railX = rail.AbsolutePosition.X
            local railW = rail.AbsoluteSize.X
            if railW <= 0 then return end
            local pct = math.clamp((inputX - railX) / railW, 0, 1)
            local dur = snd.TimeLength or 0
            if dur > 0 then pcall(function() snd.TimePosition = pct * dur end) end
        end
        rail.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true; seekTo(inp.Position.X)
            end
        end)
        rail.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                seekTo(inp.Position.X)
            end
        end)
        local hbConn = RunService.Heartbeat:Connect(function()
            if not wrap.Parent then return end
            if not snd then return end
            local dur = snd.TimeLength or 0
            local pos = snd.TimePosition or 0
            curLbl.Text = fmtTime(pos)
            durLbl.Text = fmtTime(dur)
            local pct = dur > 0 and (pos / dur) or 0
            fill.Size = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, 0, 0.5, 0)
        end)
        local mod = { Frame = wrap, Type = "Audio", Sound = snd }
        function mod:Play() if snd then pcall(function() snd:Play() end) end end
        function mod:Pause() if snd then pcall(function() snd:Pause() end) end end
        function mod:Stop() if snd then pcall(function() snd:Stop() end) end end
        function mod:SetVolume(v) if snd then snd.Volume = math.clamp(v, 0, 10) end end
        function mod:Destroy() safeDisconnect(hbConn); if snd then pcall(function() snd:Stop(); snd:Destroy() end) end; wrap:Destroy() end
        return mod
    end

    child.Social = function(_, config)
        config = safeConfig(config)
        local parent = config.Parent or contentHolder
        if not parent then return end
        local displayName = tostring(config.Name or config.DisplayName or "")
        local subName = tostring(config.SubName or config.Subtitle or "")
        local platform = tostring(config.SmlName or config.Platform or "")
        local avatarSrc = config.Logo or config.Avatar or ""
        local copyText = tostring(config.copy or "")
        local buttonText = tostring(config.Cbn or "复制")
        if displayName == "" then displayName = "用户" end
        local wrap = Instance.new("Frame")
        wrap.Size = UDim2.new(1, 0, 0, 64)
        wrap.BackgroundTransparency = 1; wrap.BorderSizePixel = 0
        wrap.Parent = parent
        local avatarBg = Instance.new("Frame")
        avatarBg.Size = UDim2.fromOffset(42, 42)
        avatarBg.Position = UDim2.new(0, 11, 0.5, 0)
        avatarBg.AnchorPoint = Vector2.new(0, 0.5)
        avatarBg.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
        avatarBg.BorderSizePixel = 0; avatarBg.Parent = wrap
        avatarBg.ClipsDescendants = true
        Instance.new("UICorner", avatarBg).CornerRadius = UDim.new(1, 0)
        local avatarImg = Instance.new("ImageLabel")
        avatarImg.Size = UDim2.fromScale(1, 1)
        avatarImg.BackgroundTransparency = 1; avatarImg.Parent = avatarBg
        Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)
        local nameLbl = Instance.new("TextLabel")
        nameLbl.Text = displayName
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 13
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.BackgroundTransparency = 1
        nameLbl.Size = UDim2.new(1, -140, 0, 16)
        nameLbl.Position = UDim2.new(0, 62, 0, 9)
        nameLbl.Parent = wrap
        AddToRegistry(nameLbl, "TextColor3", "Text")
        if subName ~= "" then
            local subNameLbl = Instance.new("TextLabel")
            subNameLbl.Text = subName
            subNameLbl.Font = Enum.Font.Gotham
            subNameLbl.TextSize = 11
            subNameLbl.TextXAlignment = Enum.TextXAlignment.Left
            subNameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            subNameLbl.BackgroundTransparency = 1
            subNameLbl.Size = UDim2.new(1, -140, 0, 13)
            subNameLbl.Position = UDim2.new(0, 62, 0, 27)
            subNameLbl.Parent = wrap
            AddToRegistry(subNameLbl, "TextColor3", "SubText")
            TextGradient:Skip(subNameLbl)
        end
        if platform ~= "" then
            local platformLbl = Instance.new("TextLabel")
            platformLbl.Text = platform
            platformLbl.Font = Enum.Font.Gotham
            platformLbl.TextSize = 10
            platformLbl.TextTransparency = 0.3
            platformLbl.TextXAlignment = Enum.TextXAlignment.Left
            platformLbl.BackgroundTransparency = 1
            platformLbl.Size = UDim2.new(1, -140, 0, 12)
            platformLbl.Position = UDim2.new(0, 62, 0, subName ~= "" and 42 or 27)
            platformLbl.Parent = wrap
            AddToRegistry(platformLbl, "TextColor3", "SubText")
            TextGradient:Skip(platformLbl)
        end
        if copyText ~= "" then
            local copyBtn = Instance.new("TextButton")
            copyBtn.Text = buttonText
            copyBtn.Size = UDim2.fromOffset(52, 26)
            copyBtn.Position = UDim2.new(1, -11, 0.5, 0)
            copyBtn.AnchorPoint = Vector2.new(1, 0.5)
            copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            copyBtn.Font = Enum.Font.GothamMedium
            copyBtn.TextSize = 12
            copyBtn.BackgroundColor3 = Color3.fromRGB(39, 40, 49)
            copyBtn.BorderSizePixel = 0; copyBtn.Parent = wrap
            Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 8)
            copyBtn.MouseButton1Click:Connect(function()
                pcall(function() toclipboard(copyText) end)
            end)
        end
        task.spawn(function()
            local imgUrl = nil
            if avatarSrc ~= "" then
                if avatarSrc:match("^rbxassetid://") or avatarSrc:match("^rbxasset://") or avatarSrc:match("^http") then
                    imgUrl = avatarSrc
                elseif tonumber(avatarSrc) then
                    imgUrl = "rbxassetid://"..avatarSrc
                end
            end
            if imgUrl and imgUrl ~= "" then
                local ok, asset = pcall(function() return MediaManager:Image(imgUrl) end)
                if ok and asset and asset ~= "" then avatarImg.Image = asset end
            end
        end)
        local mod = { Frame = wrap, Type = "Social" }
        function mod:SetName(n) displayName = tostring(n or ""); nameLbl.Text = displayName end
        function mod:Destroy() wrap:Destroy() end
        return mod
    end

    child.AddCenterTabbox = function(self, name)
        return self:Tabbox({ Name = name })
    end

    local functions = {}
    for k, v in pairs(child) do functions[k] = v end

    local function createSection(_, config)
        if type(config) == "string" then config = { Name = config }
        elseif type(config) ~= "table" then config = {} end

        local tabEntries = {}
        for i = 1, #config do
            local entry = config[i]
            if type(entry) == "table" and entry.Key ~= nil then
                table.insert(tabEntries, entry)
            end
        end
        local hasTabs = #tabEntries > 0

        local sectionTitle    = config.Name or config.Title or ""
        local sectionSubtitle = config.SubName or config.Subtitle or ""
        local sectionIcon     = config.Logo or config.Icon or nil
        local collapsible     = config.Collapsible == true
        local collapsed       = collapsible and (config.Collapsed == false)
        local locked      = config.Locked == true
        local lockedTitle = config.TextLocked or config.LockMessage or "已锁定"
        local hasTitle    = (sectionTitle ~= "")
        local hasSubtitle = (sectionSubtitle ~= "")
        local hasIcon     = (sectionIcon ~= nil)
        local hasHeader   = hasTitle or hasSubtitle or hasIcon
        local HEADER_LEFT = 12
        local ARROW_W     = collapsible and 26 or 0
        local ICON_SIZE = hasSubtitle and 40 or 32
        local TITLE_SIZE = 15
        local TITLE_H    = 20
        local SUB_SIZE = 12
        local SUB_H    = 16
        local SUB_GAP  = 2
        local HEADER_H
        if hasHeader then HEADER_H = hasSubtitle and 56 or 44 else HEADER_H = 4 end
        local COLLAPSED_H
        if hasSubtitle then COLLAPSED_H = 50
        elseif hasHeader then COLLAPSED_H = 40
        else COLLAPSED_H = collapsible and 40 or 4 end
        local CONTENT_TOP = hasHeader and (HEADER_H + 4) or 4
        local ICON_TOP       = math.floor((COLLAPSED_H - ICON_SIZE) / 2)
        local TEXT_BLOCK_H   = hasSubtitle and (TITLE_H + SUB_GAP + SUB_H) or TITLE_H
        local TEXT_BLOCK_TOP = math.floor((COLLAPSED_H - TEXT_BLOCK_H) / 2)
        local TITLE_TOP      = TEXT_BLOCK_TOP
        local SUB_TOP        = TEXT_BLOCK_TOP + TITLE_H + SUB_GAP
        local ARROW_TOP      = math.floor((COLLAPSED_H - 18) / 2)
        local MIUI_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quart)

        local sectionFrame = Instance.new("Frame")
        sectionFrame.Size = UDim2.new(1, -5, 0, 0)
        sectionFrame.AnchorPoint = Vector2.new(0, 0)
        sectionFrame.Position = UDim2.new(0, 0, 0, 0)
        sectionFrame.BackgroundTransparency = 1
        sectionFrame.ClipsDescendants = true; sectionFrame.Parent = parent

        local contentContainer = Instance.new("Frame")
        contentContainer.Size = UDim2.new(1, -5, 0, 0)
        contentContainer.Position = UDim2.new(0, 0, 0, 0)
        contentContainer.AnchorPoint = Vector2.new(0, 0)
        contentContainer.BackgroundTransparency = 0.5
        contentContainer.ClipsDescendants = true
        contentContainer.Parent = sectionFrame
        AddToRegistry(contentContainer, "BackgroundColor3", "Main")

        local contentStroke = Instance.new("UIStroke")
        contentStroke.Thickness = 1; contentStroke.Transparency = 0.65
        contentStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        contentStroke.Parent = contentContainer
        AddToRegistry(contentStroke, "Color", "Stroke")

        local contentCorner = Instance.new("UICorner")
        contentCorner.CornerRadius = UDim.new(0, 10); contentCorner.Parent = contentContainer

        local iconLabel = nil
        local iconGap = 0
if hasIcon then
    iconLabel = Instance.new("ImageLabel")
    iconLabel.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
    iconLabel.Position = UDim2.new(0, HEADER_LEFT, 0, ICON_TOP)
    iconLabel.BackgroundTransparency = 1
    iconLabel.ImageColor3 = Color3.new(1, 1, 1)
    iconLabel.Image = ResolveIcon(sectionIcon) or ""
    Instance.new("UICorner", iconLabel).CornerRadius = UDim.new(0, 8)
    iconLabel.Parent = contentContainer
    AddToRegistry(iconLabel, "ImageColor3", "Text")
    iconGap = ICON_SIZE + 10
end

        local titleLabel = nil
        if hasTitle then
            titleLabel = Instance.new("TextLabel")
            titleLabel.Size = UDim2.new(1, -(HEADER_LEFT * 2 + iconGap + ARROW_W), 0, TITLE_H)
            titleLabel.Position = UDim2.new(0, HEADER_LEFT + iconGap, 0, TITLE_TOP)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Font = Enum.Font.GothamBold
            titleLabel.Text = sectionTitle; titleLabel.TextSize = TITLE_SIZE
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.TextYAlignment = Enum.TextYAlignment.Center
            titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
            titleLabel.TextColor3 = CurrentTheme.Accent
            titleLabel.Parent = contentContainer
            AddToRegistry(titleLabel, "TextColor3", "Accent")
        end

        local subtitleLabel = nil
        if hasSubtitle then
            subtitleLabel = Instance.new("TextLabel")
            subtitleLabel.Size = UDim2.new(1, -(HEADER_LEFT * 2 + iconGap + ARROW_W), 0, SUB_H)
            subtitleLabel.Position = UDim2.new(0, HEADER_LEFT + iconGap, 0, SUB_TOP)
            subtitleLabel.BackgroundTransparency = 1
            subtitleLabel.Font = Enum.Font.Gotham
            subtitleLabel.Text = sectionSubtitle; subtitleLabel.TextSize = SUB_SIZE
            subtitleLabel.TextTransparency = 0.4
            subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
            subtitleLabel.TextYAlignment = Enum.TextYAlignment.Center
            subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
            subtitleLabel.Parent = contentContainer
            AddToRegistry(subtitleLabel, "TextColor3", "SubText")
            TextGradient:Skip(subtitleLabel)
        end

        local collapseArrow = nil
        if collapsible then
            collapseArrow = Instance.new("ImageLabel")
            collapseArrow.Size = UDim2.new(0, 18, 0, 18)
            collapseArrow.AnchorPoint = Vector2.new(1, 0.5)
            collapseArrow.Position = UDim2.new(1, -10, 0, ARROW_TOP + 9)
            collapseArrow.BackgroundTransparency = 1
            collapseArrow.Image = "rbxassetid://122444883127455"
            collapseArrow.ImageColor3 = CurrentTheme.Text
            collapseArrow.ImageTransparency = 0.35
            collapseArrow.ScaleType = Enum.ScaleType.Fit
            collapseArrow.Rotation = collapsed and 180 or 0
            collapseArrow.Parent = contentContainer
            AddToRegistry(collapseArrow, "ImageColor3", "Text")
        end

        local contentHolder = Instance.new("Frame")
        contentHolder.Size = UDim2.new(1, -10, 0, 0)
        contentHolder.Position = UDim2.new(0, 5, 0, CONTENT_TOP)
        contentHolder.AnchorPoint = Vector2.new(0, 0)
        contentHolder.BackgroundTransparency = 1
        contentHolder.AutomaticSize = Enum.AutomaticSize.None
        contentHolder.ClipsDescendants = false
        contentHolder.Parent = contentContainer
        local contentLayout = Instance.new("UIListLayout")
        contentLayout.Padding = UDim.new(0, 0)
        contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
        contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        contentLayout.Parent = contentHolder

        local bottomPadding = Instance.new("Frame")
        bottomPadding.Size = UDim2.new(1, 0, 0, 4)
        bottomPadding.BackgroundTransparency = 1
        bottomPadding.LayoutOrder = 9999
        bottomPadding.Parent = contentHolder

        contentContainer.Visible = true; contentHolder.Visible = true

        local lockFrame, lockLabel = createLockOverlay(sectionFrame, lockedTitle)
        lockFrame.Size = UDim2.new(1, -5, 1, 0)
        lockFrame.Position = UDim2.new(0, 0, 0, 0)
        lockFrame.AnchorPoint = Vector2.new(0, 0)
        local _lockCorner = lockFrame:FindFirstChildOfClass("UICorner")
        if _lockCorner and contentCorner then
            _lockCorner.CornerRadius = contentCorner.CornerRadius
        end
        lockFrame.ZIndex = 200; lockFrame.Visible = locked

        local collapsedState = collapsed
        local function getContentHeight() return contentLayout.AbsoluteContentSize.Y or 0 end
        local function getTargetHeight()
            if collapsedState then return COLLAPSED_H end
            return getContentHeight() + CONTENT_TOP + 4
        end
        local function updateHeight(instant)
            local targetH = getTargetHeight()
            if instant then
                contentContainer.Size = UDim2.new(1, -5, 0, targetH)
                sectionFrame.Size = UDim2.new(1, -5, 0, targetH)
            else
                TweenService:Create(contentContainer, MIUI_TWEEN, {Size = UDim2.new(1, -5, 0, targetH)}):Play()
                TweenService:Create(sectionFrame, MIUI_TWEEN, {Size = UDim2.new(1, -5, 0, targetH)}):Play()
            end
        end
        contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            if not collapsedState then updateHeight(false) end
        end)
        contentHolder.ChildAdded:Connect(function()
            task.wait(0.05)
            if not collapsedState then updateHeight(false) end
        end)
        contentHolder.ChildRemoved:Connect(function()
            task.wait(0.05)
            if not collapsedState then updateHeight(false) end
        end)
        if collapsedState then contentHolder.Visible = false end
        defer(function() updateHeight(true) end)

        local function setCollapsed(state, instant)
            if not collapsible then return end
            state = state == true
            if collapsedState == state then return end
            collapsedState = state
            if collapseArrow then
                TweenService:Create(collapseArrow, MIUI_TWEEN, { Rotation = state and 180 or 0 }):Play()
            end
            contentHolder.Visible = not state
            updateHeight(instant)
        end

        local PoppedOut = false
        local PopOutFloat = nil
        local PopOutPlaceholder = nil

        local DragState = "Idle"
        local DragInput = nil
        local PressMouse = nil
        local DragStartPos = nil
        local DragChangedConn = nil
        local DragDidMove = false
        local JustDragged = false

        local function GetScreenGui()
            local s = sectionFrame
            while s do
                if s:IsA("ScreenGui") then return s end
                s = s.Parent
            end
            return nil
        end

        local function GetHostWindow()
            local node = sectionFrame
            while node and node.Parent do
                if node.Parent:IsA("ScreenGui") then return node end
                node = node.Parent
            end
            return nil
        end

        local function PointOverFrame(frame, point)
            if not frame or not frame.Parent then return false end
            local ap, as = frame.AbsolutePosition, frame.AbsoluteSize
            return point.X >= ap.X and point.X <= ap.X + as.X
               and point.Y >= ap.Y and point.Y <= ap.Y + as.Y
        end

        local function RaiseFloat()
            if not PopOutFloat then return end
            local sg = GetScreenGui()
            if not sg then return end
            local maxZ = 500
            for _, c in ipairs(sg:GetChildren()) do
                if c:IsA("Frame") and c.Name == "KGSectionFloat" and c ~= PopOutFloat then
                    maxZ = math.max(maxZ, c.ZIndex)
                end
            end
            PopOutFloat.ZIndex = maxZ + 1
        end

        local function ApplyPoppedOut(shouldPop)
            shouldPop = shouldPop == true
            if PoppedOut == shouldPop then return end

            local sg = GetScreenGui()
            if not sg then return end

            if shouldPop then
                local width = sectionFrame.AbsoluteSize.X
                local height = sectionFrame.Size.Y.Offset

                local ph = Instance.new("Frame")
                ph.Name = "KGSectionPlaceholder"
                ph.Size = UDim2.fromScale(1, 1)
                ph.BackgroundTransparency = 1
                ph.BorderSizePixel = 0
                ph.ZIndex = contentContainer.ZIndex
                ph.Parent = sectionFrame
                local phc = Instance.new("UICorner")
                phc.CornerRadius = UDim.new(0, 10)
                phc.Parent = ph
                local phs = Instance.new("UIStroke")
                phs.Color = CurrentTheme.Stroke
                phs.Transparency = 0.5
                phs.Thickness = 1
                phs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                phs.Parent = ph
                PopOutPlaceholder = ph

                local absPos = sectionFrame.AbsolutePosition
                local float = Instance.new("Frame")
                float.Name = "KGSectionFloat"
                float.BackgroundTransparency = 1
                float.BorderSizePixel = 0
                float.AutomaticSize = Enum.AutomaticSize.Y
                float.Size = UDim2.new(0, width, 0, 0)
                float.Position = UDim2.fromOffset(absPos.X, absPos.Y)
                float.ZIndex = 500
                float.Parent = sg
                PopOutFloat = float

                contentContainer.Parent = float
                contentContainer.Size = UDim2.new(1, 0, 0, height)
                contentContainer.Position = UDim2.new(0, 0, 0, 0)
                contentContainer.AnchorPoint = Vector2.new(0, 0)

                PoppedOut = true
                RaiseFloat()
            else
                contentContainer.Parent = sectionFrame
                contentContainer.Size = UDim2.new(1, -5, 0, sectionFrame.Size.Y.Offset)
                contentContainer.Position = UDim2.new(0, 0, 0, 0)

                if PopOutPlaceholder then PopOutPlaceholder:Destroy(); PopOutPlaceholder = nil end
                if PopOutFloat then PopOutFloat:Destroy(); PopOutFloat = nil end

                PoppedOut = false
                updateHeight(true)
            end
        end

        local function StopDrag()
            if DragState == "Idle" then return end

            local wasDragging = DragState == "Dragging"
            local didMove = DragDidMove

            DragState = "Idle"
            DragInput = nil
            PressMouse = nil
            DragStartPos = nil
            DragDidMove = false

            if DragChangedConn then
                DragChangedConn:Disconnect()
                DragChangedConn = nil
            end

            if not wasDragging then return end

            if didMove then
                JustDragged = true
                task.delay(0.25, function() JustDragged = false end)
            end

            if not PoppedOut or not PopOutFloat then return end

            local hostWin = GetHostWindow()
            if hostWin and not hostWin.Visible then return end

            if PopOutPlaceholder and PopOutPlaceholder.Parent then
                local floatCenter = PopOutFloat.AbsolutePosition + PopOutFloat.AbsoluteSize * 0.5
                local phCenter    = PopOutPlaceholder.AbsolutePosition + PopOutPlaceholder.AbsoluteSize * 0.5
                if (floatCenter - phCenter).Magnitude <= 80 then
                    ApplyPoppedOut(false)
                end
            end
        end

        local function BeginDrag(input)
            if DragState ~= "Idle" then return end
            if not SectionDragMode then return end

            DragState = "Holding"
            DragInput = input
            PressMouse = Vector2.new(input.Position.X, input.Position.Y)
            DragStartPos = nil
            DragDidMove = false

            if PoppedOut and PopOutFloat then
                RaiseFloat()
            end

            DragChangedConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    StopDrag()
                end
            end)

            task.delay(0.5, function()
                if DragState ~= "Holding" or DragInput ~= input then return end
                DragState = "Dragging"
                if PoppedOut and PopOutFloat then
                    RaiseFloat()
                    DragStartPos = PopOutFloat.Position
                end
            end)
        end

        local function UpdateDrag(input)
            if DragState ~= "Dragging" or not PressMouse then return end

            local mousePos = Vector2.new(input.Position.X, input.Position.Y)
            local delta = mousePos - PressMouse

            if not PoppedOut then
                if delta.Magnitude < 8 then return end
                ApplyPoppedOut(true)
                if not PopOutFloat then return end
                RaiseFloat()
                DragStartPos = PopOutFloat.Position
                DragDidMove = true
            elseif delta.Magnitude >= 8 then
                DragDidMove = true
            end

            if PopOutFloat and DragStartPos then
                PopOutFloat.Position = UDim2.new(
                    DragStartPos.X.Scale,
                    DragStartPos.X.Offset + delta.X,
                    DragStartPos.Y.Scale,
                    DragStartPos.Y.Offset + delta.Y
                )
            end
        end

        UserInputService.InputChanged:Connect(function(input)
            if DragState ~= "Dragging" then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                UpdateDrag(input)
            end
        end)

        if collapsible then
            local headBtn = Instance.new("TextButton")
            headBtn.Size = UDim2.new(1, 0, 0, HEADER_H)
            headBtn.Position = UDim2.new(0, 0, 0, 0)
            headBtn.BackgroundTransparency = 1
            headBtn.Text = ""; headBtn.ZIndex = 5
            headBtn.AutoButtonColor = false
            headBtn.Parent = contentContainer
            headBtn.MouseButton1Click:Connect(function()
                if locked or JustDragged then return end
                setCollapsed(not collapsedState, false)
            end)
            headBtn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                    BeginDrag(input)
                end
            end)
        else
            local dragZone = Instance.new("TextButton")
            dragZone.Name = "SectionDragZone"
            dragZone.Size = UDim2.new(1, 0, 0, math.max(HEADER_H, 30))
            dragZone.Position = UDim2.new(0, 0, 0, 0)
            dragZone.BackgroundTransparency = 1
            dragZone.Text = ""
            dragZone.AutoButtonColor = false
            dragZone.ZIndex = 2
            dragZone.Parent = contentContainer

            dragZone.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                    BeginDrag(input)
                end
            end)
        end

        table.insert(SectionDragListeners, function(enabled)
            if enabled or not PoppedOut then return end
            local hostWin = GetHostWindow()
            if hostWin and not hostWin.Visible then return end
            ApplyPoppedOut(false)
        end)

        local tabBuilders = {}
        if hasTabs then
            local tabBar = Instance.new("Frame")
            tabBar.Name = "SectionTabBar"
            tabBar.Size = UDim2.new(1, 0, 0, 28)
            tabBar.BackgroundTransparency = 1
            tabBar.Parent = contentHolder
            local tabBarLayout = Instance.new("UIListLayout")
            tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
            tabBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
            tabBarLayout.Padding = UDim.new(0, 5)
            tabBarLayout.Parent = tabBar

            local tabSpacer = Instance.new("Frame")
            tabSpacer.Name = "TabSpacer"
            tabSpacer.Size = UDim2.new(1, 0, 0, 5)
            tabSpacer.BackgroundTransparency = 1
            tabSpacer.Parent = contentHolder

            local tabContentWrap = Instance.new("Frame")
            tabContentWrap.Name = "SectionTabContentWrap"
            tabContentWrap.Size = UDim2.new(1, 0, 0, 0)
            tabContentWrap.BackgroundTransparency = 1
            tabContentWrap.Parent = contentHolder

            local tabDataMap = {}
            local activeTabKey = nil
            local tabCount = #tabEntries
            local widthScale = 1 / math.max(tabCount, 1)

            local function refreshTabWrapHeight()
                if activeTabKey and tabDataMap[activeTabKey] then
                    local h = tabDataMap[activeTabKey].layout.AbsoluteContentSize.Y
                    tabContentWrap.Size = UDim2.new(1, 0, 0, h)
                end
            end

            local function switchTab(key)
                if activeTabKey == key then return end
                activeTabKey = key
                for k, data in pairs(tabDataMap) do
                    local active = (k == key)
                    data.frame.Visible = active
                    Tween(data.btn, {
                        BackgroundTransparency = active and 0.150 or 1,
                        BackgroundColor3 = CurrentTheme.Top,
                    }, 0.18)
                    Tween(data.stroke, {
                        Transparency = active and 0.650 or 1,
                    }, 0.18)
                    if data.icon then
                        Tween(data.icon, {
                            ImageColor3 = active and CurrentTheme.Accent or Color3.fromRGB(223, 223, 223),
                            ImageTransparency = active and 0 or 0.5,
                        }, 0.18)
                    end
                    if data.label then
                        Tween(data.label, {
                            TextColor3 = Color3.fromRGB(255, 255, 255),
                            TextTransparency = active and 0 or 0.5,
                        }, 0.18)
                    end
                end
                refreshTabWrapHeight()
            end

            for _, entry in ipairs(tabEntries) do
                local key     = tostring(entry.Key)
                local tabName = entry.Name or key
                local tabIcon = entry.Icon

                local btn = Instance.new("TextButton")
                btn.Name = "SectionTab_"..key
                btn.BackgroundColor3 = CurrentTheme.Top
                btn.BackgroundTransparency = 1
                btn.Text = ""
                btn.AutoButtonColor = false
                btn.Size = UDim2.new(widthScale, -4, 1, 0)
                btn.Parent = tabBar
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

                local btnStroke = Instance.new("UIStroke")
                btnStroke.Thickness = 1
                btnStroke.Transparency = 1
                btnStroke.Color = CurrentTheme.Stroke
                btnStroke.Parent = btn
                table.insert(ThemeListeners, function() btnStroke.Color = CurrentTheme.Stroke end)

                local iconLabel = nil
                if tabIcon and tostring(tabIcon) ~= "" then
                    iconLabel = Instance.new("ImageLabel")
                    iconLabel.AnchorPoint = Vector2.new(0, 0.5)
                    iconLabel.Position = UDim2.new(0, 7, 0.5, 0)
                    iconLabel.Size = UDim2.new(0, 18, 0, 18)
                    iconLabel.BackgroundTransparency = 1
                    iconLabel.ImageColor3 = Color3.fromRGB(223, 223, 223)
                    iconLabel.ImageTransparency = 0.5
                    iconLabel.ScaleType = Enum.ScaleType.Fit
                    iconLabel.Image = ResolveIcon(tabIcon) or ""

                    local uiScale = Instance.new("UIScale")
                    uiScale.Name = "ModernIconScale"
                    uiScale.Scale = 0.82
                    uiScale.Parent = iconLabel

                    iconLabel.Parent = btn
                end

                local textLbl = Instance.new("TextLabel")
                textLbl.Name = "TabText"
                textLbl.AnchorPoint = Vector2.new(0, 0.5)
                textLbl.Position = UDim2.new(0, 29, 0.5, 0)
                textLbl.Size = UDim2.new(1, -34, 0, 15)
                textLbl.BackgroundTransparency = 1
                textLbl.Font = Enum.Font.GothamMedium
                textLbl.Text = tabName
                textLbl.TextSize = 11
                textLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                textLbl.TextTransparency = 0.5
                textLbl.TextXAlignment = Enum.TextXAlignment.Left
                textLbl.TextTruncate = Enum.TextTruncate.AtEnd
                textLbl.Parent = btn

                local tabFrame = Instance.new("Frame")
                tabFrame.Name = "TabContent_"..key
                tabFrame.Size = UDim2.new(1, 0, 0, 0)
                tabFrame.AutomaticSize = Enum.AutomaticSize.Y
                tabFrame.BackgroundTransparency = 1
                tabFrame.Visible = false
                tabFrame.Parent = tabContentWrap
                local tabLayout = Instance.new("UIListLayout")
                tabLayout.Padding = UDim.new(0, 0)
                tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
                tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                tabLayout.Parent = tabFrame

                tabDataMap[key] = {
                    frame = tabFrame, layout = tabLayout,
                    btn = btn, stroke = btnStroke,
                    icon = iconLabel, label = textLbl,
                }

                local subBuilder = createSectionBuilder(tabFrame, tabFrame, elementWidth, windowCount, win)
                tabBuilders[key] = setmetatable({}, {
                    __index = function(_, k)
                        local fn = subBuilder[k]
                        if k == "Section" then
                            return function(self, cfg) return fn(subBuilder, cfg) end
                        end
                        if type(fn) == "function" then
                            return function(self, cfg)
                                cfg = cfg or {}
                                if type(cfg) == "table" and cfg.Parent == nil then
                                    cfg.Parent = tabFrame
                                end
                                return fn(subBuilder, cfg)
                            end
                        end
                        return fn
                    end
                })

                btn.MouseButton1Click:Connect(function()
                    if locked then return end
                    switchTab(key)
                end)

                tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    if activeTabKey == key then refreshTabWrapHeight() end
                end)
            end

            if tabEntries[1] then
                local firstKey = tostring(tabEntries[1].Key)
                activeTabKey = nil
                switchTab(firstKey)
            end
        end

        local sectionObj = {}
        for methodName, methodFn in pairs(child) do
            sectionObj[methodName] = function(_, cfg)
                cfg = cfg or {}
                cfg.Parent = contentHolder
                return methodFn(_, cfg)
            end
        end
        sectionObj.SetVisible = function(_, vis) sectionFrame.Visible = vis end
        sectionObj.SetTitle = function(_, text)
            if titleLabel then titleLabel.Text = text or ""; titleLabel.Visible = (text ~= nil and text ~= "") end
        end
        sectionObj.SetSubtitle = function(_, text)
            if subtitleLabel then subtitleLabel.Text = text or ""; subtitleLabel.Visible = (text ~= nil and text ~= "") end
        end
        sectionObj.SetCollapsed = function(_, state) setCollapsed(state, false); return sectionObj end
        sectionObj.ToggleCollapsed = function(_) setCollapsed(not collapsedState, false); return sectionObj end
        sectionObj.GetCollapsed = function(_) return collapsedState end
        sectionObj.SetCollapsible = function(_, state) collapsible = state == true; return sectionObj end
        sectionObj.IsCollapsible = function(_) return collapsible end
        sectionObj.SetLocked = function(_, state) locked = state == true; lockFrame.Visible = locked; return sectionObj end
        sectionObj.SetTextLocked = function(_, text) lockedTitle = text or "已锁定"; lockLabel.Text = lockedTitle; return sectionObj end
        sectionObj.SetMessage = function(_, text) lockedTitle = text or "已锁定"; lockLabel.Text = lockedTitle; return sectionObj end
        sectionObj.GetLocked = function(_) return locked end
        sectionObj.Lock = function(_, text)
            if text then lockedTitle = text; lockLabel.Text = lockedTitle end
            locked = true; lockFrame.Visible = true
            return sectionObj
        end
        sectionObj.Unlock = function(_) locked = false; lockFrame.Visible = false; return sectionObj end

        if hasTabs then
            return setmetatable({}, {
                __index = function(_, key)
                    if sectionObj[key] ~= nil then
                        return sectionObj[key]
                    end
                    if tabBuilders[key] ~= nil then
                        return tabBuilders[key]
                    end
                    return nil
                end
            })
        end

        return sectionObj
    end

    functions.Section = createSection
    return functions
end

function KG_UI:CreateWindow(Config)
    ConfigIdCounter = 0

    local Window = {}
    local Title = Config.Name or "KG_UI"
    local Subtitle = Config.SubName
    local Keybind = Config.Keybind
    local IconAsset = Config.Logo or Config.Icon
    local SceneId = Config.Scene
    local AccNameCfg = Config.AccountName or Config.PlayerName
    local AccSubCfg  = Config.AccountSub or Config.PlayerSub

    if Config.Theme then
        if type(Config.Theme) == "string" then
            if Themes[Config.Theme] then CurrentTheme = Themes[Config.Theme] end
        elseif type(Config.Theme) == "table" then
            local t = Config.Theme
            local function toC3(v)
                if type(v) == "table" then return Color3.fromRGB(v[1] or 0, v[2] or 0, v[3] or 0)
                elseif type(v) == "userdata" then return v
                else return Color3.new(0,0,0) end
            end
            local customTheme = {}
            for k, v in pairs(CurrentTheme) do customTheme[k] = v end
            if t.Main then customTheme.Main = toC3(t.Main) end
            if t.Top then customTheme.Top = toC3(t.Top) end
            if t.Text then customTheme.Text = toC3(t.Text) end
            if t.Accent then customTheme.Accent = toC3(t.Accent) end
            if t.Stroke then customTheme.Stroke = toC3(t.Stroke) end
            if t.SubText then customTheme.SubText = toC3(t.SubText) end
            if t.Element then customTheme.Element = toC3(t.Element) end
            if t.Hover then customTheme.Hover = toC3(t.Hover) end
            if t.ShineEnabled ~= nil then customTheme.ShineEnabled = t.ShineEnabled end
            if t.Shine then customTheme.Shine = t.Shine end
            if t.StrokeShine ~= nil then customTheme.StrokeShine = t.StrokeShine end
            if t.StrokeDark then customTheme.StrokeDark = toC3(t.StrokeDark) end
            local customName = t.Name or "Custom"
            Themes[customName] = customTheme
            CurrentTheme = customTheme
        end
    end

    -- ① ScreenGui
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "KG_UI"
    ScreenGui.Parent = CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = tonumber(Config.DisplayOrder) or 999
    pcall(function()
        ScreenGui.ScreenInsets = Enum.ScreenInsets.None
    end)
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) elseif gethui then ScreenGui.Parent = gethui() end

    TextGradient:AttachHook(ScreenGui)

    

    local FINAL_WIDTH = 500
    local FINAL_HEIGHT = 299

    -- ② MainFrame（主窗口容器）
    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 0, 0, 0)
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.ClipsDescendants = true
    MainFrame.BackgroundTransparency = 0.15
    MainFrame.Visible = false
    MainFrame.Parent = ScreenGui
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
    AddToRegistry(MainFrame, "BackgroundColor3", "Main")

    -- ③ bgImage / bgGradient / shadowStrokes
    local shadowStrokes = {}
    for _, thick in ipairs({6, 5, 4, 3}) do
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = thick
        stroke.Color = Color3.new(0, 0, 0)
        stroke.Transparency = 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = MainFrame
        table.insert(shadowStrokes, stroke)
    end
    local function setShadowVisible(visible, instant)
        local targetTrans = visible and 0.9 or 1
        for _, stroke in ipairs(shadowStrokes) do
            if instant then stroke.Transparency = targetTrans
            else Tween(stroke, {Transparency = targetTrans}, 0.3) end
        end
    end

    local bgImage = Instance.new("ImageLabel")
    bgImage.Size = UDim2.new(1, 0, 1, 0)
    bgImage.BackgroundTransparency = 1
    bgImage.ZIndex = 0; bgImage.Parent = MainFrame
    Instance.new("UICorner", bgImage).CornerRadius = UDim.new(0, 12)
    if SceneId then
        if type(SceneId) == "number" or (type(SceneId) == "string" and tonumber(SceneId)) then
            bgImage.Image = "rbxassetid://"..tostring(SceneId)
        else bgImage.Image = tostring(SceneId) end
    else
        bgImage.Image = ""; bgImage.Visible = false
    end

    local bgGradient = Instance.new("UIGradient")
    bgGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CurrentTheme.Main),
        ColorSequenceKeypoint.new(0.5, CurrentTheme.Top),
        ColorSequenceKeypoint.new(1, CurrentTheme.Main)
    })
    bgGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.1),
        NumberSequenceKeypoint.new(1, 0.3)
    })
    bgGradient.Parent = MainFrame
    setShadowVisible(false, true)

    -- ④ Resizer（缩放手柄）
    local Resizer = Instance.new("TextButton")
    Resizer.Parent = MainFrame
    Resizer.BackgroundTransparency = 0.8
    Resizer.BackgroundColor3 = Color3.new(1, 1, 1)
    Resizer.Position = UDim2.new(1, 5, 1, 5)
    Resizer.Size = UDim2.new(0, 24, 0, 24)
    Resizer.AnchorPoint = Vector2.new(1, 1)
    Resizer.Text = ""; Resizer.ZIndex = 30; Resizer.Visible = false
    local isResizing = false
    local resizeStart = Vector2.new(0, 0)
    local startSize = UDim2.new(0, 0, 0, 0)
    Resizer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isResizing = true; resizeStart = input.Position; startSize = MainFrame.Size
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isResizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - resizeStart
            MainFrame.Size = UDim2.new(0, math.max(400, startSize.X.Offset + delta.X), 0, math.max(250, startSize.Y.Offset + delta.Y))
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isResizing = false end
    end)

    -- ⑤ LeftMenuFrame（左侧边栏）
    local LeftMenuFrame = Instance.new("Frame")
    LeftMenuFrame.Size = UDim2.new(0, 175, 1, 0)
    LeftMenuFrame.BackgroundTransparency = 1
    LeftMenuFrame.Parent = MainFrame

    local HeadFrame = Instance.new("Frame")
    HeadFrame.Size = UDim2.new(1, 0, 0, 50)
    HeadFrame.BackgroundTransparency = 1
    HeadFrame.Parent = LeftMenuFrame

    local LogoImage = Instance.new("ImageLabel")
    LogoImage.Size = UDim2.new(0, 35, 0, 35)
    LogoImage.Position = UDim2.new(0, 10, 0.5, -17.5)
    LogoImage.BackgroundTransparency = 1
    LogoImage.Image = ResolveIcon(IconAsset) or "rbxassetid://84830962019412"
    LogoImage.Parent = HeadFrame
    AddToRegistry(LogoImage, "ImageColor3", "Text")
    Instance.new("UICorner", LogoImage).CornerRadius = UDim.new(0, 7)

    local WindowName = Instance.new("TextLabel")
    WindowName.Size = UDim2.new(1, -65, 0, 25)
    WindowName.Position = UDim2.new(0, 55, 0, 4)
    WindowName.BackgroundTransparency = 1
    WindowName.Font = Enum.Font.GothamBold
    WindowName.Text = Title; WindowName.TextSize = 18
    WindowName.TextXAlignment = Enum.TextXAlignment.Left
    WindowName.Parent = HeadFrame
    AddToRegistry(WindowName, "TextColor3", "Text")

    local WindowContent = Instance.new("TextLabel")
    WindowContent.Size = UDim2.new(1, -65, 0, 15)
    WindowContent.Position = UDim2.new(0, 55, 0, 25)
    WindowContent.BackgroundTransparency = 1
    WindowContent.Font = Enum.Font.GothamMedium
    WindowContent.Text = Subtitle or ""; WindowContent.TextSize = 9
    WindowContent.TextTransparency = 0.65
    WindowContent.TextXAlignment = Enum.TextXAlignment.Left
    WindowContent.Parent = HeadFrame
    AddToRegistry(WindowContent, "TextColor3", "SubText")
    TextGradient:Skip(WindowContent)

    local LineFrame = Instance.new("Frame")
    LineFrame.Size = UDim2.new(1, -10, 0, 1)
    LineFrame.Position = UDim2.new(0.5, 0, 1, 0)
    LineFrame.AnchorPoint = Vector2.new(0.5, 1)
    LineFrame.BackgroundTransparency = 0.65
    LineFrame.BorderSizePixel = 0; LineFrame.Parent = HeadFrame
    AddToRegistry(LineFrame, "BackgroundColor3", "Stroke")

    local LeftScrollingFrame = Instance.new("ScrollingFrame")
    LeftScrollingFrame.Size = UDim2.new(1, -10, 1, -100)
    LeftScrollingFrame.Position = UDim2.new(0.5, 0, 0, 50)
    LeftScrollingFrame.AnchorPoint = Vector2.new(0.5, 0)
    LeftScrollingFrame.BackgroundTransparency = 1
    LeftScrollingFrame.ScrollBarThickness = 0
    LeftScrollingFrame.Parent = LeftMenuFrame
    local TabList = Instance.new("UIListLayout")
    TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    TabList.SortOrder = Enum.SortOrder.LayoutOrder
    TabList.Padding = UDim.new(0, 0)
    TabList.Parent = LeftScrollingFrame
    local function updateTabCanvas()
        LeftScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, TabList.AbsoluteContentSize.Y + 10)
    end
    TabList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateTabCanvas)
    task.spawn(updateTabCanvas)

    local BottomFrame = Instance.new("Frame")
    BottomFrame.Size = UDim2.new(1, 0, 0, 50)
    BottomFrame.Position = UDim2.new(0, 0, 1, 0)
    BottomFrame.AnchorPoint = Vector2.new(0, 1)
    BottomFrame.BackgroundTransparency = 1
    BottomFrame.Parent = LeftMenuFrame

    local LineFrame_2 = Instance.new("Frame")
    LineFrame_2.Size = UDim2.new(1, -10, 0, 1)
    LineFrame_2.Position = UDim2.new(0.5, 0, 0, 0)
    LineFrame_2.AnchorPoint = Vector2.new(0.5, 0)
    LineFrame_2.BackgroundTransparency = 0.65
    LineFrame_2.BorderSizePixel = 0
    LineFrame_2.Parent = BottomFrame
    AddToRegistry(LineFrame_2, "BackgroundColor3", "Stroke")

    local AccountProfile = Instance.new("ImageLabel")
    AccountProfile.Size = UDim2.new(0, 35, 0, 35)
    AccountProfile.Position = UDim2.new(0, 10, 0.5, -17.5)
    AccountProfile.BackgroundTransparency = 1
    AccountProfile.Image = Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
    AccountProfile.Parent = BottomFrame
    Instance.new("UICorner", AccountProfile).CornerRadius = UDim.new(1, 0)

    local AccountName = Instance.new("TextLabel")
    AccountName.Size = UDim2.new(0, 100, 0, 25)
    AccountName.Position = UDim2.new(0, 55, 0, 5)
    AccountName.BackgroundTransparency = 1
    AccountName.Font = Enum.Font.GothamBold
    AccountName.Text = LocalPlayer.DisplayName
    AccountName.TextSize = 14
    AccountName.TextXAlignment = Enum.TextXAlignment.Left
    AccountName.TextTruncate = Enum.TextTruncate.SplitWord
    AccountName.Parent = BottomFrame
    AddToRegistry(AccountName, "TextColor3", "Text")

    local ExpireLabel = Instance.new("TextLabel")
    ExpireLabel.Size = UDim2.new(0, 120, 0, 15)
    ExpireLabel.Position = UDim2.new(0, 55, 0, 25)
    ExpireLabel.BackgroundTransparency = 1
    ExpireLabel.Font = Enum.Font.GothamMedium
    ExpireLabel.Text = LocalPlayer.Name
    ExpireLabel.TextSize = 10
    ExpireLabel.TextTransparency = 0.65
    ExpireLabel.TextXAlignment = Enum.TextXAlignment.Left
    ExpireLabel.Parent = BottomFrame
    AddToRegistry(ExpireLabel, "TextColor3", "SubText")
    TextGradient:Skip(ExpireLabel)



    -- ⑥ RightMenuFrame（右侧内容区）
    local RightMenuFrame = Instance.new("Frame")
    RightMenuFrame.Size = UDim2.new(1, -176, 1, 0)
    RightMenuFrame.Position = UDim2.new(0, 176, 0, 0)
    RightMenuFrame.BackgroundTransparency = 0.6
    RightMenuFrame.ClipsDescendants = true
    RightMenuFrame.Parent = MainFrame
    Instance.new("UICorner", RightMenuFrame).CornerRadius = UDim.new(0, 13)
    AddToRegistry(RightMenuFrame, "BackgroundColor3", "Main")

    local RightStroke = Instance.new("UIStroke")
    RightStroke.Thickness = 1; RightStroke.Transparency = 0.65
    RightStroke.Parent = RightMenuFrame
    AddToRegistry(RightStroke, "Color", "Stroke")

    local RightHeader = Instance.new("Frame")
    RightHeader.Size = UDim2.new(1, 0, 0, 50)
    RightHeader.BackgroundTransparency = 1
    RightHeader.Parent = RightMenuFrame

    local LineFrame_3 = Instance.new("Frame")
    LineFrame_3.Size = UDim2.new(1, -10, 0, 1)
    LineFrame_3.Position = UDim2.new(0.5, 0, 1, 0)
    LineFrame_3.AnchorPoint = Vector2.new(0.5, 1)
    LineFrame_3.BackgroundTransparency = 0.65
    LineFrame_3.BorderSizePixel = 0; LineFrame_3.Parent = RightHeader
    AddToRegistry(LineFrame_3, "BackgroundColor3", "Stroke")

    -- ⑧ ButtonGroup（右上角 4 按钮）
    local resizerVisible = false
    local ButtonGroup = Instance.new("Frame")
    ButtonGroup.Size = UDim2.new(0, 180, 1, 0)
    ButtonGroup.Position = UDim2.new(1, -190, 0, 0)
    ButtonGroup.BackgroundTransparency = 1; ButtonGroup.Parent = RightHeader
    local ButtonLayout = Instance.new("UIListLayout")
    ButtonLayout.FillDirection = Enum.FillDirection.Horizontal
    ButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    ButtonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    ButtonLayout.Padding = UDim.new(0, 5); ButtonLayout.Parent = ButtonGroup
    local ButtonPadding = Instance.new("UIPadding")
    ButtonPadding.PaddingRight = UDim.new(0, 10); ButtonPadding.Parent = ButtonGroup

    local function createControlButton(iconAsset, fallbackText, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 32, 0, 32)
        btn.AutoButtonColor = false; btn.Text = ""
        btn.BackgroundTransparency = 0.2
        btn.BackgroundColor3 = CurrentTheme.Element or CurrentTheme.Top
        btn.Parent = ButtonGroup
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 0, 0, 0)
        accent.AnchorPoint = Vector2.new(0.5, 0.5)
        accent.Position = UDim2.new(0.5, 0, 0.5, 0)
        accent.BackgroundTransparency = 1; accent.ZIndex = 2
        accent.BackgroundColor3 = CurrentTheme.Accent
        accent.Parent = btn
        Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 7)
        local content
        if iconAsset then
            content = Instance.new("ImageLabel")
            content.Size = UDim2.new(0, 14, 0, 14)
            content.AnchorPoint = Vector2.new(0.5, 0.5)
            content.Position = UDim2.new(0.5, 0, 0.5, 0)
            content.BackgroundTransparency = 1
            content.Image = iconAsset
            content.ImageColor3 = CurrentTheme.Text
            content.ImageTransparency = 0.3
            content.ZIndex = 3; content.Parent = btn
        else
            content = Instance.new("TextLabel")
            content.Size = UDim2.new(1, 0, 1, 0)
            content.BackgroundTransparency = 1
            content.Font = Enum.Font.GothamBold
            content.Text = fallbackText or ""
            content.TextSize = 18
            content.TextColor3 = CurrentTheme.Text
            content.TextTransparency = 0.3
            content.ZIndex = 3; content.Parent = btn
        end
        btn.MouseEnter:Connect(function()
            Tween(btn, {BackgroundTransparency = 0}, 0.2)
            if content then
                local p = content:IsA("ImageLabel") and "ImageTransparency" or "TextTransparency"
                Tween(content, {[p] = 0}, 0.2)
            end
            Tween(accent, {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 0}, 0.2)
        end)
        btn.MouseLeave:Connect(function()
            Tween(btn, {BackgroundTransparency = 0.2}, 0.2)
            if content then
                local p = content:IsA("ImageLabel") and "ImageTransparency" or "TextTransparency"
                Tween(content, {[p] = 0.3}, 0.2)
            end
            Tween(accent, {Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1}, 0.2)
        end)
        btn.MouseButton1Click:Connect(callback)
        return btn, content
    end

    local SectionDragBtn, SectionDragIcon = createControlButton("rbxassetid://18879088568", nil, function()
        SetSectionDragMode(not SectionDragMode)
        if SectionDragIcon then
            Tween(SectionDragIcon, {
                ImageColor3 = SectionDragMode and CurrentTheme.Accent or CurrentTheme.Text,
                ImageTransparency = SectionDragMode and 0 or 0.3,
            }, 0.18)
        end
    end)
    if SectionDragIcon then
        SectionDragIcon.ImageColor3 = SectionDragMode and CurrentTheme.Accent or CurrentTheme.Text
    end

    local MinimizeBtn = createControlButton(nil, "−", function() MainFrame.Visible = false end)
    local MaximizeBtn = createControlButton("rbxassetid://6031090998", nil, function()
        resizerVisible = not resizerVisible
        Resizer.Visible = resizerVisible
    end)
    local CloseBtn = createControlButton("rbxassetid://130510492706892", nil, function() ScreenGui:Destroy() end)

    -- ⑩ TabContainer（右侧内容区）
    local TabContainer = Instance.new("Frame")
    TabContainer.Size = UDim2.new(1, 0, 1, -50)
    TabContainer.Position = UDim2.new(0, 0, 0, 50)
    TabContainer.BackgroundTransparency = 1
    TabContainer.ClipsDescendants = true
    TabContainer.Parent = RightMenuFrame

    local PageContainer = Instance.new("ScrollingFrame")
    PageContainer.Size = UDim2.new(1, 0, 1, 0)
    PageContainer.BackgroundTransparency = 1
    PageContainer.ScrollBarThickness = 0
    PageContainer.ScrollingEnabled = true
    PageContainer.Parent = TabContainer

    local PageContent = Instance.new("Frame")
    PageContent.Size = UDim2.new(1, 0, 0, 0)
    PageContent.AutomaticSize = Enum.AutomaticSize.Y
    PageContent.BackgroundTransparency = 1
    PageContent.Parent = PageContainer
    local PageList = Instance.new("UIListLayout")
    PageList.Padding = UDim.new(0, 0)
    PageList.SortOrder = Enum.SortOrder.LayoutOrder
    PageList.Parent = PageContent
    local function updatePageCanvas()
        PageContainer.CanvasSize = UDim2.new(0, 0, 0, PageList.AbsoluteContentSize.Y + 10)
    end
    PageList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updatePageCanvas)
    task.spawn(updatePageCanvas)

    -- ⑪ 拖拽 / 缩放 / 键盘绑定 / 动画
    local dragToggle = false
    local dragStart, startPos
    HeadFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragToggle = true
            dragStart = input.Position
            startPos = MainFrame.Position
            local input_end
            input_end = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragToggle = false; input_end:Disconnect()
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    local function AnimateWindowIn()
        MainFrame.Visible = true
        TweenService:Create(MainFrame, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, FINAL_WIDTH, 0, FINAL_HEIGHT)
        }):Play()
        setShadowVisible(true, false)
    end
    MainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        if MainFrame.Visible then setShadowVisible(true, false)
        else setShadowVisible(false, false) end
    end)
    task.delay(0.1, AnimateWindowIn)

-- ============================================================
-- 最小化后的顶部胶囊（完整可配置版）
-- ============================================================
-- ============================================
--  KG_UI 展开胶囊按钮（美化版）
-- ============================================
local OpenPillCfg = {
    Title             = "KG_UI",
    Color             = CurrentTheme.Accent,
    W                 = 150,
    H                 = 32,
    Pos               = UDim2.new(0.5, 0, 0, 8),
    Anchor            = Vector2.new(0.5, 0),
    CornerRadius      = UDim.new(1, 0),          -- 1,0 = 完美胶囊
    StrokeThickness   = 1,
    StrokeTransparency= 0.35,
    Draggable         = false,
    TextSize          = 11,
    TextColor         = Color3.fromRGB(240, 240, 245),
    BgColor           = Color3.fromRGB(18, 18, 22),
    BgTransparency    = 0.15,
    ShowDot           = true,                    -- 左侧小圆点（状态灯）
    DotPulse          = true,                    -- 圆点呼吸动画
}

-- ============================================
--  1. 渐变描边容器（外框）
-- ============================================
local OpenPillBorder = Instance.new("Frame")
OpenPillBorder.Name = "KGOpenPillBorder"
OpenPillBorder.AnchorPoint = OpenPillCfg.Anchor
OpenPillBorder.Position = UDim2.new(
    OpenPillCfg.Pos.X.Scale, OpenPillCfg.Pos.X.Offset,
    OpenPillCfg.Pos.Y.Scale, OpenPillCfg.Pos.Y.Offset - 2
)
OpenPillBorder.Size = UDim2.fromOffset(OpenPillCfg.W + 4, OpenPillCfg.H + 4)
OpenPillBorder.BackgroundColor3 = Color3.new(1, 1, 1)
OpenPillBorder.BorderSizePixel = 0
OpenPillBorder.ZIndex = 10
OpenPillBorder.Visible = false
OpenPillBorder.Parent = ScreenGui

local _pillBorderCorner = Instance.new("UICorner")
_pillBorderCorner.CornerRadius = UDim.new(1, 0)
_pillBorderCorner.Parent = OpenPillBorder

-- 渐变色（用双色渐变模拟霓虹描边）
local _pillGrad = Instance.new("UIGradient")
_pillGrad.Rotation = 90
_pillGrad.Parent = OpenPillBorder

-- 描边透明度（让它像发光边）
local _pillBorderStroke = Instance.new("UIStroke")
_pillBorderStroke.Color = Color3.new(1, 1, 1)
_pillBorderStroke.Thickness = 0
_pillBorderStroke.Transparency = 1
_pillBorderStroke.Parent = OpenPillBorder

-- ============================================
--  2. 胶囊本体
-- ============================================
local OpenPill = Instance.new("TextButton")
OpenPill.Name = "KGOpenPill"
OpenPill.AnchorPoint = OpenPillCfg.Anchor
OpenPill.Position = OpenPillCfg.Pos
OpenPill.Size = UDim2.fromOffset(OpenPillCfg.W, OpenPillCfg.H)
OpenPill.BackgroundColor3 = OpenPillCfg.BgColor
OpenPill.BackgroundTransparency = OpenPillCfg.BgTransparency
OpenPill.BorderSizePixel = 0
OpenPill.Text = ""                              -- 文字单独用一个 Label（便于布局）
OpenPill.AutoButtonColor = false
OpenPill.ZIndex = 11
OpenPill.Visible = false
OpenPill.Parent = ScreenGui

local _pillCorner = Instance.new("UICorner")
_pillCorner.CornerRadius = OpenPillCfg.CornerRadius
_pillCorner.Parent = OpenPill

local _pillStroke = Instance.new("UIStroke")
_pillStroke.Color = CurrentTheme.Stroke
_pillStroke.Thickness = OpenPillCfg.StrokeThickness
_pillStroke.Transparency = OpenPillCfg.StrokeTransparency
_pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
_pillStroke.Parent = OpenPill

-- 顶部高光（让胶囊有玻璃质感）
local _pillGloss = Instance.new("Frame")
_pillGloss.Name = "Gloss"
_pillGloss.BackgroundColor3 = Color3.new(1, 1, 1)
_pillGloss.BackgroundTransparency = 0.94
_pillGloss.BorderSizePixel = 0
_pillGloss.Size = UDim2.new(1, -8, 0.5, -2)
_pillGloss.Position = UDim2.new(0, 4, 0, 2)
_pillGloss.ZIndex = 12
_pillGloss.Parent = OpenPill
local _glossCorner = Instance.new("UICorner")
_glossCorner.CornerRadius = UDim.new(1, 0)
_glossCorner.Parent = _pillGloss

-- ============================================
--  3. 左侧状态圆点（可选）
-- ============================================
local _pillDot
if OpenPillCfg.ShowDot then
    _pillDot = Instance.new("Frame")
    _pillDot.Name = "StatusDot"
    _pillDot.AnchorPoint = Vector2.new(0, 0.5)
    _pillDot.Position = UDim2.new(0, 12, 0.5, 0)
    _pillDot.Size = UDim2.fromOffset(6, 6)
    _pillDot.BackgroundColor3 = OpenPillCfg.Color
    _pillDot.BorderSizePixel = 0
    _pillDot.ZIndex = 13
    _pillDot.Parent = OpenPill
    local _dotCorner = Instance.new("UICorner")
    _dotCorner.CornerRadius = UDim.new(1, 0)
    _dotCorner.Parent = _pillDot

    local _dotGlow = Instance.new("UIStroke")
    _dotGlow.Color = OpenPillCfg.Color
    _dotGlow.Thickness = 2
    _dotGlow.Transparency = 0.5
    _dotGlow.Parent = _pillDot

    if OpenPillCfg.DotPulse then
        task.spawn(function()
            while _pillDot and _pillDot.Parent do
                Tween(_dotGlow, {Transparency = 0.9}, 1.2)
                task.wait(1.2)
                if not (_pillDot and _pillDot.Parent) then break end
                Tween(_dotGlow, {Transparency = 0.4}, 1.2)
                task.wait(1.2)
            end
        end)
    end
end

-- ============================================
--  4. 标题文字（放在胶囊中间）
-- ============================================
local _pillText = Instance.new("TextLabel")
_pillText.Name = "Title"
_pillText.BackgroundTransparency = 1
_pillText.Size = UDim2.new(1, 0, 1, 0)
_pillText.Font = Enum.Font.GothamMedium
_pillText.Text = OpenPillCfg.Title
_pillText.TextColor3 = OpenPillCfg.TextColor
_pillText.TextSize = OpenPillCfg.TextSize
_pillText.ZIndex = 13
_pillText.Parent = OpenPill

if OpenPillCfg.ShowDot then
    local _pad = Instance.new("UIPadding")
    _pad.PaddingLeft = UDim.new(0, 22)   -- 给圆点让位
    _pad.PaddingRight = UDim.new(0, 10)
    _pad.Parent = _pillText
end

-- ============================================
--  内部同步函数
-- ============================================
local function _pillApplyColor(c)
    if typeof(c) ~= "Color3" then return end
    OpenPillCfg.Color = c
    _pillGrad.Color = ColorSequence.new(
        c,
        c:Lerp(Color3.new(1, 1, 1), 0.4)
    )
    if _pillDot then
        _pillDot.BackgroundColor3 = c
        _pillDot:FindFirstChildOfClass("UIStroke").Color = c
    end
end
_pillApplyColor(OpenPillCfg.Color)

local function _pillApplySize(w, h)
    w = tonumber(w) or OpenPillCfg.W
    h = tonumber(h) or OpenPillCfg.H
    OpenPillCfg.W = w
    OpenPillCfg.H = h
    OpenPill.Size = UDim2.fromOffset(w, h)
    OpenPillBorder.Size = UDim2.fromOffset(w + 4, h + 4)
end

local function _pillApplyPos(pos)
    if typeof(pos) ~= "UDim2" then return end
    OpenPillCfg.Pos = pos
    OpenPill.Position = pos
    OpenPillBorder.Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset - 2)
end

local function _pillApplyText(t)
    OpenPillCfg.Title = tostring(t or "")
    _pillText.Text = OpenPillCfg.Title
end

local function _pillApplyStroke(thick)
    OpenPillCfg.StrokeThickness = tonumber(thick) or OpenPillCfg.StrokeThickness
    _pillStroke.Thickness = OpenPillCfg.StrokeThickness
end

local _pillDragConn = nil
local function _pillApplyDraggable(enabled)
    OpenPillCfg.Draggable = enabled == true
    OpenPill.Draggable = OpenPillCfg.Draggable
    OpenPillBorder.Draggable = OpenPillCfg.Draggable
    if OpenPillCfg.Draggable then
        if not _pillDragConn then
            _pillDragConn = OpenPill:GetPropertyChangedSignal("Position"):Connect(function()
                OpenPillBorder.Position = UDim2.new(
                    OpenPill.Position.X.Scale, OpenPill.Position.X.Offset,
                    OpenPill.Position.Y.Scale, OpenPill.Position.Y.Offset - 2
                )
                OpenPillCfg.Pos = OpenPill.Position
            end)
        end
    else
        if _pillDragConn then
            _pillDragConn:Disconnect()
            _pillDragConn = nil
        end
    end
end

-- ============================================
--  交互：悬停 / 按下 / 点击
-- ============================================
local _baseTrans = OpenPillCfg.BgTransparency

OpenPill.MouseEnter:Connect(function()
    Tween(OpenPill, {BackgroundTransparency = math.max(0, _baseTrans - 0.2)}, 0.18)
    Tween(_pillStroke, {Transparency = math.max(0, OpenPillCfg.StrokeTransparency - 0.2)}, 0.18)
end)

OpenPill.MouseLeave:Connect(function()
    Tween(OpenPill, {BackgroundTransparency = _baseTrans}, 0.18)
    Tween(_pillStroke, {Transparency = OpenPillCfg.StrokeTransparency}, 0.18)
end)

-- 按下缩放
OpenPill.MouseButton1Down:Connect(function()
    Tween(OpenPill, {Size = UDim2.fromOffset(OpenPillCfg.W - 4, OpenPillCfg.H - 4)}, 0.08)
end)
OpenPill.MouseButton1Up:Connect(function()
    Tween(OpenPill, {Size = UDim2.fromOffset(OpenPillCfg.W, OpenPillCfg.H)}, 0.12)
end)

OpenPill.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
end)

-- ============================================
--  显隐联动（带淡入淡出）
-- ============================================
local function _pillShow()
    OpenPill.Visible = true
    OpenPillBorder.Visible = true
    OpenPill.BackgroundTransparency = 1
    OpenPill.TextTransparency = 1
    Tween(OpenPill, {BackgroundTransparency = _baseTrans}, 0.2)
end

local function _pillHide()
    OpenPill.Visible = false
    OpenPillBorder.Visible = false
end

MainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
    if MainFrame.Visible then
        _pillHide()
    else
        _pillShow()
    end
end)

OpenPill.Visible = false
OpenPillBorder.Visible = false
MainFrame.Visible = true

    UserInputService.InputBegan:Connect(function(input, gpe)
        if not gpe and Keybind and input.KeyCode == Keybind then
            MainFrame.Visible = not MainFrame.Visible
        end
    end)

    -- ⑫ Category / Tab / TabDivider
    Window._currentCategory = nil
    function Window:Category(config)
        local name = type(config) == "table" and config.Name or config
        local collapsible = type(config) == "table" and config.Collapsible or false
        local opened = true
        if type(config) == "table" and config.Opened ~= nil then opened = config.Opened end
        local categoryFrame = Instance.new("Frame")
        categoryFrame.Size = UDim2.new(1, 0, 0, 0)
        categoryFrame.AutomaticSize = Enum.AutomaticSize.Y
        categoryFrame.BackgroundTransparency = 1
        categoryFrame.Parent = LeftScrollingFrame
        local catLayout = Instance.new("UIListLayout")
        catLayout.FillDirection = Enum.FillDirection.Vertical
        catLayout.SortOrder = Enum.SortOrder.LayoutOrder
        catLayout.Padding = UDim.new(0, 0); catLayout.Parent = categoryFrame
        local header = Instance.new("TextButton")
        header.Size = UDim2.new(1, 0, 0, 28)
        header.BackgroundTransparency = 1
        header.Text = name
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Font = Enum.Font.GothamBold
        header.TextSize = 13
        header.TextColor3 = CurrentTheme.Text
        header.TextTransparency = 0.5
        header.Parent = categoryFrame
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10); pad.Parent = header
        AddToRegistry(header, "TextColor3", "Text")
        local arrow = Instance.new("ImageLabel")
        arrow.Size = UDim2.new(0, 12, 0, 12)
        arrow.BackgroundTransparency = 1
        arrow.Image = "rbxassetid://8240930340"
        arrow.ImageColor3 = CurrentTheme.Text
        arrow.ImageTransparency = 0.3
        arrow.Visible = collapsible
        arrow.Rotation = opened and 0 or 180
        arrow.Parent = header
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.new(1, -10, 0.5, 0)
        AddToRegistry(arrow, "ImageColor3", "Text")
        local content = Instance.new("Frame")
        content.Size = UDim2.new(1, 0, 0, 0)
        content.BackgroundTransparency = 1
        content.AutomaticSize = Enum.AutomaticSize.None
        content.ClipsDescendants = true
        content.Visible = true; content.Parent = categoryFrame
        local contentList = Instance.new("UIListLayout")
        contentList.Padding = UDim.new(0, 4)
        contentList.SortOrder = Enum.SortOrder.LayoutOrder
        contentList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        contentList.Parent = content
        local currentTween = nil
        local function getContentHeight() return contentList.AbsoluteContentSize.Y or 0 end
        local function setContentHeight(targetHeight, animate)
            targetHeight = math.max(0, targetHeight)
            local currentHeight = content.Size.Y.Offset
            if animate and currentHeight ~= targetHeight then
                if currentTween then currentTween:Cancel(); currentTween = nil end
                currentTween = TweenService:Create(content, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetHeight)})
                currentTween:Play()
                currentTween.Completed:Connect(function() currentTween = nil; task.spawn(updateTabCanvas) end)
            else
                content.Size = UDim2.new(1, 0, 0, targetHeight)
                task.spawn(updateTabCanvas)
            end
        end
        local function toggleCategory()
            if not collapsible then return end
            opened = not opened
            Tween(arrow, {Rotation = opened and 0 or 180}, 0.25)
            local targetHeight = opened and getContentHeight() or 0
            setContentHeight(targetHeight, true)
        end
        header.MouseButton1Click:Connect(toggleCategory)
        contentList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            if opened then
                local h = getContentHeight()
                if math.abs(h - content.Size.Y.Offset) > 0.5 then setContentHeight(h, false) end
            end
        end)
        task.spawn(function()
            task.wait()
            local h = getContentHeight()
            local initialHeight = opened and h or 0
            content.Size = UDim2.new(1, 0, 0, initialHeight)
            updateTabCanvas()
        end)
        Window._currentCategory = {frame = categoryFrame, content = content, contentList = contentList, header = header, label = header, arrow = arrow, collapsible = collapsible, opened = opened, toggle = toggleCategory}
        table.insert(ThemeListeners, function() header.TextColor3 = CurrentTheme.Text; arrow.ImageColor3 = CurrentTheme.Text end)
        return Window._currentCategory
    end

    function Window:TabDivider()
        local parentContainer = LeftScrollingFrame
        if Window._currentCategory then parentContainer = Window._currentCategory.content end
        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, -20, 0, 1)
        line.Position = UDim2.new(0, 10, 0, 0)
        line.BackgroundColor3 = CurrentTheme.Stroke
        line.BackgroundTransparency = 0.5
        line.BorderSizePixel = 0; line.Parent = parentContainer
        AddToRegistry(line, "BackgroundColor3", "Stroke")
    end

    -- ⑬ Tab（右侧页面）
    Window._activeTab = nil
    Window._tabs = {}
    function Window:Tab(name, icon)
        local parentContainer = LeftScrollingFrame
        if Window._currentCategory then parentContainer = Window._currentCategory.content end
        local TabBtn = Instance.new("TextButton")
        TabBtn.Size = UDim2.new(1, -7, 0, 32)
        TabBtn.BackgroundTransparency = 1
        TabBtn.BackgroundColor3 = CurrentTheme.Top
        TabBtn.Text = ""; TabBtn.Parent = parentContainer
        Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 10)
        local glowFrame = Instance.new("Frame")
        glowFrame.Size = UDim2.new(1, 0, 1, 0)
        glowFrame.BackgroundColor3 = CurrentTheme.Accent
        glowFrame.BackgroundTransparency = 1
        glowFrame.Parent = TabBtn
        Instance.new("UICorner", glowFrame).CornerRadius = UDim.new(0, 10)
        local glowGrad = Instance.new("UIGradient")
        glowGrad.Color = ColorSequence.new(CurrentTheme.Accent, CurrentTheme.Accent)
        glowGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1)})
        glowGrad.Parent = glowFrame
        local ContentFrame = Instance.new("Frame")
        ContentFrame.Size = UDim2.new(1, 0, 1, 0)
        ContentFrame.BackgroundTransparency = 1
        ContentFrame.Parent = TabBtn
        local Layout = Instance.new("UIListLayout")
        Layout.FillDirection = Enum.FillDirection.Horizontal
        Layout.VerticalAlignment = Enum.VerticalAlignment.Center
        Layout.Padding = UDim.new(0, 5); Layout.Parent = ContentFrame
        local Padding = Instance.new("UIPadding")
        Padding.PaddingLeft = UDim.new(0, 10); Padding.Parent = ContentFrame
        if icon then
            local TabIcon = Instance.new("ImageLabel")
            TabIcon.Size = UDim2.new(0, 28, 0, 28)
            TabIcon.BackgroundTransparency = 1
            TabIcon.Image = ResolveIcon(icon) or ""
            TabIcon.Parent = ContentFrame
            AddToRegistry(TabIcon, "ImageColor3", "Text")
            Instance.new("UICorner", TabIcon).CornerRadius = UDim.new(0, 8)
        end
        local TabText = Instance.new("TextLabel")
        TabText.Size = UDim2.new(1, -40, 0, 15)
        TabText.BackgroundTransparency = 1
        TabText.Font = Enum.Font.GothamMedium
        TabText.Text = name
        TabText.TextColor3 = CurrentTheme.Text
        TabText.TextTransparency = 0.3; TabText.TextSize = 14
        TabText.TextXAlignment = Enum.TextXAlignment.Left
        TabText.Parent = ContentFrame
        AddToRegistry(TabText, "TextColor3", "Text")
        local Page = Instance.new("ScrollingFrame")
        Page.Size = UDim2.new(1, 0, 1, 0)
        Page.BackgroundTransparency = 1
        Page.ScrollBarThickness = 0
        Page.ScrollingEnabled = true
        Page.Visible = false
        Page.Position = UDim2.new(0, 0, 0, 60)
        Page.Parent = PageContainer
        Instance.new("UICorner", Page).CornerRadius = UDim.new(0, 16)
        Page.ClipsDescendants = true
        local PageContent = Instance.new("Frame")
        PageContent.Size = UDim2.new(1, 0, 0, 0)
        PageContent.AutomaticSize = Enum.AutomaticSize.Y
        PageContent.BackgroundTransparency = 1
        PageContent.Parent = Page
        local PageList = Instance.new("UIListLayout")
        PageList.Padding = UDim.new(0, 8)
        PageList.SortOrder = Enum.SortOrder.LayoutOrder
        PageList.HorizontalAlignment = Enum.HorizontalAlignment.Left
        PageList.Parent = PageContent
        local function updatePageCanvas()
            Page.CanvasSize = UDim2.new(0, 0, 0, PageList.AbsoluteContentSize.Y + 10)
        end
        PageList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updatePageCanvas)
        task.spawn(updatePageCanvas)
        local state = {isActive = false, btn = TabBtn, page = Page, textLabel = TabText, glow = glowFrame}
        TabBtn.MouseButton1Click:Connect(function()
            if Window._activeTab == state then return end
            for _, s in ipairs(Window._tabs) do
                s.btn.BackgroundTransparency = 1
                s.isActive = false
                s.glow.BackgroundTransparency = 1
                if s.textLabel then Tween(s.textLabel, {TextTransparency = 0.3}, 0.2) end
            end
            TabBtn.BackgroundTransparency = 1
            state.isActive = true
            state.glow.BackgroundTransparency = 0
            Tween(TabText, {TextTransparency = 0}, 0.2)
            if Window._activeTab then Window._activeTab.page.Visible = false end
            Page.Visible = true
            Tween(Page, {Position = UDim2.new(0, 0, 0, 0)}, 0.5)
            Window._activeTab = state
        end)
        if not Window._activeTab then
            TabBtn.BackgroundTransparency = 1
            state.isActive = true
            state.glow.BackgroundTransparency = 0
            TabText.TextTransparency = 0
            Page.Visible = true
            Page.Position = UDim2.new(0, 0, 0, 0)
            Window._activeTab = state
        end
        table.insert(Window._tabs, state)
        if name == "Config" then TabBtn.LayoutOrder = 99998 end
        if name == "Settings" then TabBtn.LayoutOrder = 99999 end
        table.insert(ThemeListeners, function()
            for _, s in ipairs(Window._tabs) do
                local glow = s.glow
                if glow then
                    glow.BackgroundColor3 = CurrentTheme.Accent
                    local grad = glow:FindFirstChildOfClass("UIGradient")
                    if grad then grad.Color = ColorSequence.new(CurrentTheme.Accent, CurrentTheme.Accent) end
                end
                s.btn.BackgroundTransparency = 1
            end
        end)
        local _tabBuilder = createSectionBuilder(PageContent, PageContent, 330, 1, Window)
        state.builder = _tabBuilder
        return _tabBuilder
    end

-- ============================================================
-- ⑭ 特效引擎 + 内置设置页
-- 用法：Tab:ThemeTab() / Tab:AccountTab() / Tab:WindowTab() / Tab:EffectTab() / Tab:ConfigTab()
-- ============================================================
local EffectState    = { matrix=false, rain=false, sakura=false, stars=false, snow=false, glitch=false }
local EffectContainers = {}
local EffectConns      = {}

local function StopEffect(key)
    if EffectConns[key] then EffectConns[key]:Disconnect(); EffectConns[key] = nil end
    if EffectContainers[key] then EffectContainers[key]:Destroy(); EffectContainers[key] = nil end
end

local function StartEffect(key)
    StopEffect(key)
    local container = Instance.new("Frame")
    container.Name = "UIEffect_" .. key
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, 0, 1, 0)
    container.ClipsDescendants = true
    container.ZIndex = 150
    container.Parent = MainFrame
    EffectContainers[key] = container
    local size = MainFrame.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        RunService.Heartbeat:Wait()
        size = MainFrame.AbsoluteSize
    end
    if size.X <= 0 or size.Y <= 0 then
        size = Vector2.new(500, 299)
    end

    if key == "matrix" then
        -- 片假名/数字/符号 = 代码雨飘落字符池，可自由替换
        local GLYPHS = {
            "ア","イ","ウ","エ","オ","カ","キ","ク","ケ","コ",
            "サ","シ","ス","セ","ソ","タ","チ","ツ","テ","ト",
            "ナ","ニ","ヌ","ネ","ノ","ハ","ヒ","フ","ヘ","ホ",
            "0","1","2","3","4","5","6","7","8","9","X","Z","#","%","*","&"
        }
        local t = 0
        EffectConns[key] = RunService.RenderStepped:Connect(function(dt)
            if not container.Parent then StopEffect(key); return end
            t += dt
            if t < 0.04 then return end
            t = 0
            for _ = 1, 2 do
                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(0, 14, 0, 14)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.Code
                label.TextSize = 12
                label.Text = GLYPHS[math.random(#GLYPHS)]
                label.ZIndex = 151
                if math.random() < 0.20 then
                    label.TextColor3 = Color3.fromRGB(220, 255, 220)
                    label.TextTransparency = 0.05
                else
                    label.TextColor3 = Color3.fromRGB(0, 255, 100)
                    label.TextTransparency = math.random(15, 35) / 100
                end
                local colStep = 14
                local colIndex = math.random(0, math.max(1, math.floor(size.X / colStep) - 1))
                local startX = colIndex * colStep + 2
                label.Position = UDim2.new(0, startX, 0, -15)
                label.Parent = container
                local tw = TweenService:Create(label,
                    TweenInfo.new(math.random(140, 250) / 100, Enum.EasingStyle.Linear),
                    { Position = UDim2.new(0, startX, 0, size.Y + 15), TextTransparency = 1 })
                tw:Play()
                tw.Completed:Connect(function() label:Destroy() end)
            end
        end)

    elseif key == "rain" then
        EffectConns[key] = RunService.RenderStepped:Connect(function()
            if not container.Parent then StopEffect(key); return end
            for _ = 1, 2 do
                local drop = Instance.new("Frame")
                drop.Size = UDim2.new(0, 1, 0, math.random(12, 22))
                drop.BackgroundColor3 = Color3.fromRGB(200, 225, 255)
                drop.BackgroundTransparency = math.random(35, 65) / 100
                drop.BorderSizePixel = 0
                drop.Rotation = -25
                drop.ZIndex = 151
                local startX = math.random(-50, math.floor(size.X))
                drop.Position = UDim2.new(0, startX, 0, -20)
                drop.Parent = container
                local tw = TweenService:Create(drop,
                    TweenInfo.new(math.random(30, 50) / 100, Enum.EasingStyle.Linear),
                    { Position = UDim2.new(0, startX + (size.Y * 0.45), 0, size.Y + 30), BackgroundTransparency = 1 })
                tw:Play()
                tw.Completed:Connect(function() drop:Destroy() end)
            end
        end)

    elseif key == "sakura" then
        local PETAL_COLORS = {
            Color3.fromRGB(255, 183, 197), Color3.fromRGB(255, 192, 203),
            Color3.fromRGB(255, 209, 220), Color3.fromRGB(248, 200, 220),
            Color3.fromRGB(255, 105, 180),
        }
        local t = 0
        EffectConns[key] = RunService.RenderStepped:Connect(function(dt)
            if not container.Parent then StopEffect(key); return end
            t += dt
            if t < 0.12 then return end
            t = 0
            local petal = Instance.new("Frame")
            petal.Size = UDim2.new(0, math.random(8, 14), 0, math.random(12, 18))
            petal.BackgroundColor3 = PETAL_COLORS[math.random(#PETAL_COLORS)]
            petal.BackgroundTransparency = math.random(10, 35) / 100
            petal.BorderSizePixel = 0
            petal.Rotation = math.random(0, 360)
            petal.ZIndex = 151
            Instance.new("UICorner", petal).CornerRadius = UDim.new(0.6, 0)
            local startX = math.random(-30, math.floor(size.X + 30))
            petal.Position = UDim2.new(0, startX, 0, -20)
            petal.Parent = container
            local spin = (math.random() > 0.5 and 1 or -1) * math.random(180, 540)
            local tw = TweenService:Create(petal,
                TweenInfo.new(math.random(350, 600) / 100, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Position = UDim2.new(0, startX + math.random(-80, 100), 0, size.Y + 25),
                  Rotation = petal.Rotation + spin, BackgroundTransparency = 1 })
            tw:Play()
            tw.Completed:Connect(function() petal:Destroy() end)
        end)

    elseif key == "stars" then
        local SPARKLE_ICONS = { "✦", "✧", "★", "✨", "✺", "✶" }
        local SPARKLE_COLORS = {
            Color3.fromRGB(255, 223, 128), Color3.fromRGB(255, 255, 255),
            Color3.fromRGB(200, 230, 255), Color3.fromRGB(255, 192, 230),
            Color3.fromRGB(220, 180, 255),
        }
        local t = 0
        EffectConns[key] = RunService.RenderStepped:Connect(function(dt)
            if not container.Parent then StopEffect(key); return end
            t += dt
            if t < 0.08 then return end
            t = 0
            local baseSize = math.random(10, 18)
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(0, baseSize, 0, baseSize)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.SourceSansBold
            label.TextSize = baseSize
            label.Text = SPARKLE_ICONS[math.random(#SPARKLE_ICONS)]
            label.TextColor3 = SPARKLE_COLORS[math.random(#SPARKLE_COLORS)]
            label.TextTransparency = 1
            label.Rotation = math.random(-30, 30)
            label.ZIndex = 151
            local startX = math.random(10, math.max(10, math.floor(size.X - 20)))
            local startY = math.random(10, math.max(10, math.floor(size.Y - 20)))
            label.Position = UDim2.new(0, startX, 0, startY)
            label.Parent = container
            local lifetime = math.random(120, 220) / 100
            local floatDist = math.random(15, 35)
            local fadeIn = TweenService:Create(label,
                TweenInfo.new(lifetime * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = math.random(0, 20) / 100,
                  Position = UDim2.new(0, startX, 0, startY - floatDist * 0.4),
                  Rotation = label.Rotation + 15,
                  Size = UDim2.new(0, baseSize + 4, 0, baseSize + 4) })
            local fadeOut = TweenService:Create(label,
                TweenInfo.new(lifetime * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { TextTransparency = 1,
                  Position = UDim2.new(0, startX + math.random(-10, 10), 0, startY - floatDist),
                  Rotation = label.Rotation + math.random(-45, 45),
                  Size = UDim2.new(0, baseSize - 2, 0, baseSize - 2) })
            fadeIn:Play()
            fadeIn.Completed:Connect(function() fadeOut:Play() end)
            fadeOut.Completed:Connect(function() label:Destroy() end)
        end)

    elseif key == "snow" then
        local t = 0
        EffectConns[key] = RunService.RenderStepped:Connect(function(dt)
            if not container.Parent then StopEffect(key); return end
            t += dt
            if t < 0.08 then return end
            t = 0
            local flakeSize = math.random(3, 6)
            local flake = Instance.new("Frame")
            flake.Size = UDim2.new(0, flakeSize, 0, flakeSize)
            flake.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            flake.BackgroundTransparency = math.random(10, 40) / 100
            flake.BorderSizePixel = 0
            flake.ZIndex = 151
            Instance.new("UICorner", flake).CornerRadius = UDim.new(1, 0)
            local startX = math.random(-20, math.floor(size.X + 20))
            flake.Position = UDim2.new(0, startX, 0, -10)
            flake.Parent = container
            local tw = TweenService:Create(flake,
                TweenInfo.new(math.random(250, 450) / 100, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { Position = UDim2.new(0, startX + math.random(-40, 60), 0, size.Y + 15), BackgroundTransparency = 1 })
            tw:Play()
            tw.Completed:Connect(function() flake:Destroy() end)
        end)

    elseif key == "glitch" then
        local GLITCH_COLORS = {
            Color3.fromRGB(0, 255, 240), Color3.fromRGB(255, 0, 115),
            Color3.fromRGB(255, 230, 0), Color3.fromRGB(0, 150, 255),
            Color3.fromRGB(255, 255, 255),
        }
        local t = 0
        EffectConns[key] = RunService.RenderStepped:Connect(function(dt)
            if not container.Parent then StopEffect(key); return end
            t += dt
            if t < math.random(3, 8) / 100 then return end
            t = 0
            for _ = 1, math.random(1, 3) do
                local thickness = math.random(1, 4)
                local width = size.X * (math.random(20, 95) / 100)
                local line = Instance.new("Frame")
                line.Size = UDim2.new(0, width, 0, thickness)
                line.BackgroundColor3 = GLITCH_COLORS[math.random(#GLITCH_COLORS)]
                line.BackgroundTransparency = math.random(10, 30) / 100
                line.BorderSizePixel = 0
                line.ZIndex = 151
                local startX = math.random(-10, math.max(0, math.floor(size.X - width + 10)))
                local startY = math.random(5, math.max(5, math.floor(size.Y - thickness)))
                line.Position = UDim2.new(0, startX, 0, startY)
                line.Parent = container
                local tw = TweenService:Create(line,
                    TweenInfo.new(math.random(4, 12) / 100, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                    { Position = UDim2.new(0, startX + math.random(-25, 25), 0, startY), BackgroundTransparency = 1 })
                tw:Play()
                tw.Completed:Connect(function() line:Destroy() end)
            end
        end)
    end
end

-- ===== ① 主题区 =====
local function BuildThemeTab(builder, cfg)
    cfg = type(cfg) == "table" and cfg or {}
    local sec = builder:Section({ Name = cfg.Name or "主题区", SubName = cfg.SubName or "选择界面主题，实时生效" })
    local themeValues = { "红色", "蓝色", "绿色" }
    local cur = CurrentThemeName
    if not table.find(themeValues, cur) then cur = "蓝色" end
    sec:Dropdown({
        Name = "主题", Desc = "红 / 蓝 / 绿 三套主题", Values = themeValues, Value = cur,
        Callback = function(v) KG_UI:SetTheme(v) end,
    })
    sec:Toggle({
        Name = "文字渐变", Desc = "标题文字扫光效果", Value = TextGradient.Enabled,
        Callback = function(en) TextGradient:SetEnabled(en) end,
    })
    return sec
end

-- ===== ② 账号 =====
local function BuildAccountTab(builder, cfg)
    cfg = type(cfg) == "table" and cfg or {}
    local sec = builder:Section({ Name = cfg.Name or "账号", Collapsible = false })
    local card = sec:UserFrame({
        Name    = cfg.PlayerName or LocalPlayer.DisplayName,
        Profile = Players:GetUserThumbnailAsync(LocalPlayer.UserId,
            Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150),
        Expires = cfg.PlayerSub or LocalPlayer.Name,
        ButtonIcon = 9405931578,
        Names        = { "副名字", "名字" },
        Placeholders = { "输入副名字", "输入名字" },
        Defaults     = { LocalPlayer.DisplayName, LocalPlayer.Name },
        OnChanged = function(idx, text)
            if idx == 1 then
                AccountName.Text = (text ~= "" and text) or LocalPlayer.DisplayName
            elseif idx == 2 then
                ExpireLabel.Text = (text ~= "" and text) or LocalPlayer.Name
            end
        end,
    })
    Window._playerCard = card
    Window._userCard = card
    return sec
end

-- ===== ③ 窗口配置 =====
local function BuildWindowTab(builder, cfg)
    cfg = type(cfg) == "table" and cfg or {}
    local sec = builder:Section({ Name = cfg.Name or "窗口配置" })
    sec:Keybind({
        Name = "菜单绑定键", Desc = "点击后按下新按键，立即生效", Default = Keybind or Enum.KeyCode.RightShift, Mode = "Toggle",
        Callback = function() end,
        OnKeyChanged = function(newKey)
            local kc = Enum.KeyCode[newKey]
            if kc then Window:SetKeybind(kc) end
        end,
    })
    sec:Button({ Name = "重置窗口位置", Desc = "窗口回到屏幕中央", Callback = function()
        Tween(MainFrame, { Position = UDim2.new(0.5, 0, 0.5, 0) }, 0.35)
    end })
    sec:Button({ Name = "最小化窗口", Callback = function() MainFrame.Visible = false end })
    sec:Button({ Name = "销毁界面", Desc = "彻底关闭并清除", Callback = function() Window:Destroy() end })
    return sec
end

-- ===== ④ 界面特效 =====
local function BuildEffectTab(builder, cfg)
    cfg = type(cfg) == "table" and cfg or {}
    local sec = builder:Section({ Name = cfg.Name or "界面特效", SubName = cfg.SubName or "可多选，点应用生效" })
    local fxList = {
        { "matrix", "代码雨" }, { "rain", "下雨" }, { "sakura", "花瓣" },
        { "stars", "星空" }, { "snow", "雪花" }, { "glitch", "错误" },
    }
    local fxNames = {}
    for _, ef in ipairs(fxList) do table.insert(fxNames, ef[2]) end
    local fxDrop = sec:Dropdown({ Name = "选择特效", Desc = "可多选", Values = fxNames, Multi = true, Value = {} })
    sec:Button({ Name = "应用", Desc = "应用所选特效；取消勾选后再点应用可关闭", Callback = function()
        local arr = fxDrop:GetValue()
        local sel = {}
        for _, v in ipairs(type(arr) == "table" and arr or {}) do sel[v] = true end
        for _, ef in ipairs(fxList) do
            local on = sel[ef[2]] == true
            if on ~= (EffectState[ef[1]] == true) then
                EffectState[ef[1]] = on
                if on then StartEffect(ef[1]) else StopEffect(ef[1]) end
            end
        end
    end })
    return sec
end

-- ===== ⑤ 配置区（适配 KG_UI 自带 ConfigObjects）=====
local function BuildConfigTab(builder, cfg)
    cfg = type(cfg) == "table" and cfg or {}
    local sec = builder:Section({
        Name    = cfg.Name    or "配置区",
        SubName = cfg.SubName or "保存 / 加载 / 删除本地配置",
    })

    local CONFIG_DIR = "KG_UI_Configs"
    local ConfigName = ""
    local dropdownObj
    local ConfigPaths = {}

    local function RefreshConfigs()
        pcall(function()
            if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        end)
        local newList = { "None" }
        local newPaths = {}
        pcall(function()
            if isfolder(CONFIG_DIR) then
                for _, file in ipairs(listfiles(CONFIG_DIR)) do
                    local name = file:gsub(".*[/\\]", ""):gsub("%.json$", "")
                    if name ~= "" then
                        table.insert(newList, name)
                        newPaths[name] = file
                    end
                end
            end
        end)
        ConfigPaths = newPaths
        if dropdownObj and dropdownObj.Refresh then
            dropdownObj:Refresh(newList)
        end
    end

    sec:Input({
        Name = "配置名字", Placeholder = "输入配置名",
        Callback = function(val) ConfigName = val end,
    })

    dropdownObj = sec:Dropdown({
        Name = "选择配置", Values = { "None" },
        Callback = function(val) Window.CurrentConfig = val end,
    })

    sec:Button({ Name = "刷新列表", Callback = RefreshConfigs })

    sec:Button({
        Name = "保存配置",
        Callback = function()
            if ConfigName == "" then return end
            KG_UI:SaveConfig(ConfigName, CONFIG_DIR)
            Window.CurrentConfig = ConfigName
            RefreshConfigs()
        end,
    })

    sec:Button({
        Name = "加载配置",
        Callback = function()
            local name = Window.CurrentConfig
            if not name or name == "None" then return end
            local path = ConfigPaths[name] or (CONFIG_DIR .. "/" .. name .. ".json")
            KG_UI:LoadConfig(path)
        end,
    })

    sec:Button({
        Name = "删除配置",
        Callback = function()
            local name = Window.CurrentConfig
            if not name or name == "None" then return end
            local paths = {
                ConfigPaths[name],
                CONFIG_DIR .. "/" .. name .. ".json",
                CONFIG_DIR .. "\\" .. name .. ".json",
            }
            pcall(function()
                for _, path in ipairs(paths) do
                    if path and isfile(path) then delfile(path); break end
                end
            end)
            Window.CurrentConfig = "None"
            task.wait(0.05)
            RefreshConfigs()
            if dropdownObj and dropdownObj.Reset then dropdownObj:Reset() end
        end,
    })

    RefreshConfigs()
    return sec
end

-- ===== 给每个 Tab 附加 5 个方法：一行一个区 =====
local _origTab = Window.Tab
function Window:Tab(name, icon)
    local builder = _origTab(self, name, icon)
    builder.ThemeTab   = function(_, c) return BuildThemeTab(builder, c)   end
    builder.AccountTab = function(_, c) return BuildAccountTab(builder, c) end
    builder.WindowTab  = function(_, c) return BuildWindowTab(builder, c)  end
    builder.EffectTab  = function(_, c) return BuildEffectTab(builder, c)  end
    builder.ConfigTab  = function(_, c) return BuildConfigTab(builder, c)  end
    return builder
end

    -- ⑮ HomeTab
    function Window:CreateHomeTab(a, b)
        -- 两种用法：
        --   旧: Window:CreateHomeTab({...})                 → 自动创建"仪表盘"Tab
        --   新: Window:CreateHomeTab(Window:Tab("仪表盘"), {...})  → 接你自己创建的Tab
        local Config, TabBuilder
        if type(a) == "table" and type(a.Section) == "function" then
            TabBuilder = a
            Config = type(b) == "table" and b or {}
        else
            Config = type(a) == "table" and a or {}
            TabBuilder = Window:Tab(Config.Title or Config.Name or "仪表盘", Config.Icon or Config.Logo or "rbxassetid://9904843409")
        end
        local title  = Config.Title or Config.Name or "仪表盘"
        local icon   = Config.Icon or Config.Logo
        local qqLink = tostring(Config.QQGroup or "https://qm.qq.com/q/GDgGTuT66I")

        local function _CheckObsidianCompat()
            local missing = {}
            local function Need(name, ok)
                if not ok then table.insert(missing, name) end
            end

            Need("cloneref",          (cloneref or clonereference))
            Need("getgenv",           getgenv)
            Need("gethui",            gethui)
            Need("protectgui",        (syn and syn.protect_gui) or protectgui)
            Need("getcustomasset",    getcustomasset)
            Need("writefile",         writefile)
            Need("readfile",          readfile)
            Need("isfile",            isfile)
            Need("isfolder",          isfolder)
            Need("makefolder",        makefolder)
            Need("listfiles",         listfiles)
            Need("delfile",           delfile)
            Need("setclipboard",      setclipboard or toclipboard or set_clipboard or (syn and syn.write_clipboard))
            Need("request",           (syn and syn.request) or http_request or request)
            Need("sethiddenproperty", sethiddenproperty)
            Need("setscriptable",     setscriptable)

            return (#missing == 0), missing
        end

        local _ObsidianOK, _ObsidianMissing = _CheckObsidianCompat()

        local changelog = Config.ScriptChangelog or Config.Changelog or {}
        local segCfg    = type(Config.Segments) == "table" and Config.Segments or {}

        local tabState = nil
        for _, _st in ipairs(Window._tabs) do
            if _st.builder == TabBuilder then tabState = _st break end
        end
        if not tabState then return TabBuilder end
        local Page = tabState.page
        local PageContent = Page:FindFirstChildWhichIsA("Frame")
        if not PageContent then return TabBuilder end

        local Player       = LocalPlayer
        local ExecutorName = "Unknown"
        local Region       = "未知"
        local TimeFunction = RunService:IsRunning() and time or os.clock
        local StartedAt    = TimeFunction()

        pcall(function()
            if identifyexecutor then
                local ok, name = pcall(identifyexecutor)
                if ok and name then ExecutorName = tostring(name) end
            end
        end)
        pcall(function()
            Region = game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(Player)
        end)

local HourText = {
	[0] = "零点啦，该睡了",
	[1] = "凌晨一点，还不睡？",
	[2] = "两点多了，眼皮打架了吧",
	[3] = "三点，夜猫子上线",
	[4] = "四点，天快亮了",
	[5] = "五点，你不会通宵了吧",
	[6] = "六点，早安",
	[7] = "七点，该吃早饭了",
	[8] = "八点，上午开始了",
	[9] = "九点，干活时间",
	[10] = "十点，喝口水吧",
	[11] = "十一点，快到中午了",
	[12] = "十二点，该吃午饭了",
	[13] = "一点了，午休一下吧",
	[14] = "两点，下午茶时间",
	[15] = "三点，下午过半了",
	[16] = "四点，摸摸鱼",
	[17] = "五点，快吃晚饭了",
	[18] = "六点，晚饭时间",
	[19] = "七点，晚上好",
	[20] = "八点，夜生活开始",
	[21] = "九点，该洗澡了",
	[22] = "十点，要睡觉了哦",
	[23] = "十一点了，困不困呀",
}

local function Greeting()
	local h = math.floor(workspace:GetServerTimeNow() % 86400 / 3600)
	return HourText[h]
end

        local function Elapsed()
            local e = math.max(0, TimeFunction() - StartedAt)
            if e < 60 then return math.floor(e) .. " 秒" end
            if e < 3600 then return math.floor(e / 60) .. " 分" end
            return math.floor(e / 3600) .. " 小时"
        end

        local function Panel(parent, size, pos)
            local p = Instance.new("Frame")
            p.BackgroundColor3 = CurrentTheme.Top
            p.BackgroundTransparency = 0.25
            p.BorderSizePixel = 0
            p.ClipsDescendants = true
            p.Size = size
            p.Position = pos or UDim2.fromOffset(0, 0)
            p.Parent = parent
            Instance.new("UICorner", p).CornerRadius = UDim.new(0, 8)
            local s = Instance.new("UIStroke")
            s.Color = CurrentTheme.Stroke
            s.Transparency = 0.68
            s.Parent = p
            table.insert(ThemeListeners, function()
                p.BackgroundColor3 = CurrentTheme.Top
                s.Color = CurrentTheme.Stroke
            end)
            return p
        end

        local function MakeText(parent, txt, sz, bold, transp)
            local l = Instance.new("TextLabel")
            l.BackgroundTransparency = 1
            l.BorderSizePixel = 0
            l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
            l.Text = tostring(txt or "")
            l.TextColor3 = CurrentTheme.Text
            l.TextSize = sz or 12
            l.TextTransparency = transp or 0
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.TextYAlignment = Enum.TextYAlignment.Center
            l.TextTruncate = Enum.TextTruncate.AtEnd
            l.Parent = parent
            AddToRegistry(l, "TextColor3", "Text")
            return l
        end

        local function MakeIcon(parent, src, sz, color)
            local i = Instance.new("ImageLabel")
            i.BackgroundTransparency = 1
            i.BorderSizePixel = 0
            i.Size = UDim2.fromOffset(sz or 16, sz or 16)
            i.ScaleType = Enum.ScaleType.Fit
            i.ImageColor3 = color or CurrentTheme.Text
            if type(src) == "number" then
                i.Image = "rbxassetid://" .. src
            elseif type(src) == "string" and src ~= "" then
                if tonumber(src) then
                    i.Image = "rbxassetid://" .. src
                elseif src:match("^rbxasset") or src:match("^http") then
                    i.Image = src
                else
                    i.Image = "rbxassetid://" .. src
                end
            end
            i.Parent = parent
            table.insert(ThemeListeners, function()
                i.ImageColor3 = CurrentTheme.Text
            end)
            return i
        end

        local function FitTextToWidth(Label, BaseSize, MinSize, Wrapped)
            BaseSize = BaseSize or Label.TextSize
            MinSize = MinSize or 8
            Label.TextSize = BaseSize
            defer(function()
                if not Label or not Label.Parent then return end
                local W = math.max(1, Label.AbsoluteSize.X)
                local H = math.max(1, Label.AbsoluteSize.Y)
                local sz = BaseSize
                while sz > MinSize do
                    local b = TextService:GetTextSize(Label.Text, sz, Label.Font,
                        Wrapped and Vector2.new(W, math.huge) or Vector2.new(math.huge, H))
                    if b.X <= W and (not Wrapped or b.Y <= H) then break end
                    sz = sz - 1
                end
                Label.TextSize = sz
            end)
        end

        local Root = Instance.new("Frame")
        Root.Name = "HomeDashboard"
        Root.Size = UDim2.new(1, -8, 0, 0)
        Root.AutomaticSize = Enum.AutomaticSize.Y
        Root.BackgroundTransparency = 1
        Root.BorderSizePixel = 0
        Root.Parent = PageContent
        local RL = Instance.new("UIListLayout")
        RL.Padding = UDim.new(0, 8)
        RL.SortOrder = Enum.SortOrder.LayoutOrder
        RL.Parent = Root

        local HomeFonts = {}
        do
            local function tryLoad(relPath, weight, style)
                if type(getcustomasset) ~= "function" then return nil end
                if type(isfile) == "function" then
                    local ok, exists = pcall(isfile, relPath)
                    if not ok or not exists then return nil end
                end
                local ok, asset = pcall(getcustomasset, relPath)
                if not ok or not asset or asset == "" then return nil end
                local ok2, font = pcall(Font.new, asset, weight or Enum.FontWeight.Regular, style or Enum.FontStyle.Normal)
                return ok2 and font or nil
            end
            HomeFonts.eyebrow = tryLoad("BasedHub/fonts/Archivo-ExpandedBold.ttf", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
            HomeFonts.title = tryLoad("BasedHub/fonts/InstrumentSerif-Italic.ttf", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
            HomeFonts.body = tryLoad("BasedHub/fonts/Inter-Regular.ttf", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
            if not HomeFonts.eyebrow then HomeFonts.eyebrow = Font.fromEnum(Enum.Font.GothamBold) end
            if not HomeFonts.title then
                local ok, f = pcall(function()
                    return Font.fromName("Merriweather", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
                end)
                HomeFonts.title = ok and f or Font.fromEnum(Enum.Font.GothamBold)
            end
            if not HomeFonts.body then HomeFonts.body = Font.fromEnum(Enum.Font.Gotham) end
        end

        local Profile = Panel(Root, UDim2.new(1, 0, 0, 170))
        Profile.LayoutOrder = 1
        Profile.ClipsDescendants = true

        local Banner = Instance.new("ImageLabel")
        Banner.Name = "Still"
        Banner.BackgroundTransparency = 1
        Banner.BorderSizePixel = 0
        Banner.Image = "rbxassetid://135781374174090"
        Banner.ScaleType = Enum.ScaleType.Crop
        Banner.Size = UDim2.new(0.62, 0, 1, -40)
        Banner.Position = UDim2.fromScale(1, 0)
        Banner.AnchorPoint = Vector2.new(1, 0)
        Banner.ImageTransparency = 0.25
        Banner.Parent = Profile
        Instance.new("UICorner", Banner).CornerRadius = UDim.new(0, 8)
        local BannerFade = Instance.new("UIGradient")
        BannerFade.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.55, 0.35),
            NumberSequenceKeypoint.new(1, 0.1),
        })
        BannerFade.Parent = Banner

        local HeroText = Instance.new("Frame")
        HeroText.Name = "Text"
        HeroText.BackgroundTransparency = 1
        HeroText.Size = UDim2.new(0.66, 0, 1, -40)
        HeroText.Parent = Profile
        local TP = Instance.new("UIPadding")
        TP.PaddingTop = UDim.new(0, 14)
        TP.PaddingRight = UDim.new(0, 0)
        TP.PaddingBottom = UDim.new(0, 14)
        TP.PaddingLeft = UDim.new(0, 24)
        TP.Parent = HeroText
        local TL = Instance.new("UIListLayout")
        TL.SortOrder = Enum.SortOrder.LayoutOrder
        TL.VerticalAlignment = Enum.VerticalAlignment.Bottom
        TL.Padding = UDim.new(0, 6)
        TL.Parent = HeroText

        local Eyebrow = Instance.new("Frame")
        Eyebrow.Name = "Eyebrow"
        Eyebrow.BackgroundTransparency = 1
        Eyebrow.Size = UDim2.new(1, 0, 0, 20)
        Eyebrow.LayoutOrder = 1
        Eyebrow.Parent = HeroText
        local EL = Instance.new("UIListLayout")
        EL.FillDirection = Enum.FillDirection.Horizontal
        EL.VerticalAlignment = Enum.VerticalAlignment.Center
        EL.Padding = UDim.new(0, 8)
        EL.SortOrder = Enum.SortOrder.LayoutOrder
        EL.Parent = Eyebrow

        local Pip = Instance.new("Frame")
        Pip.Name = "Pip"
        Pip.Size = UDim2.fromOffset(7, 7)
        Pip.BorderSizePixel = 0
        Pip.LayoutOrder = 1
        Pip.BackgroundColor3 = CurrentTheme.Accent
        Pip.Parent = Eyebrow
        Instance.new("UICorner", Pip).CornerRadius = UDim.new(1, 0)
        table.insert(ThemeListeners, function()
            Pip.BackgroundColor3 = CurrentTheme.Accent
        end)

        local PipRing = Instance.new("Frame")
        PipRing.Name = "Ring"
        PipRing.AnchorPoint = Vector2.new(0.5, 0.5)
        PipRing.Position = UDim2.fromScale(0.5, 0.5)
        PipRing.Size = UDim2.fromScale(1, 1)
        PipRing.BackgroundColor3 = CurrentTheme.Accent
        PipRing.BackgroundTransparency = 0.5
        PipRing.BorderSizePixel = 0
        PipRing.Parent = Pip
        Instance.new("UICorner", PipRing).CornerRadius = UDim.new(1, 0)
        table.insert(ThemeListeners, function()
            PipRing.BackgroundColor3 = CurrentTheme.Accent
        end)

        local pipPhase, pipConn = 0, nil
        pipConn = RunService.RenderStepped:Connect(function(dt)
            if not (Pip.Parent and PipRing.Parent) then
                if pipConn then pipConn:Disconnect(); pipConn = nil end
                return
            end
            pipPhase = (pipPhase + dt / 1.8) % 1
            local p = 1 - (1 - pipPhase) ^ 3
            PipRing.Size = UDim2.fromScale(1 + p * 2.4, 1 + p * 2.4)
            PipRing.BackgroundTransparency = 0.5 + 0.5 * p
        end)

        local EyebrowText = Instance.new("TextLabel")
        EyebrowText.Name = "EyebrowText"
        EyebrowText.BackgroundTransparency = 1
        EyebrowText.BorderSizePixel = 0
        EyebrowText.FontFace = HomeFonts.eyebrow
        EyebrowText.TextSize = 10
        EyebrowText.Text = "KG_UI"
        EyebrowText.TextColor3 = CurrentTheme.Accent
        EyebrowText.TextXAlignment = Enum.TextXAlignment.Left
        EyebrowText.TextYAlignment = Enum.TextYAlignment.Center
        EyebrowText.Size = UDim2.new(0, 0, 0, 14)
        EyebrowText.AutomaticSize = Enum.AutomaticSize.X
        EyebrowText.LayoutOrder = 2
        EyebrowText.Parent = Eyebrow
        AddToRegistry(EyebrowText, "TextColor3", "Accent")

        local HeroTitle = Instance.new("TextLabel")
        HeroTitle.Name = "HeroTitle"
        HeroTitle.BackgroundTransparency = 1
        HeroTitle.BorderSizePixel = 0
        HeroTitle.FontFace = HomeFonts.title
        HeroTitle.TextSize = 46
        HeroTitle.Text = "你好，" .. Player.DisplayName
        HeroTitle.TextColor3 = CurrentTheme.Text
        HeroTitle.TextXAlignment = Enum.TextXAlignment.Left
        HeroTitle.TextYAlignment = Enum.TextYAlignment.Center
        HeroTitle.TextTruncate = Enum.TextTruncate.AtEnd
        HeroTitle.Size = UDim2.new(1, 0, 0, 0)
        HeroTitle.AutomaticSize = Enum.AutomaticSize.Y
        HeroTitle.LayoutOrder = 2
        HeroTitle.Parent = HeroText
        AddToRegistry(HeroTitle, "TextColor3", "Text")
        TextGradient:Add(HeroTitle)

        local HeroSub = Instance.new("TextLabel")
        HeroSub.Name = "HeroSub"
        HeroSub.BackgroundTransparency = 1
        HeroSub.BorderSizePixel = 0
        HeroSub.FontFace = HomeFonts.body
        HeroSub.TextSize = 13
        HeroSub.Text = "@" .. Player.Name
        HeroSub.TextColor3 = CurrentTheme.Text
        HeroSub.TextTransparency = 0.25
        HeroSub.TextXAlignment = Enum.TextXAlignment.Left
        HeroSub.TextYAlignment = Enum.TextYAlignment.Center
        HeroSub.TextWrapped = true
        HeroSub.Size = UDim2.new(1, 0, 0, 0)
        HeroSub.AutomaticSize = Enum.AutomaticSize.Y
        HeroSub.LayoutOrder = 3
        HeroSub.Parent = HeroText
        AddToRegistry(HeroSub, "TextColor3", "SubText")
        TextGradient:Skip(HeroSub)

        local SegBox = Instance.new("Frame")
        SegBox.Name = "SegBar"
        SegBox.AnchorPoint = Vector2.new(0, 1)
        SegBox.Position = UDim2.new(0, 12, 1, -4)
        SegBox.Size = UDim2.new(1, -24, 0, 34)
        SegBox.BackgroundTransparency = 1
        SegBox.BorderSizePixel = 0
        SegBox.Parent = Profile
        local SL = Instance.new("UIListLayout")
        SL.FillDirection = Enum.FillDirection.Horizontal
        SL.HorizontalAlignment = Enum.HorizontalAlignment.Left
        SL.VerticalAlignment = Enum.VerticalAlignment.Center
        SL.SortOrder = Enum.SortOrder.LayoutOrder
        SL.Padding = UDim.new(0, 8)
        SL.Parent = SegBox

        local CH = Instance.new("Frame")
        CH.BackgroundTransparency = 1
        CH.BorderSizePixel = 0
        CH.Size = UDim2.new(1, 0, 0, 0)
        CH.AutomaticSize = Enum.AutomaticSize.Y
        CH.LayoutOrder = 3
        CH.Parent = Root

        local function NewPage(parent)
            local f = Instance.new("Frame")
            f.BackgroundTransparency = 1
            f.BorderSizePixel = 0
            f.Size = UDim2.new(1, 0, 0, 0)
            f.AutomaticSize = Enum.AutomaticSize.Y
            f.Visible = false
            f.Parent = parent
            local l = Instance.new("UIListLayout")
            l.Padding = UDim.new(0, 8)
            l.SortOrder = Enum.SortOrder.LayoutOrder
            l.Parent = f
            return f, l
        end

        local DetailsPage = NewPage(CH)
        local ScriptPage  = NewPage(CH)

        local segButtons = {}
        local function MakeSegment(segName, text, ic)
            local lblW = math.max(60,
                TextService:GetTextSize(tostring(text), 12, Enum.Font.GothamBold,
                    Vector2.new(math.huge, math.huge)).X + 4)
            local btnW = 36 + lblW + 14
            local bt = Panel(SegBox, UDim2.fromOffset(btnW, 34))
            bt.BackgroundTransparency = 0.55

            local icn = MakeIcon(bt, ic, 16, CurrentTheme.Text)
            icn.Position = UDim2.new(0, 12, 0.5, -8)
            icn.ImageTransparency = 0.3

            local lbl = MakeText(bt, text, 12, true, 0.25)
            lbl.Position = UDim2.new(0, 36, 0, 0)
            lbl.Size = UDim2.new(1, -44, 1, 0)

            segButtons[segName] = { Root = bt, Icon = icn, Label = lbl }

            local hit = Instance.new("TextButton")
            hit.Size = UDim2.fromScale(1, 1)
            hit.BackgroundTransparency = 1
            hit.Text = ""
            hit.AutoButtonColor = false
            hit.Parent = bt

            hit.MouseButton1Click:Connect(function()
                DetailsPage.Visible = (segName == "Details")
                ScriptPage.Visible  = (segName == "Script")
                for n, s in pairs(segButtons) do
                    local active = (n == segName)
                    Tween(s.Root, {BackgroundTransparency = active and 0.08 or 0.55}, 0.2)
                    s.Icon.ImageColor3  = active and CurrentTheme.Accent or CurrentTheme.Text
                    s.Label.TextColor3  = active and CurrentTheme.Accent or CurrentTheme.Text
                    s.Label.TextTransparency = active and 0 or 0.25
                end
            end)
        end

        local segSpec = {
            Details = segCfg.Details or segCfg[1] or {},
            Script  = segCfg.Script  or segCfg[2] or {},
        }
        local showDetails = segSpec.Details.Show ~= false and Config.ShowDetailsSegment ~= false
        local showScript  = segSpec.Script.Show  ~= false and Config.ShowScriptSegment  ~= false

        if showDetails then
            MakeSegment("Details",
                segSpec.Details.Text or segSpec.Details.Name or Config.DetailsText or "详情信息",
                segSpec.Details.Icon or Config.DetailsIcon or 9904843409)
        end
        if showScript then
            MakeSegment("Script",
                segSpec.Script.Text or segSpec.Script.Name or Config.ScriptText or "脚本更新",
                segSpec.Script.Icon or Config.ScriptIcon or 9904743710)
        end

        local DW = Instance.new("Frame")
        DW.BackgroundTransparency = 1
        DW.BorderSizePixel = 0
        DW.Size = UDim2.new(1, 0, 0, 0)
        DW.AutomaticSize = Enum.AutomaticSize.Y
        DW.LayoutOrder = 1
        DW.Parent = DetailsPage
        local DWL = Instance.new("UIListLayout")
        DWL.FillDirection = Enum.FillDirection.Horizontal
        DWL.SortOrder = Enum.SortOrder.LayoutOrder
        DWL.Padding = UDim.new(0, 8)
        DWL.Parent = DW

        local LeftCol = Instance.new("Frame")
        LeftCol.BackgroundTransparency = 1
        LeftCol.BorderSizePixel = 0
        LeftCol.Size = UDim2.new(0.52, -4, 0, 0)
        LeftCol.AutomaticSize = Enum.AutomaticSize.Y
        LeftCol.LayoutOrder = 1
        LeftCol.Parent = DW
        local LCL = Instance.new("UIListLayout")
        LCL.Padding = UDim.new(0, 8)
        LCL.SortOrder = Enum.SortOrder.LayoutOrder
        LCL.Parent = LeftCol

        local RightCol = Instance.new("Frame")
        RightCol.BackgroundTransparency = 1
        RightCol.BorderSizePixel = 0
        RightCol.Size = UDim2.new(0.48, -4, 0, 0)
        RightCol.AutomaticSize = Enum.AutomaticSize.Y
        RightCol.LayoutOrder = 2
        RightCol.Parent = DW
        local RCL = Instance.new("UIListLayout")
        RCL.Padding = UDim.new(0, 8)
        RCL.SortOrder = Enum.SortOrder.LayoutOrder
        RCL.Parent = RightCol

        local ServerCard = Panel(LeftCol, UDim2.new(1, 0, 0, 162))
        ServerCard.LayoutOrder = 1

        local SvrT = MakeText(ServerCard, "服务器", 15, true, 0)
        SvrT.Position = UDim2.fromOffset(16, 12)
        SvrT.Size = UDim2.new(1, -32, 0, 18)

        local SvrS = MakeText(ServerCard, "当前会话的信息", 10, false, 0.48)
        SvrS.Position = UDim2.fromOffset(16, 30)
        SvrS.Size = UDim2.new(1, -32, 0, 14)

        local StatLabels = {}
        local function MakeStat(parent, ttl, val, xScale, y, wScale)
            local st = Panel(parent, UDim2.new(wScale, -6, 0, 42),
                UDim2.new(xScale, 3, 0, y))
            st.BackgroundTransparency = 0.3
            local t = MakeText(st, ttl, 10, true, 0.13)
            t.Position = UDim2.fromOffset(10, 6)
            t.Size = UDim2.new(1, -20, 0, 13)
            local v = MakeText(st, val, 10, false, 0.35)
            v.Position = UDim2.fromOffset(10, 20)
            v.Size = UDim2.new(1, -20, 0, 13)
            return v
        end

        StatLabels.Players  = MakeStat(ServerCard, "玩家",       "0 人在玩", 0,    58, 0.5)
        StatLabels.Capacity = MakeStat(ServerCard, "最大玩家数", tostring(Players.MaxPlayers).." 人", 0.5, 58, 0.5)
        StatLabels.Latency  = MakeStat(ServerCard, "延迟",       "...",      0,    104, 0.33)
        StatLabels.Region   = MakeStat(ServerCard, "地区", tostring(Region), 0.33, 104, 0.34)
        StatLabels.Runtime  = MakeStat(ServerCard, "时长",   "0 秒",     0.67, 104, 0.33)

        local QQCard = Panel(LeftCol, UDim2.new(1, 0, 0, 68))
        QQCard.LayoutOrder = 2
        QQCard.BackgroundColor3 = CurrentTheme.Accent
        QQCard.BackgroundTransparency = 0.18
        table.insert(ThemeListeners, function()
            QQCard.BackgroundColor3 = CurrentTheme.Accent
        end)
        local QGrad = Instance.new("UIGradient")
        QGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, CurrentTheme.Accent),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 17, 22)),
        })
        QGrad.Parent = QQCard

        local QTitle = MakeText(QQCard, "QQ 群", 20, true, 0)
        QTitle.Position = UDim2.fromOffset(18, 12)
        QTitle.Size = UDim2.new(1, -36, 0, 25)

        local QSub = MakeText(QQCard,
            qqLink ~= "" and "点击复制 QQ 群链接" or "未配置 QQ 群链接",
            12, false, 0.25)
        QSub.Position = UDim2.fromOffset(18, 38)
        QSub.Size = UDim2.new(1, -36, 0, 18)

        local QClick = Instance.new("TextButton")
        QClick.Size = UDim2.fromScale(1, 1)
        QClick.BackgroundTransparency = 1
        QClick.Text = ""
        QClick.AutoButtonColor = false
        QClick.Parent = QQCard
        QClick.MouseButton1Click:Connect(function()
            if qqLink == "" then return end
            pcall(function()
                if setclipboard then setclipboard(qqLink)
                elseif toclipboard then toclipboard(qqLink)
                elseif set_clipboard then set_clipboard(qqLink) end
            end)
        end)

        local ExecutorCard = Panel(RightCol, UDim2.new(1, 0, 0, 92))
        ExecutorCard.LayoutOrder = 1

        local ExecStatus = "未知"
        local ExecColor  = CurrentTheme.Accent

        if _ObsidianOK then
            ExecStatus = "你的注入器完全兼容"
            ExecColor  = Color3.fromRGB(45, 180, 115)
        elseif #_ObsidianMissing <= 3 then
            ExecStatus = "部分兼容：缺少 " .. table.concat(_ObsidianMissing, ", ") .. "（只能使用UI的部分功能）"
            ExecColor  = Color3.fromRGB(230, 170, 60)
        else
            ExecStatus = "不兼容殺脚本：缺少 " .. table.concat(_ObsidianMissing, ", ")
            ExecColor  = Color3.fromRGB(220, 70, 70)
        end

        ExecutorCard.BackgroundColor3 = ExecColor
        ExecutorCard.BackgroundTransparency = 0.18
        local EGrad = Instance.new("UIGradient")
        EGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, ExecColor),
            ColorSequenceKeypoint.new(0.58, Color3.fromRGB(13, 17, 22)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
        })
        EGrad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.08),
            NumberSequenceKeypoint.new(0.55, 0),
            NumberSequenceKeypoint.new(1, 0),
        })
        EGrad.Parent = ExecutorCard

        local ETitle = MakeText(ExecutorCard, ExecutorName, 17, true, 0)
        ETitle.Position = UDim2.fromOffset(18, 16)
        ETitle.Size = UDim2.new(1, -36, 0, 22)

        local ESub = MakeText(ExecutorCard, ExecStatus, 12, false, 0.15)
        ESub.Position = UDim2.fromOffset(18, 42)
        ESub.Size = UDim2.new(1, -36, 0, 40)
        ESub.TextWrapped = true
        ESub.TextTruncate = Enum.TextTruncate.None
        ESub.TextYAlignment = Enum.TextYAlignment.Top
        FitTextToWidth(ESub, 12, 8, true)

        local FriendsCard = Panel(RightCol, UDim2.new(1, 0, 0, 166))
        FriendsCard.LayoutOrder = 2

        local FTitle = MakeText(FriendsCard, "好友", 16, true, 0)
        FTitle.Position = UDim2.fromOffset(16, 12)
        FTitle.Size = UDim2.new(1, -32, 0, 20)

        local FSub = MakeText(FriendsCard, "查看你的好友现在在做什么", 10, false, 0.48)
        FSub.Position = UDim2.fromOffset(16, 32)
        FSub.Size = UDim2.new(1, -32, 0, 14)

        local FriendLabels = {}
        FriendLabels.InServer = MakeStat(FriendsCard, "本服务器", "...", 0,   58,  0.5)
        FriendLabels.Offline  = MakeStat(FriendsCard, "离线",     "...", 0.5, 58,  0.5)
        FriendLabels.Online   = MakeStat(FriendsCard, "在线",     "...", 0,   104, 0.5)
        FriendLabels.All      = MakeStat(FriendsCard, "全部",     "...", 0.5, 104, 0.5)

        local function FillChangelog(Page, Entries, EmptyText)
            local Holder = Panel(Page, UDim2.new(1, 0, 0, 40))
            Holder.AutomaticSize = Enum.AutomaticSize.Y
            local L = Instance.new("UIListLayout")
            L.Padding = UDim.new(0, 8)
            L.SortOrder = Enum.SortOrder.LayoutOrder
            L.Parent = Holder
            local P = Instance.new("UIPadding")
            P.PaddingTop = UDim.new(0, 12)
            P.PaddingBottom = UDim.new(0, 12)
            P.PaddingLeft = UDim.new(0, 12)
            P.PaddingRight = UDim.new(0, 12)
            P.Parent = Holder

            if type(Entries) ~= "table" or #Entries <= 0 then
                local em = MakeText(Holder, EmptyText, 13, false, 0.25)
                em.Size = UDim2.new(1, 0, 0, 26)
                return
            end

            for i, Entry in ipairs(Entries) do
                local Item = Panel(Holder, UDim2.new(1, 0, 0, 62))
                Item.LayoutOrder = i
                local t = MakeText(Item,
                    tostring(Entry.Title or Entry.Name or ("更新 " .. i)),
                    14, true, 0)
                t.Position = UDim2.fromOffset(14, 10)
                t.Size = UDim2.new(1, -28, 0, 18)
                local d = MakeText(Item,
                    tostring(Entry.Description or Entry.Content or Entry.Date or ""),
                    11, false, 0.3)
                d.Position = UDim2.fromOffset(14, 30)
                d.Size = UDim2.new(1, -28, 0, 22)
                d.TextWrapped = true
                d.TextTruncate = Enum.TextTruncate.None
                d.TextYAlignment = Enum.TextYAlignment.Top
            end
        end

        FillChangelog(ScriptPage, changelog, "暂无脚本更新")

        local FriendCache = {
            All = "...", Online = "...", Offline = "...", InServer = "...",
            Cooldown = 0,
        }
        local function UpdateFriends()
            if FriendCache.Cooldown > 0 then
                FriendCache.Cooldown = FriendCache.Cooldown - 1
                return
            end
            FriendCache.Cooldown = 30
            task.spawn(function()
                local done = false
                task.delay(8, function() done = true end)
                local OnlineFriends, TotalFriends, InServer = 0, 0, 0
                pcall(function()
                    OnlineFriends = #Player:GetFriendsOnline()
                end)
                if done then return end
                pcall(function()
                    local Pages = Players:GetFriendsAsync(Player.UserId)
                    while true do
                        if done then return end
                        for _, Data in ipairs(Pages:GetCurrentPage()) do
                            TotalFriends = TotalFriends + 1
                            if Players:FindFirstChild(Data.Username) then
                                InServer = InServer + 1
                            end
                        end
                        if Pages.IsFinished then break end
                        Pages:AdvanceToNextPageAsync()
                    end
                end)
                if done then return end
                done = true
                FriendCache.All      = tostring(TotalFriends) .. " 个好友"
                FriendCache.Online   = tostring(OnlineFriends) .. " 个好友"
                FriendCache.Offline  = tostring(math.max(TotalFriends - OnlineFriends, 0)) .. " 个好友"
                FriendCache.InServer = InServer > 0 and tostring(InServer) .. " 个好友" or "无好友"
            end)
        end

        local Accumulator = 0
        local function UpdateHome(dt)
            Accumulator = Accumulator + (dt or 0)
            if Accumulator < 0.5 then return end
            Accumulator = 0

            local Ping = "..."
            pcall(function()
                Ping = tostring(math.floor((Player:GetNetworkPing() * 1000) + 0.5)) .. "ms"
            end)

            HeroTitle.Text = "你好，" .. Player.DisplayName
            HeroSub.Text = Greeting() .. " | @" .. Player.Name
            if StatLabels.Players  then StatLabels.Players.Text  = tostring(#Players:GetPlayers()) .. " 人在玩" end
            if StatLabels.Capacity then StatLabels.Capacity.Text = tostring(Players.MaxPlayers) .. " 人" end
            if StatLabels.Latency  then StatLabels.Latency.Text  = Ping end
            if StatLabels.Runtime  then StatLabels.Runtime.Text  = Elapsed() end
            if FriendLabels.InServer then FriendLabels.InServer.Text = FriendCache.InServer end
            if FriendLabels.Offline  then FriendLabels.Offline.Text  = FriendCache.Offline end
            if FriendLabels.Online   then FriendLabels.Online.Text   = FriendCache.Online end
            if FriendLabels.All      then FriendLabels.All.Text      = FriendCache.All end
            UpdateFriends()
        end

        DetailsPage.Visible = true
        if segButtons["Details"] then
            segButtons["Details"].Root.BackgroundTransparency = 0.08
            segButtons["Details"].Icon.ImageColor3 = CurrentTheme.Accent
            segButtons["Details"].Label.TextColor3 = CurrentTheme.Accent
            segButtons["Details"].Label.TextTransparency = 0
        end

        local HomeConn = RunService.RenderStepped:Connect(UpdateHome)
        Window._homeCleanup = Window._homeCleanup or {}
        table.insert(Window._homeCleanup, function()
            safeDisconnect(HomeConn)
            if pipConn then pipConn:Disconnect(); pipConn = nil end
        end)

        TabBuilder.HomeRoot = Root
        TabBuilder.GetHomeSection = function() return Root end
        return TabBuilder
    end

    -- 仪表盘快捷方式：Window:HomeTab(...) 本身就是创建一个 Tab
    Window.HomeTab = Window.CreateHomeTab

    -- ⑰ 窗口 API
    function Window:SetKeybind(key) Keybind = key end
    function Window:Destroy()
        for _, fn in ipairs(Window._homeCleanup or {}) do pcall(fn) end
        Window._homeCleanup = nil
        ScreenGui:Destroy()
    end
    function Window:SetSubtitle(newSubtitle) WindowContent.Text = newSubtitle or "" end

    function Window:SetAccount(cfg)
        cfg = cfg or {}
        if cfg.ShowUser == false then
            AccountProfile.Image = ""
            AccountProfile.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
            AccountProfile.BackgroundTransparency = 0.25
            AccountProfile.ImageColor3 = CurrentTheme.Accent
            AccountName.Text = cfg.Expires  or "自定义菜单"
            ExpireLabel.Text = cfg.Username or "设置"
            if Window._userCard then
                Window._userCard:SetValue(1, cfg.Expires  or "自定义菜单")
                Window._userCard:SetValue(2, cfg.Username or "设置")
            end
        else
            AccountProfile.Image = cfg.Profile
                or Players:GetUserThumbnailAsync(LocalPlayer.UserId,
                    Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
            AccountProfile.BackgroundColor3 = Color3.new(1, 1, 1)
            AccountProfile.BackgroundTransparency = 1
            AccountName.Text = cfg.Expires  or AccNameCfg or LocalPlayer.DisplayName
            ExpireLabel.Text = cfg.Username or AccSubCfg  or LocalPlayer.Name
            if Window._userCard then
                Window._userCard:SetValue(1, cfg.Expires  or AccNameCfg or LocalPlayer.DisplayName)
                Window._userCard:SetValue(2, cfg.Username or AccSubCfg  or LocalPlayer.Name)
                if cfg.Profile then Window._userCard:SetProfile(cfg.Profile) end
            end
        end
    end
    Window:SetAccount({ ShowUser = (Config.ShowUser ~= false) })

    return Window
end

return KG_UI
