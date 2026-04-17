local QBCore = exports['qb-core']:GetCoreObject()

local state = {
    hacking = false,
    activeATM = nil,
    laptopObj = nil,
    startedAt = 0,
    lastProbe = 0
}

local function notify(msg, typ)
    QBCore.Functions.Notify(msg, typ or 'primary')
end

local function loadModel(model)
    if HasModelLoaded(model) then return end
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end
end

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
end

local function getClosestATM()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    for _, model in ipairs(Config.ATMModels) do
        local atm = GetClosestObjectOfType(pCoords.x, pCoords.y, pCoords.z, Config.MaxDistanceFromATM, model, false, false, false)
        if atm and atm ~= 0 then
            local dist = #(GetEntityCoords(atm) - pCoords)
            if dist <= Config.MaxDistanceFromATM then
                return atm, dist
            end
        end
    end

    return nil, 999.0
end

local function setNui(enabled, payload)
    SetNuiFocus(enabled, enabled)
    SendNUIMessage(payload)
end

local function spawnLaptop(atm)
    local model = Config.LaptopProp
    if not model then return end

    loadModel(model)

    local coords = GetEntityCoords(atm)
    local forward = GetEntityForwardVector(atm)
    local spawn = vector3(coords.x - forward.x * 0.34, coords.y - forward.y * 0.34, coords.z + 0.90)
    local heading = GetEntityHeading(atm)

    local obj = CreateObject(model, spawn.x, spawn.y, spawn.z, true, true, false)
    SetEntityHeading(obj, heading)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)

    state.laptopObj = obj
end

local function removeLaptop()
    if state.laptopObj and DoesEntityExist(state.laptopObj) then
        DeleteEntity(state.laptopObj)
    end
    state.laptopObj = nil
end

local function playHackAnim()
    local ped = PlayerPedId()
    loadAnimDict('anim@heists@ornate_bank@hack')
    TaskPlayAnim(ped, 'anim@heists@ornate_bank@hack', 'hack_loop', 8.0, -8.0, -1, 1, 0, false, false, false)
end

local function clearHackSession(silent)
    state.hacking = false
    state.activeATM = nil
    state.startedAt = 0
    ClearPedTasks(PlayerPedId())
    removeLaptop()
    setNui(false, { action = 'hide' })

    if not silent then
        notify('Exploit session terminated.', 'error')
    end
end

RegisterNUICallback('closeHack', function(_, cb)
    if state.hacking then
        TriggerServerEvent('atmhack:server:finish', false, {
            reason = 'manual_abort',
            elapsed = math.max(0, GetGameTimer() - state.startedAt)
        })
    end

    clearHackSession(true)
    cb(true)
end)

RegisterNUICallback('finishHack', function(data, cb)
    local success = data and data.success or false
    local tier = data and tonumber(data.tier) or 1

    if success then
        notify('Access granted. Pulling funds from host bank.', 'success')
    else
        notify('Session burned. Trace signatures detected.', 'error')
    end

    TriggerServerEvent('atmhack:server:finish', success, {
        tier = tier,
        mode = data and data.mode or 'atm',
        cardId = data and data.cardId or nil,
        elapsed = math.max(0, GetGameTimer() - state.startedAt),
        trace = data and data.trace or 0,
        stageReached = data and data.stageReached or 1,
        reason = data and data.reason or (success and 'success' or 'failed')
    })

    clearHackSession(true)
    cb(true)
end)

RegisterNetEvent('atmhack:client:start', function(payload)
    if state.hacking then return end

    local atm = getClosestATM()
    if not atm then
        notify('No ATM terminal detected nearby.', 'error')
        return
    end

    state.hacking = true
    state.activeATM = atm
    state.startedAt = GetGameTimer()

    spawnLaptop(atm)
    playHackAnim()

    setNui(true, {
        action = 'start',
        maxDuration = Config.HackDuration,
        payload = payload
    })
end)

RegisterNetEvent('atmhack:client:useLaptop', function()
    if state.hacking then
        notify('Exploit already running.', 'error')
        return
    end

    local atm, dist = getClosestATM()
    if not atm then
        notify('Move within ATM terminal range to deploy laptop.', 'error')
        return
    end

    if dist > Config.MaxDistanceFromATM then
        notify('Too far from ATM terminal.', 'error')
        return
    end

    TriggerServerEvent('atmhack:server:requestStart')
end)

RegisterNetEvent('atmhack:client:useSkimmer', function()
    local atm = getClosestATM()
    if not atm then
        notify('You must be next to an ATM to install skimmer hardware.', 'error')
        return
    end

    local coords = GetEntityCoords(atm)
    TriggerServerEvent('atmhack:server:installSkimmer', {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })
end)

RegisterNetEvent('atmhack:client:policeAlert', function(coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('ATM Intrusion')
    EndTextCommandSetBlipName(blip)

    notify('Dispatch: ATM intrusion signatures detected.', 'error')

    Wait(30000)
    RemoveBlip(blip)
end)

CreateThread(function()
    while true do
        if state.hacking then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000)

        if state.hacking then
            goto continue
        end

        local atm = getClosestATM()
        if atm then
            local now = GetGameTimer()
            if now - state.lastProbe > 20000 then
                state.lastProbe = now
                local coords = GetEntityCoords(PlayerPedId())
                TriggerServerEvent('atmhack:server:atmProbe', {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z
                })
            end
        end

        ::continue::
    end
end)
