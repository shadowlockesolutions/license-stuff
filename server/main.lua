local QBCore = exports['qb-core']:GetCoreObject()

local globalCooldownUntil = 0
local playerCooldowns = {}
local playerHeat = {}
local playerStreak = {}
local burnedCards = {}
local clonedCards = {}
local skimmers = {}

local function now()
    return os.time()
end

local function notify(src, msg, typ)
    TriggerClientEvent('QBCore:Notify', src, msg, typ or 'primary')
end

local function cardFingerprint(cardInfo)
    return ('%s|%s'):format(cardInfo.citizenid or 'unknown', cardInfo.cardNumber or cardInfo.masked or 'none')
end

local function countPoliceOnline()
    local players = QBCore.Functions.GetQBPlayers()
    local count = 0

    for _, player in pairs(players) do
        local job = player.PlayerData.job
        if job and job.onduty then
            for _, allowed in ipairs(Config.AlertJobs) do
                if job.name == allowed then
                    count = count + 1
                    break
                end
            end
        end
    end

    return count
end

local function findPlayerByCitizenId(citizenid)
    for _, player in pairs(QBCore.Functions.GetQBPlayers()) do
        if player.PlayerData.citizenid == citizenid then
            return player
        end
    end

    return nil
end

local function getPlayerCreditCardInfo(player)
    local card = player.Functions.GetItemByName(Config.CreditCardItem)
    if not card then return nil end

    local info = card.info or {}
    local char = player.PlayerData.charinfo or {}
    local holder = (char.firstname and char.lastname) and (char.firstname .. ' ' .. char.lastname) or ('CID ' .. player.PlayerData.citizenid)
    local rawNumber = tostring(info.cardNumber or info.number or info.ibannumber or math.random(1000000000000000, 9999999999999999))
    local last4 = rawNumber:sub(-4)

    return {
        citizenid = player.PlayerData.citizenid,
        holder = holder,
        bankName = info.bankName or 'Pacific Banking Cluster',
        cardNumber = rawNumber,
        masked = ('**** **** **** %s'):format(last4),
        pinHint = tostring(info.pinHint or (math.random(10, 99) .. 'X')),
        source = player.PlayerData.source
    }
end

