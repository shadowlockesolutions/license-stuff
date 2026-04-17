# qb-atm-intrusion

Advanced ATM hacking resource for QBCore with **laptop deployment gameplay**, a fully animated cyber UI, direct **QS-Banking payout support**, and optional **stolen-card compromise mode**.

## Core Features

- **Laptop-first hack flow** (deploy near ATM, boot exploit, run intrusion stages).
- **Two exploit sources inside UI**:
  - **ATM Bus** (standard ATM intrusion payout flow)
  - **Stolen Card** (swipe stolen card profile, crack credentials, siphon victim funds)
- **One-time stolen card lifecycle**:
  - steal card from nearby player (`/stealcard`)
  - use card once in hack flow
  - card is consumed and globally burned so it cannot be reused
- **Multi-stage minigame suite**:
  1. Pattern memory injection
  2. Wire bypass sequencing
  3. Cipher bruteforce with exact/near hints
- **Risk profile selector** (Ghost / Balanced / Overclock) that dynamically changes difficulty and reward potential.
- **Live telemetry HUD** inside the NUI:
  - Trace level
  - Stealth integrity
  - Node access progress
- **Heat + streak progression** that evolves long-term difficulty and payout scaling.
- **Required device loadout** (laptop + exploit drive) with configurable consumption behavior.
- **Police alerting + dispatch hook** on failed runs.
- **QS-Banking adapter** with automatic fallback to QBCore money if qs export is unavailable.

## Dependencies

- `qb-core`
- `qs-banking` (recommended if using `Config.Economy.mode = 'qs-banking'`)
- inventory item definitions for:
  - `laptop_green`
  - `trojan_usb`
  - `stolen_bank_card`

## Installation

1. Place this resource in your server resources directory.
2. Add to `server.cfg`:

```cfg
ensure qb-atm-intrusion
```

3. Ensure `qb-core` (and `qs-banking` if used) starts before this resource.
4. Configure `config.lua`:
   - `Config.RequiredItems.laptop.name`
   - `Config.RequiredItems.exploit.name`
   - `Config.StolenCardItem`
   - `Config.CardMode.*`
   - `Config.Economy.mode`
   - `Config.RequiredPolice`, cooldowns, and reward tuning

## Usage

- Walk up to an ATM.
- Use your **laptop item** (`laptop_green` by default) from inventory while near ATM.
- Your laptop prop deploys at ATM terminal.
- Pick risk tier and exploit source.
- Complete all 3 stages before trace reaches 100% or timer expires.

### Stolen Card Flow

1. Get close to a player and run `/stealcard`.
2. Start ATM hack and switch source mode to **Stolen Card**.
3. Select stolen card in dropdown and complete intrusion.
4. Script drains a configured percentage/limit from that victim's bank (if online), then burns the card.

## Economy Modes

- `qs-banking`: attempts `exports['qs-banking']:AddMoney(src, amount, reason)`.
- `qb-cash`: pays via `player.Functions.AddMoney`.
- `custom`: forwards payout to your configured event.

## Integration Notes

- If your inventory UI event differs, update `inventory:client:ItemBox` in `server/main.lua`.
- If your stress/hud event differs, update `hud:client:UpdateStress` in `server/main.lua`.
- If your QS-Banking export signature differs, adjust the `payout()` adapter in `server/main.lua`.
