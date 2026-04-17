Config = {}

Config.Framework = 'qbcore'

-- Inventory / item flow
Config.RequiredItems = {
    laptop = {
        name = 'laptop_green',
        removeOnUse = false
    },
    exploit = {
        name = 'trojan_usb',
        removeOnUse = true
    },
    skimmer = {
        name = 'atm_skimmer',
        removeOnUse = true
    }
}

Config.CreditCardItem = 'bank_card'
Config.SkimDistance = 1.8
Config.SkimmerDurationMinutes = 60
Config.SkimmerCaptureCooldown = 90 -- seconds per victim per skimmer
Config.SkimmerMaxPerPlayer = 4

Config.CardMode = {
    enabled = true,
    requireExploitItem = false,
    minBalanceAfterDrain = 1500,
    maxDrain = 3200,
    percentRange = { min = 0.22, max = 0.38 },
    fallbackReward = { min = 900, max = 1400 },
    consumeOnAttempt = true,
    blockReuseGlobally = true
}

-- Economy / banking behavior
Config.Economy = {
    mode = 'qs-banking', -- 'qs-banking' | 'qb-cash' | 'custom'
    qbMoneyType = 'cash',
    qsStatement = 'ATM intrusion payout',
    customRewardEvent = nil -- server event name; payload: (src, amount, meta)
}

-- Security gates
Config.RequiredPolice = 2
Config.GlobalCooldown = 12 * 60 -- seconds
Config.PlayerCooldown = 20 * 60 -- seconds
Config.MaxDistanceFromATM = 2.0

-- Reward tuning
Config.BaseReward = { min = 1400, max = 3500 }
Config.RiskBonus = {
    [1] = 1.0,
    [2] = 1.18,
    [3] = 1.42
}
Config.HeatBonusCap = 1.45
Config.StreakBonusCap = 1.5

-- Hack runtime
Config.HackDuration = 95 -- max seconds in UI
Config.LaptopProp = `prop_laptop_lester2`

Config.ATMModels = {
    `prop_atm_01`,
    `prop_atm_02`,
    `prop_atm_03`,
    `prop_fleeca_atm`
}

-- Dispatch integration
Config.AlertJobs = { 'police', 'sheriff' }
Config.DispatchEvent = nil -- e.g. 'ps-dispatch:server:notify'

-- Player effects
Config.SuccessStress = 10
Config.FailStress = 24

Config.UniqueFeatures = {
    DynamicDifficulty = true,
    HeatSystem = true,
    ProgressiveRiskModes = true,
    RewardStreak = true,
    QSBankingAdapter = true,
    LaptopDeploySequence = true,
    PlayerCardCompromiseMode = true,
    ATMPhysicalSkimmers = true
}
