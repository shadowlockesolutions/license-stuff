# qb-atm-intrusion

Advanced ATM hacking resource for QBCore with **laptop deployment gameplay**, full cyber NUI, direct **QS-Banking payout support**, and a **credit-card skimming system**.

## Core Features

- **Laptop-first hack flow** using inventory item (no `/hackatm` command needed).
- **Two exploit sources in UI**:
  - **ATM Bus** (normal ATM intrusion payout)
  - **Cloned Card** (use skimmed real player card metadata)
- **Physical ATM skimmers**:
  - install skimmer item on ATM
  - skimmer captures nearby players’ real card metadata from their credit-card item
  - skimmed cards appear in hacker UI card selector
  - card entries are one-time use and burned after attempt/success
- **Multi-stage minigame suite**:
  1. Pattern memory injection
  2. Wire bypass sequencing
  3. Cipher bruteforce with exact/near hints
- **Risk profile selector** (Ghost / Balanced / Overclock).
- **Live telemetry HUD** (trace, stealth integrity, node progress).
- **Heat + streak progression** with configurable security gates.
- **QS-Banking adapter** with fallback to QBCore money.

## Dependencies

- `qb-core`
- `qs-banking` (recommended for `Config.Economy.mode = 'qs-banking'`)
- Inventory item definitions for:
  - `laptop_green`
  - `trojan_usb`
  - `atm_skimmer`
  - `bank_card` (or your configured `Config.CreditCardItem`)

## Installation

1. Place resource in your server resources directory.
2. Add to `server.cfg`:

```cfg
ensure qb-atm-intrusion
```

3. Ensure `qb-core` (and `qs-banking` if used) starts before this resource.
4. Configure `config.lua`:
   - `Config.RequiredItems.*`
   - `Config.CreditCardItem`
   - `Config.SkimmerDurationMinutes`, `Config.SkimmerCaptureCooldown`, `Config.SkimmerMaxPerPlayer`
   - `Config.CardMode.*`
   - `Config.Economy.mode`

## Usage

- Walk up to ATM and use your **laptop item** from inventory.
- Pick risk tier and exploit source in UI.
- For card mode, install skimmers first and wait for card captures.

### Skimmer Flow

1. Use skimmer item (`atm_skimmer`) near ATM.
2. Skimmer runs for configured duration and captures nearby player card metadata.
3. When you start a hack, cloned cards appear in card selector.
4. Complete intrusion to drain configured amount from victim bank (if online).

## Economy Modes

- `qs-banking`: `exports['qs-banking']:AddMoney(src, amount, reason)`
- `qb-cash`: `player.Functions.AddMoney`
- `custom`: custom configured server event

## Integration Notes

- If your card item metadata key names differ, adjust `getPlayerCreditCardInfo()` in `server/main.lua`.
- If your inventory/hud events differ, update `inventory:client:ItemBox` and `hud:client:UpdateStress` in `server/main.lua`.
