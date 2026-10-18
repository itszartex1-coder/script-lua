--[[
    MONO AIM v3.6 | ESCANEO MANUAL DE COMPAÑEROS, SIN BUCLES AUTOMATICOS
    TIPO: Script NORMAL de Roblox; no es un LocalScript.
    UBICACION: StarterPlayer > StarterPlayerScripts
    IMPORTANTE: en Properties, configurar RunContext = Client.
    Esta es una herramienta CLIENTE para probar tu propio juego.
    El apuntado modifica la camara, no los proyectiles ni el dano del servidor.
    Desactiva o elimina las versiones viejas: dos copias activas causan lag.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local localPlayer = Players.LocalPlayer
if not localPlayer then
    warn("MONO AIM: este Script requiere RunContext = Client.")
    return
end
local playerGui = localPlayer:WaitForChild("PlayerGui")
--==================== AJUSTES ====================--
local CONFIG = {
    IGNORE_TEAMMATES = true,
    -- Si tu juego tiene equipos personalizados por atributo, usa este nombre.
    -- Cuando ambos jugadores tienen el mismo valor, no seran objetivos.
    CUSTOM_TEAM_ATTRIBUTE = "TeamId",
    -- Flechas verdes: se buscan SOLO al pulsar la tecla o el boton actualizar.
    -- No se comprueban al iniciar, al reaparecer ni periodicamente.
    ARROW_SCREEN_RADIUS = 70, -- tolerancia en pixeles alrededor de la cabeza
    MANUAL_GUI_BATCH = 75, -- ceder un frame durante una recarga para evitar tirones
    ESP_REFRESH_INTERVAL = 0.18, -- 5-6 veces/s, muerte se detecta por eventos
    TARGET_SEARCH_INTERVAL = 0.12, -- adquirir nuevo objetivo como maximo 8 veces/s
    ARROW_DEBUG = false, -- true: imprime nuevos aliados en Output
    WALL_PASS_TAG = "MonoPassWall",  -- etiqueta opcional para muros especiales
    WALL_RADIUS = 10,              -- estudia muros proximos al jugador
    WALL_SCAN_INTERVAL = 0.18,     -- colisiones ~5-6 veces/s, evita sobrecargar CPU
    MAX_DISTANCE = 700,          -- studs
    ACQUIRE_FOV = 290,          -- pixeles alrededor de la mira
    KEEP_FOV_MULTIPLIER = 1.65, -- evita saltos entre objetivos
    REQUIRE_VISIBILITY_AIMBOT = true,
    AIMLOCK_SPEED = 65,         -- seguimiento rapido, pero no instantaneo
    AIMBOT_INSTANT = true,      -- apunta sin retraso de suavizado
    AIMBOT_SPEED = 110,        -- solo se usa con AIMBOT_INSTANT = false
    PREDICTION_SECONDS = 0,    -- 0 es correcto para armas tipo raycast/hitscan
    PROJECTILE_SPEED = 0,      -- si tu arma usa balas fisicas, indica studs/s
}
local COLORS = {
    background = Color3.fromRGB(236, 237, 239),
    white = Color3.fromRGB(255, 255, 255),
    black = Color3.fromRGB(22, 23, 25),
    dark = Color3.fromRGB(37, 38, 41),
    gray = Color3.fromRGB(117, 120, 125),
    muted = Color3.fromRGB(177, 179, 184),
    off = Color3.fromRGB(89, 91, 96),
    green = Color3.fromRGB(45, 240, 97),
}
local enabled = {aimlock = false, aimbot = false, esp = false, wallpass = false}
local binds = {
    aimlock = Enum.KeyCode.Q,
    aimbot = Enum.KeyCode.E,
    esp = Enum.KeyCode.R,
    wallpass = Enum.KeyCode.T,
    allyscan = Enum.KeyCode.Y, -- actualiza aliados SOLO al pulsar esta tecla
}
local featureNames = {aimlock = "AIM LOCK", aimbot = "AIMBOT", esp = "ESP", wallpass = "ATRAVESAR PAREDES", allyscan = "ACTUALIZAR COMPAÑEROS"}
local lockedTarget = nil
local tracked = {}
local highlights = {}
local awaitingBind = nil
--==================== LIMPIEZA BASICA ====================--
local oldUI = playerGui:FindFirstChild("MonoAimV36_UI")
if oldUI then oldUI:Destroy() end
local folderName = "MonoAimV36_Highlights_" .. localPlayer.UserId
local oldFolder = Workspace:FindFirstChild(folderName)
if oldFolder then oldFolder:Destroy() end
local highlightFolder = Instance.new("Folder")
highlightFolder.Name = folderName
highlightFolder.Parent = Workspace
--==================== UTILIDADES UI ====================--
local function create(className, properties, parent)
    local obj = Instance.new(className)
    for key, value in pairs(properties or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end
local function corners(obj, radius)
    create("UICorner", {CornerRadius = UDim.new(0, radius)}, obj)
end
local function outline(obj, color, thickness)
    create("UIStroke", {
        Color = color,
        Thickness = thickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end
local gui = create("ScreenGui", {
    Name = "MonoAimV36_UI",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    DisplayOrder = 550,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local BASE_WIDTH, BASE_HEIGHT = 388, 650
local cameraForSizing = Workspace.CurrentCamera
local viewport = cameraForSizing and cameraForSizing.ViewportSize or Vector2.new(1280, 720)
local uiScaleValue = math.min(1, (viewport.X - 20) / BASE_WIDTH, (viewport.Y - 20) / BASE_HEIGHT)
uiScaleValue = math.max(0.4, uiScaleValue)
local panel = create("Frame", {
    Name = "PanelPrincipal",
    Size = UDim2.fromOffset(BASE_WIDTH, BASE_HEIGHT),
    Position = UDim2.fromOffset(
        math.max(0, (viewport.X - BASE_WIDTH * uiScaleValue) / 2),
        math.max(0, (viewport.Y - BASE_HEIGHT * uiScaleValue) / 2)
    ),
    BackgroundColor3 = COLORS.background,
    BorderSizePixel = 0,
    Active = true,
}, gui)
corners(panel, 15)
outline(panel, Color3.fromRGB(175, 178, 182), 1)
local panelScale = create("UIScale", {Scale = uiScaleValue}, panel)
local header = create("Frame", {
    Name = "ArrastrarPanel",
    BackgroundColor3 = COLORS.black,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 83),
    Active = true,
}, panel)
corners(header, 15)
create("Frame", {
    Position = UDim2.new(0, 0, 1, -15),
    Size = UDim2.new(1, 0, 0, 15),
    BackgroundColor3 = COLORS.black,
    BorderSizePixel = 0,
}, header)
create("TextLabel", {
    Name = "Titulo",
    Position = UDim2.fromOffset(19, 13),
    Size = UDim2.fromOffset(286, 29),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "MONO  /  AIM",
    TextSize = 21,
    TextColor3 = COLORS.white,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
create("TextLabel", {
    Position = UDim2.fromOffset(20, 48),
    Size = UDim2.fromOffset(270, 17),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "PANEL DE CONTROL  •  V3.6",
    TextSize = 11,
    TextColor3 = COLORS.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local minimize = create("TextButton", {
    Name = "Minimizar",
    Position = UDim2.fromOffset(329, 22),
    Size = UDim2.fromOffset(39, 34),
    Text = "−",
    TextSize = 24,
    Font = Enum.Font.GothamBold,
    TextColor3 = COLORS.white,
    BackgroundColor3 = COLORS.dark,
    BorderSizePixel = 0,
    AutoButtonColor = false,
}, header)
corners(minimize, 9)
create("TextLabel", {
    Position = UDim2.fromOffset(18, 95),
    Size = UDim2.fromOffset(348, 20),
    BackgroundTransparency = 1,
    Text = "FUNCIONES Y ATAJOS",
    TextColor3 = COLORS.black,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
create("TextLabel", {
    Position = UDim2.fromOffset(18, 116),
    Size = UDim2.fromOffset(350, 19),
    BackgroundTransparency = 1,
    Text = "Pulsa una tecla para asignar un nuevo atajo.",
    TextColor3 = COLORS.gray,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local rows = {}
local function createRow(key, y, title, description)
    local row = create("Frame", {
        Name = title,
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.fromOffset(360, 82),
        BackgroundColor3 = COLORS.dark,
        BorderSizePixel = 0,
    }, panel)
    corners(row, 12)
    create("TextLabel", {
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.fromOffset(220, 26),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = COLORS.white,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    create("TextLabel", {
        Position = UDim2.fromOffset(14, 40),
        Size = UDim2.fromOffset(195, 30),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = description,
        TextColor3 = COLORS.muted,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, row)
    local toggle = create("TextButton", {
        Name = "CambiarEstado",
        Position = UDim2.fromOffset(219, 23),
        Size = UDim2.fromOffset(62, 35),
        BackgroundColor3 = COLORS.off,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "OFF",
        TextColor3 = COLORS.white,
        TextSize = 12,
        AutoButtonColor = false,
    }, row)
    corners(toggle, 9)
    local shortcut = create("TextButton", {
        Name = "AsignarTecla",
        Position = UDim2.fromOffset(290, 23),
        Size = UDim2.fromOffset(57, 35),
        BackgroundColor3 = COLORS.black,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = binds[key].Name,
        TextColor3 = COLORS.white,
        TextSize = 13,
        AutoButtonColor = false,
    }, row)
    corners(shortcut, 9)
    outline(shortcut, Color3.fromRGB(98, 100, 106), 1)
    rows[key] = {toggle = toggle, shortcut = shortcut}
end
createRow("aimlock", 144, "AIM LOCK", "Sigue un objetivo fijo")
createRow("aimbot", 238, "AIMBOT", "Apuntado rapido y objetivo estable")
createRow("esp", 332, "ESP", "Silueta verde sin recuadro")
createRow("wallpass", 426, "PAREDES", "Atraviesa muros sin quitar colision al suelo")
local status = create("TextLabel", {
    Name = "Estado",
    Position = UDim2.fromOffset(18, 568),
    Size = UDim2.fromOffset(354, 30),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamMedium,
    Text = "Atajos: Q / E / R / T  •  Y actualizar aliados",
    TextColor3 = COLORS.gray,
    TextSize = 11,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
create("TextLabel", {
    Position = UDim2.fromOffset(18, 603),
    Size = UDim2.fromOffset(354, 33),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "Flechas verdes: SOLO recarga manual (Y).\nLos compañeros guardados se mantienen hasta salir.",
    TextColor3 = COLORS.gray,
    TextSize = 10,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, panel)
--==================== LISTA DE COMPAÑEROS ====================--
local alliesButton = create("TextButton", {
    Name = "ListaCompaneros",
    Position = UDim2.fromOffset(18, 521),
    Size = UDim2.fromOffset(352, 38),
    BackgroundColor3 = COLORS.black,
    Text = "COMPAÑEROS (0)    VER LISTA",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = COLORS.white,
    BorderSizePixel = 0,
    AutoButtonColor = true,
}, panel)
corners(alliesButton, 10)
local alliesOverlay = create("Frame", {
    Name = "GestionCompaneros",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    Visible = false,
    Active = true,
    ZIndex = 30,
    BackgroundColor3 = COLORS.black,
    BackgroundTransparency = 0.09,
    BorderSizePixel = 0,
}, panel)
corners(alliesOverlay, 15)
local alliesCard = create("Frame", {
    Position = UDim2.fromOffset(14, 92),
    Size = UDim2.fromOffset(360, 440),
    BackgroundColor3 = COLORS.dark,
    ZIndex = 31,
    BorderSizePixel = 0,
}, alliesOverlay)
corners(alliesCard, 13)
create("TextLabel", {
    Position = UDim2.fromOffset(15, 16),
    Size = UDim2.fromOffset(255, 29),
    Text = "COMPAÑEROS DETECTADOS",
    TextSize = 15,
    TextColor3 = COLORS.white,
    Font = Enum.Font.GothamBold,
    BackgroundTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 32,
}, alliesCard)
local closeAllies = create("TextButton", {
    Position = UDim2.fromOffset(309, 13),
    Size = UDim2.fromOffset(37, 34),
    Text = "X",
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    TextColor3 = COLORS.white,
    BackgroundColor3 = COLORS.off,
    BorderSizePixel = 0,
    ZIndex = 32,
}, alliesCard)
corners(closeAllies, 8)
local alliesInfo = create("TextLabel", {
    Position = UDim2.fromOffset(15, 52),
    Size = UDim2.fromOffset(325, 28),
    Text = "Sin detección automática. Pulsa Y para actualizar.",
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextColor3 = COLORS.muted,
    BackgroundTransparency = 1,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 32,
}, alliesCard)
local alliesScroll = create("ScrollingFrame", {
    Position = UDim2.fromOffset(13, 91),
    Size = UDim2.fromOffset(333, 257),
    BackgroundColor3 = COLORS.black,
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.white,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ZIndex = 32,
}, alliesCard)
corners(alliesScroll, 8)
create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, alliesScroll)
local alliesEmpty = create("TextLabel", {
    Position = UDim2.fromOffset(16, 352),
    Size = UDim2.fromOffset(328, 45),
    Text = "QUITAR = permitir que el apuntado vuelva a seleccionar a ese jugador.",
    TextSize = 11,
    TextColor3 = COLORS.muted,
    TextWrapped = true,
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 32,
}, alliesCard)
local rescanAllies = create("TextButton", {
    Name = "ReanalizarFlechas",
    Position = UDim2.fromOffset(15, 401),
    Size = UDim2.fromOffset(225, 29),
    Text = "ACTUALIZAR ALIADOS",
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextColor3 = COLORS.black,
    BackgroundColor3 = COLORS.white,
    BorderSizePixel = 0,
    ZIndex = 32,
}, alliesCard)
corners(rescanAllies, 7)
local scanHotkeyButton = create("TextButton", {
    Name = "TeclaActualizarAliados",
    Position = UDim2.fromOffset(249, 401),
    Size = UDim2.fromOffset(96, 29),
    Text = "TECLA: Y",
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextColor3 = COLORS.white,
    BackgroundColor3 = COLORS.off,
    BorderSizePixel = 0,
    ZIndex = 32,
}, alliesCard)
corners(scanHotkeyButton, 7)
scanHotkeyButton.Activated:Connect(function()
    awaitingBind = "allyscan"
    status.Text = "Pulsa una tecla para actualizar compañeros (ESC cancelar)"
    scanHotkeyButton.Text = "..."
end)
alliesButton.Activated:Connect(function() alliesOverlay.Visible = true end)
closeAllies.Activated:Connect(function() alliesOverlay.Visible = false end)

local bubble = create("TextButton", {
    Name = "BurbujaMovible",
    Visible = false,
    Position = UDim2.fromOffset(30, 120),
    Size = UDim2.fromOffset(66, 66),
    BackgroundColor3 = COLORS.black,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "AIM",
    TextSize = 16,
    TextColor3 = COLORS.white,
    AutoButtonColor = false,
    Active = true,
}, gui)
corners(bubble, 100)
outline(bubble, COLORS.white, 2)
-- Un aviso flotante independiente: funciona con la UI abierta o minimizada.
local notification = create("TextLabel", {
    Name = "AvisoActivacion",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 15),
    Size = UDim2.fromOffset(288, 43),
    BackgroundColor3 = COLORS.black,
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = COLORS.white,
    TextTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    Visible = false,
    BorderSizePixel = 0,
    ZIndex = 200,
}, gui)
corners(notification, 12)
outline(notification, Color3.fromRGB(85, 87, 92), 1)
local notificationSequence = 0
local notificationTween = nil
local function showNotification(message)
    notificationSequence += 1
    local thisSequence = notificationSequence
    if notificationTween then notificationTween:Cancel() end
    notification.Text = message
    notification.Visible = true
    notification.Position = UDim2.new(0.5, 0, 0, 15)
    notification.TextTransparency = 1
    notification.BackgroundTransparency = 1
    notificationTween = TweenService:Create(notification,
        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0, 25),
            BackgroundTransparency = 0.06,
            TextTransparency = 0,
        })
    notificationTween:Play()
    task.delay(1, function()
        if thisSequence ~= notificationSequence or not notification.Parent then return end
        notificationTween = TweenService:Create(notification,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                TextTransparency = 1,
                BackgroundTransparency = 1,
            })
        notificationTween:Play()
        task.delay(0.13, function()
            if thisSequence == notificationSequence and notification.Parent then
                notification.Visible = false
            end
        end)
    end)
end
--==================== MOVER Y MINIMIZAR ====================--
local dragState = nil
local bubbleMoved = false
local function screenSize()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or viewport
end
local function keepInside(frame)
    local sz = screenSize()
    local visibleSize = frame.AbsoluteSize
    frame.Position = UDim2.fromOffset(
        math.clamp(frame.AbsolutePosition.X, 0, math.max(0, sz.X - visibleSize.X)),
        math.clamp(frame.AbsolutePosition.Y, 0, math.max(0, sz.Y - visibleSize.Y))
    )
end
local function enableDrag(handle, element)
    handle.InputBegan:Connect(function(input)
        local kind = input.UserInputType
        if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
            return
        end
        if element == bubble then bubbleMoved = false end
        dragState = {
            element = element,
            start = Vector2.new(input.Position.X, input.Position.Y),
            original = element.AbsolutePosition,
            touch = (kind == Enum.UserInputType.Touch) and input or nil,
        }
    end)
end
enableDrag(header, panel)
enableDrag(bubble, bubble)
UserInputService.InputChanged:Connect(function(input)
    local drag = dragState
    if not drag then return end
    if drag.touch then
        if input ~= drag.touch then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end
    local now = Vector2.new(input.Position.X, input.Position.Y)
    local delta = now - drag.start
    if delta.Magnitude > 6 and drag.element == bubble then
        bubbleMoved = true
    end
    local element = drag.element
    local sz = screenSize()
    local objSize = element.AbsoluteSize
    element.Position = UDim2.fromOffset(
        math.clamp(drag.original.X + delta.X, 0, math.max(0, sz.X - objSize.X)),
        math.clamp(drag.original.Y + delta.Y, 0, math.max(0, sz.Y - objSize.Y))
    )
end)
UserInputService.InputEnded:Connect(function(input)
    local drag = dragState
    if drag and ((drag.touch and input == drag.touch)
        or (not drag.touch and input.UserInputType == Enum.UserInputType.MouseButton1)) then
        dragState = nil
    end
end)
minimize.Activated:Connect(function()
    bubble.Position = UDim2.fromOffset(panel.AbsolutePosition.X, panel.AbsolutePosition.Y)
    panel.Visible = false
    bubble.Visible = true
    keepInside(bubble)
end)
bubble.Activated:Connect(function()
    if bubbleMoved then return end
    panel.Position = UDim2.fromOffset(bubble.AbsolutePosition.X, bubble.AbsolutePosition.Y)
    bubble.Visible = false
    panel.Visible = true
    keepInside(panel)
end)
-- Adapta el panel cuando se modifica la ventana.
local lastViewport = viewport
local function updateViewport()
    local sz = screenSize()
    if sz == lastViewport then return end
    lastViewport = sz
    panelScale.Scale = math.max(0.4, math.min(1,
        (sz.X - 20) / BASE_WIDTH, (sz.Y - 20) / BASE_HEIGHT))
    if panel.Visible then keepInside(panel) end
    if bubble.Visible then keepInside(bubble) end
end
--==================== RECONOCIMIENTO DE FLECHAS DE EQUIPO ====================--
-- Busca indicadores de aliados que sean GUIs accesibles al cliente:
--   (1) BillboardGui sobre Head/Attachment del personaje,
--   (2) BillboardGui en nuestro PlayerGui con Adornee en ese personaje,
--   (3) icono verde de ScreenGui colocado sobre la cabeza en pantalla.
-- NO puede leer el color de los pixeles dentro de una imagen: si la flecha
-- es una imagen verde SIN tintar y sin nombre identificable, no hay forma
-- de reconocerla solo por su aspecto mediante las APIs normales de Roblox.
-- Solo se inicia al pulsar actualizar. Clasificacion persiste al respawnear.
local arrowAllies = {} -- [Player] = true: permanece hasta salir de la partida
local forcedEnemies = {} -- [Player] = true: excluido de la lista manualmente
-- NINGUN bucle automatico de busqueda: las flechas SOLO se revisan al actualizar.
local function isNativeAlly(player)
    local attr = CONFIG.CUSTOM_TEAM_ATTRIBUTE
    if attr and attr ~= "" then
        local mine = localPlayer:GetAttribute(attr)
        local theirs = player:GetAttribute(attr)
        if mine ~= nil and theirs ~= nil and mine == theirs then return "TeamId" end
    end
    if not localPlayer.Neutral and not player.Neutral then
        if localPlayer.Team and player.Team then
            if localPlayer.Team == player.Team then return "Equipo" end
        elseif localPlayer.TeamColor == player.TeamColor then
            return "Color del equipo"
        end
    end
    return nil
end
local function allyReason(player)
    if not player or player == localPlayer or forcedEnemies[player] then return nil end
    if arrowAllies[player] then return "Flecha verde" end
    return isNativeAlly(player)
end
local function refreshAllyList()
    -- Se llama solo cuando cambia la clasificacion o se abre una sesion.
    for _, child in ipairs(alliesScroll:GetChildren()) do
        if child.Name == "FilaCompanero" then child:Destroy() end
    end
    local members = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local reason = allyReason(player)
        if reason then table.insert(members, {player = player, reason = reason}) end
    end
    table.sort(members, function(a, b) return a.player.Name:lower() < b.player.Name:lower() end)
    alliesButton.Text = "COMPAÑEROS (" .. #members .. ")    VER LISTA"
    alliesInfo.Text = #members == 0 and "Todavia no hay compañeros identificados."
        or (#members .. " jugadores excluidos de Aim Lock y Aimbot")
    for i, info in ipairs(members) do
        local player = info.player
        local row = create("Frame", {
            Name = "FilaCompanero", LayoutOrder = i,
            Size = UDim2.new(1, -8, 0, 47), BackgroundColor3 = COLORS.off,
            BackgroundTransparency = 0.12, BorderSizePixel = 0,
            ZIndex = 33,
        }, alliesScroll)
        corners(row, 7)
        create("TextLabel", {
            Position = UDim2.fromOffset(8, 3), Size = UDim2.fromOffset(209, 39),
            Text = player.DisplayName .. " (@" .. player.Name .. ")\n" .. info.reason,
            TextSize = 10, Font = Enum.Font.GothamMedium,
            TextColor3 = COLORS.white, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
            ZIndex = 34,
        }, row)
        local remove = create("TextButton", {
            Name = "EliminarCompanero", Position = UDim2.fromOffset(223, 7),
            Size = UDim2.fromOffset(98, 33), BackgroundColor3 = COLORS.white,
            Text = "QUITAR", TextSize = 11, Font = Enum.Font.GothamBold,
            TextColor3 = COLORS.black, BorderSizePixel = 0, ZIndex = 34,
        }, row)
        corners(remove, 7)
        remove.Activated:Connect(function()
            forcedEnemies[player] = true
            arrowAllies[player] = nil
            refreshAllyList()
            showNotification(player.Name .. " quitado de compañeros")
        end)
    end
    alliesScroll.CanvasSize = UDim2.fromOffset(0, #members * 52)
end
local ARROW_NAMES = {"arrow", "flecha", "triangle", "triangulo", "indicator", "indicador", "marker", "marcador", "icon", "icono", "chevron"}
local ALLY_NAMES = {"ally", "allies", "friendly", "friend", "teammate", "compañero", "companero", "compa", "greenarrow", "green_arrow", "allyarrow"}
local NON_ARROW_NAMES = {"health", "hpbar", "healthbar", "health_bar", "vida", "stamina", "energy", "energia", "damage", "dano", "nameplate"}
local ARROW_SYMBOLS = {"▲", "▼", "▴", "▾", "↑", "⇧", "➤", "🔼", "🔽"}

local function nameIncludes(name, parts)
    name = string.lower(name or "")
    for _, text in ipairs(parts) do
        if string.find(name, text, 1, true) then return true end
    end
    return false
end

local function greenColor(color)
    -- Verde dominante: se admiten verdes claros y oscuros.
    return color.G >= 0.34 and color.G > color.R * 1.22
        and color.G > color.B * 1.17
end

local function visibleGui(node)
    local current = node
    while current do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and not current.Enabled then return false end
        current = current.Parent
        if current == playerGui or current == Workspace then break end
    end
    return true
end

local function markerLooksLikeGreenArrow(obj)
    if not obj:IsA("GuiObject") or not visibleGui(obj) then return false end

    -- El nombre de un contenedor padre tambien puede identificar la flecha.
    local combined = obj.Name
    local parent = obj.Parent
    if parent then combined ..= " " .. parent.Name end
    if parent and parent.Parent then combined ..= " " .. parent.Parent.Name end
    if nameIncludes(combined, NON_ARROW_NAMES) then return false end

    local arrowName = nameIncludes(combined, ARROW_NAMES)
    local explicitlyAlly = nameIncludes(combined, ALLY_NAMES)
    local hasArrowSymbol = false
    local hasGreen = false

    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        hasGreen = obj.ImageTransparency < 0.95 and greenColor(obj.ImageColor3)
    elseif obj:IsA("TextLabel") or obj:IsA("TextButton") then
        hasGreen = obj.TextTransparency < 0.95 and greenColor(obj.TextColor3)
        for _, symbol in ipairs(ARROW_SYMBOLS) do
            if string.find(obj.Text, symbol, 1, true) then
                hasArrowSymbol = true
                break
            end
        end
    end
    if obj.BackgroundTransparency < 0.75 and greenColor(obj.BackgroundColor3) then
        hasGreen = true
    end

    -- Un simbolo/texto o icono verde es una flecha probable. Los nombres
    -- "ally"/"friendly" cubren imagenes cuyo verde esta en el PNG.
    if explicitlyAlly and (arrowName or obj:IsA("ImageLabel") or obj:IsA("ImageButton") or hasArrowSymbol) then
        return true
    end
    if not hasGreen then return false end
    if arrowName or hasArrowSymbol then return true end
    return obj:IsA("ImageLabel") or obj:IsA("ImageButton")
end

local function billboardRefersToCharacter(billboard, character)
    if billboard:IsDescendantOf(character) then return true end
    local adorn = billboard.Adornee
    return adorn ~= nil and (adorn == character or adorn:IsDescendantOf(character))
end

local function greenArrowInsideBillboard(billboard)
    if not billboard.Enabled or not visibleGui(billboard) then return false end
    for _, obj in ipairs(billboard:GetDescendants()) do
        if markerLooksLikeGreenArrow(obj) then return true end
    end
    return false
end

-- Indice temporal para una sola recarga manual. Se construye una sola vez
-- por pulsacion, sin listeners de GUI ni intervalos en segundo plano.
local indexedBillboards = {}
local indexedScreenMarkers = {}

local function rebuildGuiIndex()
    table.clear(indexedBillboards)
    table.clear(indexedScreenMarkers)
    local descendants = playerGui:GetDescendants()
    for i, obj in ipairs(descendants) do
        if obj:IsA("BillboardGui") then
            table.insert(indexedBillboards, obj)
        elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton")
            or obj:IsA("TextLabel") or obj:IsA("TextButton") then
            if markerLooksLikeGreenArrow(obj) then
                local screenGui = obj:FindFirstAncestorOfClass("ScreenGui")
                if screenGui and screenGui ~= gui then
                    table.insert(indexedScreenMarkers, {marker = obj, screenGui = screenGui})
                end
            end
        end
        if i % CONFIG.MANUAL_GUI_BATCH == 0 then task.wait() end
    end
    table.clear(descendants)
end

local function scanForGreenArrow(player)
    local character = player.Character
    if not character or not character.Parent then return false end
    if player:GetAttribute("MonoFriendly") == true
        or character:GetAttribute("MonoFriendly") == true then
        return true
    end

    -- Indicadores sobre la cabeza; SOLO se consultan en una recarga manual.
    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BillboardGui") and greenArrowInsideBillboard(obj) then
            return true
        end
    end

    for _, billboard in ipairs(indexedBillboards) do
        if billboard.Parent and billboardRefersToCharacter(billboard, character)
            and greenArrowInsideBillboard(billboard) then
            return true
        end
    end

    -- Si la flecha esta en una ScreenGui, usar solo los marcadores que
    -- ya se identificaron como potencialmente verdes al crear el indice.
    if #indexedScreenMarkers == 0 then return false end
    local camera = Workspace.CurrentCamera
    local head = character:FindFirstChild("Head")
    if not camera or not head then return false end
    local pos, onScreen = camera:WorldToViewportPoint(head.Position)
    if not onScreen or pos.Z <= 0 then return false end
    local radius = CONFIG.ARROW_SCREEN_RADIUS

    for _, record in ipairs(indexedScreenMarkers) do
        local obj = record.marker
        local screenGui = record.screenGui
        if obj.Parent and screenGui.Parent and screenGui.Enabled and visibleGui(obj) then
            local size = obj.AbsoluteSize
            if size.X >= 4 and size.X <= 110 and size.Y >= 4 and size.Y <= 110 then
                local center = obj.AbsolutePosition + size / 2
                local offsetY = center.Y - pos.Y
                if math.abs(center.X - pos.X) <= radius
                    and offsetY >= -145 and offsetY <= 25 then
                    return true
                end
            end
        end
    end
    return false
end

--==================== OBJETIVOS Y APLICACION ESP ====================--
local function isEnemy(player)
    if not player or player == localPlayer then return false end
    if not CONFIG.IGNORE_TEAMMATES then return true end
    -- La decision manual tiene prioridad hasta que el jugador abandone la partida.
    if forcedEnemies[player] then return true end
    -- Consultar solo datos guardados y atributos pequenos, nunca jerarquias GUI.
    return not allyReason(player)
end
-- Mantiene fuera del apuntado los personajes que ya murieron,
-- incluso si un sistema de ragdoll les vuelve a dar Health > 0.
local deadCharacters = setmetatable({}, {__mode = "k"})

-- Nombres habituales de marcas de muerte en juegos con sistema propio.
-- Se comprueban como atributos booleanos o BoolValue.
local DEATH_FLAGS = {"IsDead", "Dead", "Eliminated", "IsEliminated"}

local function hasDeathFlag(instance)
    if not instance then return false end

    for _, name in ipairs(DEATH_FLAGS) do
        if instance:GetAttribute(name) == true then
            return true
        end

        local marker = instance:FindFirstChild(name)
        if marker and marker:IsA("BoolValue") and marker.Value then
            return true
        end
    end

    return false
end

local function characterIsDead(player, char, humanoid)
    if deadCharacters[char] then return true end

    if humanoid.Health <= 0
        or humanoid:GetState() == Enum.HumanoidStateType.Dead then
        deadCharacters[char] = true
        return true
    end

    -- Compatible con eliminaciones personalizadas que no dejan Health a 0.
    return hasDeathFlag(player) or hasDeathFlag(char) or hasDeathFlag(humanoid)
end

local function getLiveParts(player)
    if not player or not isEnemy(player) then return nil end
    local char = player.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local head = char:FindFirstChild("Head")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not head or not root then return nil end
    if not char:IsDescendantOf(Workspace) then return nil end
    if characterIsDead(player, char, humanoid) then return nil end

    return char, humanoid, head, root
end
local function removeHighlight(player)
    local obj = highlights[player]
    if obj then
        highlights[player] = nil
        obj:Destroy()
    end
end
local function dropTarget(player)
    if lockedTarget == player then lockedTarget = nil end
    removeHighlight(player)
end
local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
end
local function watchCharacter(player, character)
    local record = tracked[player]
    if not record then return end
    disconnectAll(record.characterConnections)
    dropTarget(player)
    record.character = character
    local function markCharacterDead()
        deadCharacters[character] = true
        dropTarget(player)
    end

    local function watchHumanoid(humanoid)
        if record.humanoid == humanoid then return end
        record.humanoid = humanoid

        table.insert(record.characterConnections, humanoid.HealthChanged:Connect(function(health)
            if health <= 0 then markCharacterDead() end
        end))
        table.insert(record.characterConnections, humanoid.Died:Connect(markCharacterDead))
        table.insert(record.characterConnections, humanoid.StateChanged:Connect(function(_, newState)
            if newState == Enum.HumanoidStateType.Dead then
                markCharacterDead()
            end
        end))

        if characterIsDead(player, character, humanoid) then
            dropTarget(player)
        end
    end

    -- Descartar la seleccion inmediatamente si el juego marca una eliminacion.
    for _, flag in ipairs(DEATH_FLAGS) do
        table.insert(record.characterConnections,
            character:GetAttributeChangedSignal(flag):Connect(function()
                if character:GetAttribute(flag) == true then dropTarget(player) end
            end))
    end
    local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
    if currentHumanoid then watchHumanoid(currentHumanoid) end
    table.insert(record.characterConnections, character.ChildAdded:Connect(function(child)
        if child:IsA("Humanoid") then watchHumanoid(child) end
    end))
    table.insert(record.characterConnections, character.ChildRemoved:Connect(function(child)
        if child:IsA("Humanoid") or child.Name == "Head"
            or child.Name == "HumanoidRootPart" then
            dropTarget(player)
        end
    end))
end
local function trackPlayer(player)
    if player == localPlayer or tracked[player] then return end
    local record = {
        playerConnections = {},
        characterConnections = {},
        character = nil,
        humanoid = nil,
    }
    tracked[player] = record
    table.insert(record.playerConnections, player.CharacterAdded:Connect(function(character)
        watchCharacter(player, character)
    end))
    table.insert(record.playerConnections, player.CharacterRemoving:Connect(function()
        disconnectAll(record.characterConnections)
        record.character = nil
        record.humanoid = nil
        dropTarget(player)
    end))
    local function onTeamChanged()
        if not isEnemy(player) then dropTarget(player) end
        refreshAllyList()
    end
    for _, property in ipairs({"Team", "TeamColor", "Neutral"}) do
        table.insert(record.playerConnections,
            player:GetPropertyChangedSignal(property):Connect(onTeamChanged))
    end
    if CONFIG.CUSTOM_TEAM_ATTRIBUTE and CONFIG.CUSTOM_TEAM_ATTRIBUTE ~= "" then
        table.insert(record.playerConnections,
            player:GetAttributeChangedSignal(CONFIG.CUSTOM_TEAM_ATTRIBUTE):Connect(onTeamChanged))
    end

    -- Algunos modos de juego marcan la eliminacion en el propio Player.
    for _, flag in ipairs(DEATH_FLAGS) do
        table.insert(record.playerConnections,
            player:GetAttributeChangedSignal(flag):Connect(function()
                if player:GetAttribute(flag) == true then dropTarget(player) end
            end))
    end
    if player.Character then watchCharacter(player, player.Character) end
    refreshAllyList()
end
local function untrackPlayer(player)
    local record = tracked[player]
    if not record then return end
    disconnectAll(record.characterConnections)
    disconnectAll(record.playerConnections)
    tracked[player] = nil
    arrowAllies[player] = nil
    forcedEnemies[player] = nil
    dropTarget(player)
    refreshAllyList()
end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(untrackPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end
local function clearESP()
    for player in pairs(highlights) do
        removeHighlight(player)
    end
end
local function refreshESP()
    if not enabled.esp then return end
    for player in pairs(tracked) do
        local char = getLiveParts(player)
        if not char then
            removeHighlight(player)
        else
            local visual = highlights[player]
            if visual and visual.Adornee ~= char then
                removeHighlight(player)
                visual = nil
            end
            if not visual then
                visual = create("Highlight", {
                    Name = "ESP_Verde_" .. player.UserId,
                    Adornee = char,
                    FillColor = COLORS.green,
                    FillTransparency = 0.18,
                    OutlineColor = COLORS.green,
                    OutlineTransparency = 0,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                    Enabled = true,
                }, highlightFolder)
                highlights[player] = visual
            end
        end
    end
end
-- Cuando NOSOTROS cambiamos de equipo, recalcular los objetivos y el ESP.
local function myTeamChanged()
    if lockedTarget and not isEnemy(lockedTarget) then lockedTarget = nil end
    refreshAllyList()
    if enabled.esp then refreshESP() end
end
for _, property in ipairs({"Team", "TeamColor", "Neutral"}) do
    localPlayer:GetPropertyChangedSignal(property):Connect(myTeamChanged)
end
if CONFIG.CUSTOM_TEAM_ATTRIBUTE and CONFIG.CUSTOM_TEAM_ATTRIBUTE ~= "" then
    localPlayer:GetAttributeChangedSignal(CONFIG.CUSTOM_TEAM_ATTRIBUTE):Connect(myTeamChanged)
end
--==================== ACTUALIZACION MANUAL DE COMPAÑEROS ====================--
-- Ni temporizadores ni inspecciones de flechas durante apuntado o ESP.
-- Solo una pulsacion de Y (configurable) o del boton "ACTUALIZAR ALIADOS".
local manualScanBusy = false
local function runManualAllyScan()
    if manualScanBusy then
        showNotification("Actualización ya en curso")
        return
    end
    manualScanBusy = true
    showNotification("Buscando compañeros una sola vez...")
    status.Text = "Actualizando compañeros manualmente..."
    rescanAllies.Text = "ACTUALIZANDO..."
    task.spawn(function()
        local examined, found = 0, 0
        -- pcall permite desbloquear el boton incluso si un GUI externo
        -- desaparece durante la revision y provoca un error de lectura.
        local ok, err = pcall(function()
            rebuildGuiIndex()
            for _, other in ipairs(Players:GetPlayers()) do
                if other ~= localPlayer and tracked[other] and other.Character
                    and not arrowAllies[other] and not forcedEnemies[other]
                    and not isNativeAlly(other) then
                    examined += 1
                    if scanForGreenArrow(other) then
                        arrowAllies[other] = true
                        found += 1
                        if lockedTarget == other then lockedTarget = nil end
                        removeHighlight(other)
                        if CONFIG.ARROW_DEBUG then
                            print("[MONO AIM] Compañero guardado:", other.Name)
                        end
                    end
                    task.wait() -- cede un fotograma entre jugadores
                end
            end
            refreshAllyList()
            if enabled.esp then refreshESP() end
        end)
        table.clear(indexedBillboards)
        table.clear(indexedScreenMarkers)
        manualScanBusy = false
        if rescanAllies.Parent then rescanAllies.Text = "ACTUALIZAR ALIADOS" end
        if not ok then
            warn("[MONO AIM] Error de actualizacion manual:", err)
            status.Text = "Error al actualizar compañeros. Intenta de nuevo."
            showNotification("No se pudo completar la actualización")
            return
        end
        status.Text = "Escaneo manual: " .. found .. " nuevo(s) de " .. examined .. " revisado(s)"
        showNotification("Actualizado: " .. found .. " compañero(s) nuevo(s)")
    end)
end
rescanAllies.Activated:Connect(runManualAllyScan)

--==================== ATRAVESAR PAREDES ====================--
-- El cliente desactiva la colision solo en muros cercanos, NO en el suelo.
-- Las paredes normales se detectan por forma; para MeshParts/estructuras
-- especiales, usa el tag MonoPassWall o atributo MonoWallPass=true.
-- Es local al jugador; un anticheat/servidor autoritativo puede impedirlo.
local wallParams = OverlapParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.MaxParts = 125
local ghostWalls = {} -- [BasePart] = CanCollide original
local function restoreWalls()
    for part, original in pairs(ghostWalls) do
        ghostWalls[part] = nil
        if part and part.Parent then
            part.CanCollide = original
        end
    end
end
local function shouldPassWall(part)
    if not part:IsA("BasePart") then return false end
    if not part.CanCollide and ghostWalls[part] == nil then return false end
    -- Nunca modificar personajes (nuestro jugador, otros jugadores, NPCs).
    local model = part:FindFirstAncestorOfClass("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then return false end
    local name = string.lower(part.Name)
    if string.find(name, "floor", 1, true)
        or string.find(name, "ground", 1, true)
        or string.find(name, "baseplate", 1, true)
        or string.find(name, "suelo", 1, true)
        or string.find(name, "piso", 1, true)
        or string.find(name, "stairs", 1, true)
        or string.find(name, "escalera", 1, true)
        or string.find(name, "ramp", 1, true)
        or string.find(name, "techo", 1, true)
        or string.find(name, "roof", 1, true) then
        return false
    end
    if CollectionService:HasTag(part, CONFIG.WALL_PASS_TAG)
        or part:GetAttribute("MonoWallPass") == true then
        return true
    end
    -- Deteccion automatica conservadora: muro vertical, alto y delgado.
    -- Si tu mapa utiliza muros gruesos o meshes irregulares, etiquetalos.
    if not part.Anchored then return false end
    local sz = part.Size
    if sz.Y < 3 or math.abs(part.CFrame.UpVector.Y) < 0.75 then return false end
    local narrow = math.min(sz.X, sz.Z)
    local long = math.max(sz.X, sz.Z)
    return narrow <= 3.5 and long >= 3.0
end
local function refreshWallPass()
    if not enabled.wallpass then return end
    local character = localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        restoreWalls()
        return
    end
    wallParams.FilterDescendantsInstances = {character}
    local near = Workspace:GetPartBoundsInRadius(root.Position, CONFIG.WALL_RADIUS, wallParams)
    local visible = {}
    for _, part in ipairs(near) do
        if shouldPassWall(part) then
            visible[part] = true
            if ghostWalls[part] == nil then
                ghostWalls[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
    for part, original in pairs(ghostWalls) do
        if not visible[part] then
            ghostWalls[part] = nil
            if part.Parent then part.CanCollide = original end
        end
    end
end
localPlayer.CharacterRemoving:Connect(restoreWalls)
--==================== APLICACION AIM ====================--
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local function canSeeHead(camera, character, headPosition)
    rayParams.FilterDescendantsInstances = localPlayer.Character
        and {localPlayer.Character} or {}
    local origin = camera.CFrame.Position
    local direction = headPosition - origin
    if direction.Magnitude <= 0.01 then return true end
    local hit = Workspace:Raycast(origin, direction, rayParams)
    return hit == nil or hit.Instance:IsDescendantOf(character)
end
local function getAimPosition(camera, head, root)
    local result = head.Position
    local dist = (result - camera.CFrame.Position).Magnitude
    local seconds = CONFIG.PREDICTION_SECONDS
    if CONFIG.PROJECTILE_SPEED > 0 then
        seconds += dist / CONFIG.PROJECTILE_SPEED
    end
    seconds = math.clamp(seconds, 0, 0.30)
    if seconds > 0 then
        result += root.AssemblyLinearVelocity * seconds
    end
    return result
end
local function screenDistance(camera, worldPoint)
    local point, inside = camera:WorldToViewportPoint(worldPoint)
    if not inside or point.Z <= 0 then return math.huge end
    return (Vector2.new(point.X, point.Y) - camera.ViewportSize / 2).Magnitude
end
local function acquireTarget(camera, requireVisibility)
    local selected, best = nil, CONFIG.ACQUIRE_FOV
    for player in pairs(tracked) do
        local char, _, head = getLiveParts(player)
        if char then
            local dist = (head.Position - camera.CFrame.Position).Magnitude
            if dist <= CONFIG.MAX_DISTANCE then
                local pixels = screenDistance(camera, head.Position)
                if pixels < best and (not requireVisibility
                    or canSeeHead(camera, char, head.Position)) then
                    best = pixels
                    selected = player
                end
            end
        end
    end
    return selected
end
local function targetStillValid(camera, player, forAimbot)
    local char, _, head = getLiveParts(player)
    if not char then return false end
    if (head.Position - camera.CFrame.Position).Magnitude > CONFIG.MAX_DISTANCE then
        return false
    end
    if forAimbot then
        local limit = CONFIG.ACQUIRE_FOV * CONFIG.KEEP_FOV_MULTIPLIER
        if screenDistance(camera, head.Position) > limit then return false end
        if CONFIG.REQUIRE_VISIBILITY_AIMBOT
            and not canSeeHead(camera, char, head.Position) then
            return false
        end
    end
    return true
end
--==================== INTERRUPTORES Y TECLAS ====================--
local function showStatus(message)
    status.Text = message
end
local function refreshButtons()
    if scanHotkeyButton then
        if awaitingBind == "allyscan" then
            scanHotkeyButton.Text = "..."
        else
            scanHotkeyButton.Text = "TECLA: " .. (binds.allyscan and binds.allyscan.Name or "—")
        end
    end
    for feature, row in pairs(rows) do
        local isOn = enabled[feature]
        row.toggle.Text = isOn and "ON" or "OFF"
        row.toggle.BackgroundColor3 = isOn and COLORS.white or COLORS.off
        row.toggle.TextColor3 = isOn and COLORS.black or COLORS.white
        if awaitingBind == feature then
            row.shortcut.Text = "..."
            row.shortcut.BackgroundColor3 = COLORS.white
            row.shortcut.TextColor3 = COLORS.black
        else
            row.shortcut.Text = binds[feature] and binds[feature].Name or "—"
            row.shortcut.BackgroundColor3 = COLORS.black
            row.shortcut.TextColor3 = COLORS.white
        end
    end
end
local function setFeature(feature, desired)
    if enabled[feature] == desired then return end
    enabled[feature] = desired
    if desired and feature == "aimlock" then
        enabled.aimbot = false
        lockedTarget = nil
    elseif desired and feature == "aimbot" then
        enabled.aimlock = false
        lockedTarget = nil
    elseif not desired and (feature == "aimbot" or feature == "aimlock") then
        lockedTarget = nil
    end
    if feature == "esp" then
        if desired then refreshESP() else clearESP() end
    elseif feature == "wallpass" then
        if desired then refreshWallPass() else restoreWalls() end
    end
    local message = featureNames[feature] .. (desired and " ACTIVADO" or " DESACTIVADO")
    showStatus(message)
    showNotification(message)
    refreshButtons()
end
for feature, row in pairs(rows) do
    row.toggle.Activated:Connect(function()
        setFeature(feature, not enabled[feature])
    end)
    row.shortcut.Activated:Connect(function()
        awaitingBind = feature
        showStatus("Pulsa una tecla para " .. featureNames[feature]
            .. "  •  ESC cancelar / SUPR borrar")
        refreshButtons()
    end)
end
local INVALID_KEYS = {
    [Enum.KeyCode.Unknown] = true,
    [Enum.KeyCode.LeftShift] = true,
    [Enum.KeyCode.RightShift] = true,
    [Enum.KeyCode.LeftControl] = true,
    [Enum.KeyCode.RightControl] = true,
    [Enum.KeyCode.LeftAlt] = true,
    [Enum.KeyCode.RightAlt] = true,
    [Enum.KeyCode.CapsLock] = true,
}
UserInputService.InputBegan:Connect(function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local key = input.KeyCode
    if awaitingBind then
        local feature = awaitingBind
        if key == Enum.KeyCode.Escape then
            awaitingBind = nil
            showStatus("Asignacion cancelada")
        elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Delete then
            binds[feature] = nil
            awaitingBind = nil
            showStatus("Atajo de " .. featureNames[feature] .. " eliminado")
        elseif not INVALID_KEYS[key] then
            local conflict = nil
            for other, bound in pairs(binds) do
                if other ~= feature and bound == key then conflict = other end
            end
            if conflict then
                showStatus(key.Name .. " ya se usa en " .. featureNames[conflict]
                    .. ". Elige otra tecla.")
            else
                binds[feature] = key
                awaitingBind = nil
                showStatus(featureNames[feature] .. " = " .. key.Name)
            end
        end
        refreshButtons()
        return
    end
    if processed or UserInputService:GetFocusedTextBox() then return end
    for feature, bound in pairs(binds) do
        if bound and key == bound then
            if feature == "allyscan" then
                runManualAllyScan() -- RELOAD manual; no cambia ningun toggle
            else
                setFeature(feature, not enabled[feature])
            end
            return
        end
    end
end)
refreshButtons()
--==================== ACTUALIZACIONES EN CLIENTE ====================--
local renderName = "MonoAimV36_Camera_" .. localPlayer.UserId
local nextTargetSearch = 0
RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
    updateViewport()
    if not enabled.aimbot and not enabled.aimlock then return end
    local myCharacter = localPlayer.Character
    local myHumanoid = myCharacter and myCharacter:FindFirstChildOfClass("Humanoid")
    if not myHumanoid or myHumanoid.Health <= 0 then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local forAimbot = enabled.aimbot
    if lockedTarget and not targetStillValid(cam, lockedTarget, forAimbot) then
        lockedTarget = nil
    end
    if not lockedTarget then
        local now = os.clock()
        if now >= nextTargetSearch then
            nextTargetSearch = now + CONFIG.TARGET_SEARCH_INTERVAL
            lockedTarget = acquireTarget(cam,
                forAimbot and CONFIG.REQUIRE_VISIBILITY_AIMBOT)
        end
    end
    local player = lockedTarget
    if not player then return end
    local character, _, head, root = getLiveParts(player)
    if not character then
        lockedTarget = nil
        return
    end
    local destination = getAimPosition(cam, head, root)
    local origin = cam.CFrame.Position
    if (destination - origin).Magnitude <= 0.01 then return end
    local desired = CFrame.lookAt(origin, destination)
    if forAimbot and CONFIG.AIMBOT_INSTANT then
        cam.CFrame = desired
    else
        local speed = forAimbot and CONFIG.AIMBOT_SPEED or CONFIG.AIMLOCK_SPEED
        local blend = math.clamp(1 - math.exp(-speed * dt), 0, 1)
        cam.CFrame = cam.CFrame:Lerp(desired, blend)
    end
end)
local lastEspCheck = 0
local lastWallCheck = 0
RunService.Heartbeat:Connect(function(dt)
    if enabled.esp then
        lastEspCheck += dt
        if lastEspCheck >= CONFIG.ESP_REFRESH_INTERVAL then
            lastEspCheck = 0
            refreshESP()
        end
    else
        lastEspCheck = 0
    end
    if enabled.wallpass then
        lastWallCheck += dt
        if lastWallCheck >= CONFIG.WALL_SCAN_INTERVAL then
            lastWallCheck = 0
            refreshWallPass()
        end
    else
        lastWallCheck = 0
    end
end)
print("MONO AIM V3.6 listo | Q Aim Lock / E Aimbot / R ESP / T Paredes / Y Actualizar aliados MANUAL")

