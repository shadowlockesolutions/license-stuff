local QBCore = exports['qb-core']:GetCoreObject()

local globalCooldownUntil = 0
local playerCooldowns = {}
local playerHeat = {}
local playerStreak = {}
local burnedCards = {}

local function now()
    return os.time()
end

local function notify(src, msg, typ)
    TriggerClientEvent('QBCore:Notify', src, msg, typ or 'primary')
end

local function randomCardId()
    return ('CARD-%s-%04d'):format(os.time(), math.random(1000, 9999))
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

local function getStolenCards(player)
    local cards = {}
    local items = player.PlayerData.items or {}

    for slot, item in pairs(items) do
        if item and item.name == Config.StolenCardItem and item.info and item.info.cardId then
            local cardId = item.info.cardId
            if not burnedCards[cardId] and not item.info.used then
                cards[#cards + 1] = {
                    slot = slot,
                    cardId = cardId,
                    holder = item.info.holder or 'unknown',
                    bankName = item.info.bankName or 'LS Central',
                    masked = item.info.masked or '**** **** **** ****',
                    citizenid = item.info.citizenid
                }
            end
        end
    end

    return cards
end

local function playerHasLaptop(player)
    local laptopRule = Config.RequiredItems.laptop
    if not laptopRule then return true end

    local item = player.Functions.GetItemByName(laptopRule.name)
    return item ~= nil
end

local function playerHasExploit(player)
    local exploitRule = Config.RequiredItems.exploit
    if not exploitRule then return true end

    local item = player.Functions.GetItemByName(exploitRule.name)
    return item ~= nil
end

local function burnExploit(src, player)
    local exploitRule = Config.RequiredItems.exploit
    if not exploitRule or not exploitRule.removeOnUse then return end

    player.Functions.RemoveItem(exploitRule.name, 1)

    local shared = QBCore.Shared.Items[exploitRule.name]
    if shared then
        TriggerClientEvent('inventory:client:ItemBox', src, shared, 'remove')
    end
end

local function consumeStolenCard(src, player, cardId)
    local items = player.PlayerData.items or {}

    for slot, item in pairs(items) do
        if item and item.name == Config.StolenCardItem and item.info and item.info.cardId == cardId then
            player.Functions.RemoveItem(Config.StolenCardItem, 1, slot)
            local shared = QBCore.Shared.Items[Config.StolenCardItem]
            if shared then
                TriggerClientEvent('inventory:client:ItemBox', src, shared, 'remove')
            end
            return true, item.info
        end
    end

    return false, nil
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

        if ok then
            return true
        end

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
    local fallbackMin = Config.CardMode.fallbackReward.min
    local fallbackMax = Config.CardMode.fallbackReward.max
    local reward = math.random(fallbackMin, fallbackMax)

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
                notify(victim.PlayerData.source, ('Your bank card ending %s was compromised. $%s withdrawn.'):format((cardInfo.masked or '****'):sub(-4), drain), 'error')
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

QBCore.Functions.CreateUseableItem(Config.RequiredItems.laptop.name, function(source, item)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end

    local hasLaptop = player.Functions.GetItemByName(Config.RequiredItems.laptop.name)
    if not hasLaptop then
        notify(source, ('You need a %s to start intrusion.'):format(Config.RequiredItems.laptop.name), 'error')
        return
    end

    TriggerClientEvent('atmhack:client:useLaptop', source)
end)

RegisterNetEvent('atmhack:server:stealCardFromPlayer', function(targetId)
    local src = source
    local thief = QBCore.Functions.GetPlayer(src)
    local target = QBCore.Functions.GetPlayer(tonumber(targetId))

    if not thief or not target then
        notify(src, 'No valid target detected for card theft.', 'error')
        return
    end

    if src == tonumber(targetId) then
        notify(src, 'You cannot steal your own card.', 'error')
        return
    end

    local cardId = randomCardId()
    local holder = (target.PlayerData.charinfo and (target.PlayerData.charinfo.firstname .. ' ' .. target.PlayerData.charinfo.lastname)) or ('CID ' .. target.PlayerData.citizenid)
    local masked = ('%s%s%s%s'):format('**** **** **** ', tostring(math.random(1000, 9999)))

    local info = {
        cardId = cardId,
        holder = holder,
        citizenid = target.PlayerData.citizenid,
        bankName = 'Pacific Banking Cluster',
        masked = masked,
        pinHint = tostring(math.random(10, 99)) .. 'X'
    }

    local added = thief.Functions.AddItem(Config.StolenCardItem, 1, false, info)
    if not added then
        notify(src, 'You could not stash the stolen card (inventory full).', 'error')
        return
    end

    local shared = QBCore.Shared.Items[Config.StolenCardItem]
    if shared then
        TriggerClientEvent('inventory:client:ItemBox', src, shared, 'add')
    end

    notify(src, ('You lifted a cloned card from %s.'):format(holder), 'success')
    notify(target.PlayerData.source, 'You feel your wallet lighter... your card may be compromised.', 'error')
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
    local stolenCards = getStolenCards(player)
    local hasExploit = playerHasExploit(player)

    if not hasExploit and (#stolenCards == 0 or not Config.CardMode.enabled) then
        notify(src, ('Missing required exploit drive: %s'):format(Config.RequiredItems.exploit.name), 'error')
        return
    end

    TriggerClientEvent('atmhack:client:start', src, {
        heat = heat,
        streak = streak,
        difficultyBias = difficultyBias,
        economyMode = Config.Economy.mode,
        cardModeEnabled = Config.CardMode.enabled,
        stolenCards = stolenCards,
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
            local cards = getStolenCards(player)
            local cardInfo
            for _, card in ipairs(cards) do
                if card.cardId == cardId then
                    cardInfo = card
                    break
                end
            end

            if not cardInfo then
                notify(src, 'Invalid or expired stolen card selected.', 'error')
                success = false
            else
                local removed, rawInfo = consumeStolenCard(src, player, cardId)
                if not removed then
                    notify(src, 'Card could not be consumed; intrusion rejected.', 'error')
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

                    if Config.CardMode.blockReuseGlobally then
                        burnedCards[cardId] = true
                    end

                    if success then
                        computeCardReward(src, player, rawInfo, tier, trace, elapsed, stageReached)
                        playerHeat[src] = math.min(12, heat + tier)
                    end
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
            local removed = consumeStolenCard(src, player, cardId)
            if removed and Config.CardMode.blockReuseGlobally then
                burnedCards[cardId] = true
            end
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
end)