local function getClonedCards(src)
    clonedCards[src] = clonedCards[src] or {}

    local valid = {}
    for _, entry in ipairs(clonedCards[src]) do
        if not burnedCards[entry.cardId] and not entry.used then
            valid[#valid + 1] = entry
        end
    end

    clonedCards[src] = valid
    return valid
end

local function addClonedCard(src, cardInfo, method)
    local list = getClonedCards(src)
    local finger = cardFingerprint(cardInfo)

    for _, entry in ipairs(list) do
        if entry.fingerprint == finger then
            return false
        end
    end

    local cardId = ('CLONE-%s-%04d'):format(os.time(), math.random(1000, 9999))
    list[#list + 1] = {
        cardId = cardId,
        fingerprint = finger,
        holder = cardInfo.holder,
        citizenid = cardInfo.citizenid,
        bankName = cardInfo.bankName,
        masked = cardInfo.masked,
        cardNumber = cardInfo.cardNumber,
        pinHint = cardInfo.pinHint,
        acquiredBy = method,
        acquiredAt = now(),
        used = false
    }

    clonedCards[src] = list
    return true
end

local function markCardUsed(src, cardId)
    local cards = getClonedCards(src)
    for _, card in ipairs(cards) do
        if card.cardId == cardId then
            card.used = true
            if Config.CardMode.blockReuseGlobally then
                burnedCards[cardId] = true
            end
            return true, card
        end
    end
    return false, nil
end

local function getSkimmerKey(coords)
    return ('%.2f|%.2f|%.2f'):format(coords.x, coords.y, coords.z)
end

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function pruneSkimmers()
    local t = now()
    for key, skimmer in pairs(skimmers) do
        if skimmer.expiresAt <= t then
            skimmers[key] = nil
        end
    end
end

local function playerHasLaptop(player)
    local rule = Config.RequiredItems.laptop
    if not rule then return true end
    return player.Functions.GetItemByName(rule.name) ~= nil
end

local function playerHasExploit(player)
    local rule = Config.RequiredItems.exploit
    if not rule then return true end
    return player.Functions.GetItemByName(rule.name) ~= nil
end

local function burnExploit(src, player)
    local rule = Config.RequiredItems.exploit
    if not rule or not rule.removeOnUse then return end

    player.Functions.RemoveItem(rule.name, 1)
    local shared = QBCore.Shared.Items[rule.name]
    if shared then
        TriggerClientEvent('inventory:client:ItemBox', src, shared, 'remove')
    end
end

local function burnSkimmerItem(src, player)
    local rule = Config.RequiredItems.skimmer
    if not rule or not rule.removeOnUse then return true end

    local item = player.Functions.GetItemByName(rule.name)
    if not item then
        return false
    end

    player.Functions.RemoveItem(rule.name, 1)
    local shared = QBCore.Shared.Items[rule.name]
    if shared then
        TriggerClientEvent('inventory:client:ItemBox', src, shared, 'remove')
    end

    return true
end

local function broadcastPoliceAlert(coords)
    for _, id in pairs(QBCore.Functions.GetPlayers()) do
        local officer = QBCore.Functions.GetPlayer(id)
        if officer and officer.PlayerData.job and officer.PlayerData.job.onduty then
            for _, allowed in ipairs(Config.AlertJobs) do
                if officer.PlayerData.job.name == allowed then
                    TriggerClientEvent('atmhack:client:policeAlert', id, coords)
                    break
                end
            end
        end
    end

    if Config.DispatchEvent then
        TriggerEvent(Config.DispatchEvent, {
            message = 'ATM hacking in progress',
            coords = coords
        })
    end
end

local function payout(src, player, amount, meta)
    local mode = Config.Economy.mode

    if mode == 'qs-banking' then
        local ok = pcall(function()
            exports['qs-banking']:AddMoney(src, amount, Config.Economy.qsStatement)
        end)

        if ok then return true end

        player.Functions.AddMoney(Config.Economy.qbMoneyType, amount, 'atm-hack-fallback')
        return false
    end

    if mode == 'custom' and Config.Economy.customRewardEvent then
        TriggerEvent(Config.Economy.customRewardEvent, src, amount, meta)
        return true
    end

    player.Functions.AddMoney(Config.Economy.qbMoneyType, amount, 'atm-hack-success')
    return true
end

local function computeATMReward(src, player, tier, trace, elapsed, stageReached)
    local heat = playerHeat[src] or 0
    local streak = (playerStreak[src] or 0) + 1
    playerStreak[src] = streak

    local base = math.random(Config.BaseReward.min, Config.BaseReward.max)
    local tierBonus = Config.RiskBonus[tier] or 1.0
    local streakBonus = math.min(Config.StreakBonusCap, 1.0 + (streak * 0.06))
    local heatBonus = math.min(Config.HeatBonusCap, 1.0 + heat * 0.04)
    local stealthBonus = math.max(1.0, 1.25 - (trace / 200))

    local reward = math.floor(base * tierBonus * streakBonus * heatBonus * stealthBonus)

    local paidViaQS = payout(src, player, reward, {
        tier = tier,
        trace = trace,
        elapsed = elapsed,
        stageReached = stageReached,
        mode = 'atm'
    })

    if paidViaQS then
        notify(src, ('ATM breach complete. $%s transferred through %s.'):format(reward, Config.Economy.mode), 'success')
    else
        notify(src, ('QS-Banking unavailable. Fallback payout: $%s %s.'):format(reward, Config.Economy.qbMoneyType), 'primary')
    end

    playerHeat[src] = math.min(12, heat + tier)
end

local function computeCardReward(src, player, cardInfo, tier, trace, elapsed, stageReached)
    local reward = math.random(Config.CardMode.fallbackReward.min, Config.CardMode.fallbackReward.max)

    if cardInfo and cardInfo.citizenid then
        local victim = findPlayerByCitizenId(cardInfo.citizenid)
        if victim then
            local bank = victim.PlayerData.money and victim.PlayerData.money.bank or 0
            local pct = math.random(math.floor(Config.CardMode.percentRange.min * 100), math.floor(Config.CardMode.percentRange.max * 100)) / 100
            local desired = math.floor(bank * pct)
            local floorSafe = math.max(0, bank - Config.CardMode.minBalanceAfterDrain)
            local drain = math.min(desired, floorSafe, Config.CardMode.maxDrain)

            if drain > 0 then
                victim.Functions.RemoveMoney('bank', drain, 'card-compromise-atm')
                reward = drain
                notify(victim.PlayerData.source, ('Your card ending %s was skimmed and used. $%s withdrawn.'):format((cardInfo.masked or '****'):sub(-4), drain), 'error')
            end
        end
    end

    payout(src, player, reward, {
        tier = tier,
        trace = trace,
        elapsed = elapsed,
        stageReached = stageReached,
        mode = 'card'
    })

    notify(src, ('Card intrusion successful. You siphoned $%s.'):format(reward), 'success')
end

QBCore.Functions.CreateUseableItem(Config.RequiredItems.laptop.name, function(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end

    if not playerHasLaptop(player) then
        notify(source, ('You need a %s to start intrusion.'):format(Config.RequiredItems.laptop.name), 'error')
        return
    end

    TriggerClientEvent('atmhack:client:useLaptop', source)
end)

QBCore.Functions.CreateUseableItem(Config.RequiredItems.skimmer.name, function(source)
    TriggerClientEvent('atmhack:client:useSkimmer', source)
end)

RegisterNetEvent('atmhack:server:installSkimmer', function(coords)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    pruneSkimmers()

    local owned = 0
    for _, skimmer in pairs(skimmers) do
        if skimmer.owner == src then
            owned = owned + 1
        end
    end

    if owned >= Config.SkimmerMaxPerPlayer then
        notify(src, ('Skimmer limit reached (%s).'):format(Config.SkimmerMaxPerPlayer), 'error')
        return
    end

    if not burnSkimmerItem(src, player) then
        notify(src, ('Missing skimmer hardware: %s'):format(Config.RequiredItems.skimmer.name), 'error')
        return
    end

    local key = getSkimmerKey(coords)
    skimmers[key] = {
        owner = src,
        ownerCid = player.PlayerData.citizenid,
        coords = coords,
        createdAt = now(),
        expiresAt = now() + (Config.SkimmerDurationMinutes * 60),
        captures = {}
    }

    notify(src, ('Skimmer installed. Live for %s minutes.'):format(Config.SkimmerDurationMinutes), 'success')
end)

RegisterNetEvent('atmhack:server:atmProbe', function(playerCoords)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    pruneSkimmers()

    local cardInfo = getPlayerCreditCardInfo(player)
    if not cardInfo then return end

    local t = now()

    for _, skimmer in pairs(skimmers) do
        if skimmer.owner ~= src and distance(playerCoords, skimmer.coords) <= Config.SkimDistance then
            local victimKey = player.PlayerData.citizenid
            local lastCaptured = skimmer.captures[victimKey] or 0
            if (t - lastCaptured) >= Config.SkimmerCaptureCooldown then
                skimmer.captures[victimKey] = t
                local added = addClonedCard(skimmer.owner, cardInfo, 'skimmer')

                if added then
                    notify(skimmer.owner, ('Skimmer captured card data: %s (%s).'):format(cardInfo.holder, cardInfo.masked), 'success')
                end
            end
        end
    end
end)

RegisterNetEvent('atmhack:server:requestStart', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local t = now()

    if t < globalCooldownUntil then
        notify(src, ('Network lockdown active: %ss'):format(globalCooldownUntil - t), 'error')
        return
    end

    local playerCd = playerCooldowns[src] or 0
    if t < playerCd then
        notify(src, ('You need to cool off for %ss.'):format(playerCd - t), 'error')
        return
    end

    if countPoliceOnline() < Config.RequiredPolice then
        notify(src, ('At least %s police must be on duty.'):format(Config.RequiredPolice), 'error')
        return
    end

    if not playerHasLaptop(player) then
        notify(src, ('Missing required device: %s'):format(Config.RequiredItems.laptop.name), 'error')
        return
    end

    local heat = playerHeat[src] or 0
    local streak = playerStreak[src] or 0
    local difficultyBias = math.min(35, (heat * 4) + (streak * 2))
    local cards = getClonedCards(src)
    local hasExploit = playerHasExploit(player)

    if not hasExploit and (#cards == 0 or not Config.CardMode.enabled) then
        notify(src, ('Missing required exploit drive: %s'):format(Config.RequiredItems.exploit.name), 'error')
        return
    end

    TriggerClientEvent('atmhack:client:start', src, {
        heat = heat,
        streak = streak,
        difficultyBias = difficultyBias,
        economyMode = Config.Economy.mode,
        cardModeEnabled = Config.CardMode.enabled,
        stolenCards = cards,
        hasExploit = hasExploit
    })
end)

RegisterNetEvent('atmhack:server:finish', function(success, data)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local mode = (data and data.mode) or 'atm'
    local cardId = data and data.cardId or nil
    local tier = tonumber(data and data.tier) or 1
    local trace = tonumber(data and data.trace) or 0
    local elapsed = tonumber(data and data.elapsed) or 0
    local stageReached = tonumber(data and data.stageReached) or 1

    tier = math.min(math.max(tier, 1), 3)
    trace = math.min(math.max(trace, 0), 100)

    playerCooldowns[src] = now() + Config.PlayerCooldown

    local heat = playerHeat[src] or 0

    if success then
        if mode == 'card' and Config.CardMode.enabled then
            local marked, cardInfo = markCardUsed(src, cardId)
            if not marked then
                notify(src, 'Invalid or expired cloned card selected.', 'error')
                success = false
            else
                if Config.CardMode.requireExploitItem then
                    if not playerHasExploit(player) then
                        notify(src, ('Missing required exploit drive: %s'):format(Config.RequiredItems.exploit.name), 'error')
                        success = false
                    else
                        burnExploit(src, player)
                    end
                end

                if success then
                    computeCardReward(src, player, cardInfo, tier, trace, elapsed, stageReached)
                    playerHeat[src] = math.min(12, heat + tier)
                end
            end
        else
            if not playerHasExploit(player) then
                notify(src, ('Missing required exploit drive: %s'):format(Config.RequiredItems.exploit.name), 'error')
                success = false
            else
                burnExploit(src, player)
            end
        end

        if success and mode ~= 'card' then
            computeATMReward(src, player, tier, trace, elapsed, stageReached)
        end
    end

    if not success then
        playerStreak[src] = 0
        playerHeat[src] = math.max(0, heat - 1)

        if mode == 'card' and cardId and Config.CardMode.consumeOnAttempt then
            markCardUsed(src, cardId)
        end

        notify(src, 'Hack failed. Security trace escalated.', 'error')
        broadcastPoliceAlert(coords)
    end

    globalCooldownUntil = now() + Config.GlobalCooldown
    TriggerClientEvent('hud:client:UpdateStress', src, success and Config.SuccessStress or Config.FailStress)
end)

AddEventHandler('playerDropped', function()
    local src = source
    playerCooldowns[src] = nil
    playerHeat[src] = nil
    playerStreak[src] = nil
    clonedCards[src] = nil
end)
