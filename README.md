## Updated `README.md`

```markdown
# Blackjack (WoW Classic MoP) — README

**Version:** 1.0.0  
**Author:** Brewer (Discord: `jbrewer.`)  
**Compatibility:** Classic Era / Classic MoP private servers  
**Files:** `Blackjack.lua`, `Blackjack.toc`  
**SavedVariables:** `Blackjack_DB`

---

## Overview

Trade-first, whisper-driven Blackjack with an ENHC dealer (one upcard first; hole/hits rolled at resolve), a compact TSM-style dealer UI, weekly leaderboard, and Host Net tracking. Players **/roll 1–13** to draw cards; the dealer also rolls for their cards so everything’s visible and fair.

### Highlights

- **Trade-first flow** (min/max stakes)
- **ENHC rules** (no hole card until resolve)
- **Exact roll mapping** 1→A, 11→J, 12→Q, 13→K
- **Whisper-only** actions: `hit`, `stand`, `double`, `stats`, `leaderboard`
- **Resizable**, compact UI with **Last Payout** and daily/weekly **Host Net**
- **Leaderboard** persists; weekly reset **Tuesday 10:00 CST**
- **Minimal emote set** wrapped in **purple diamond** `{rt3}`:
  - Bet accepted
  - Final hands (player vs dealer) at reveal / end
  - Result amount (**won** or **lost**)

---

## Installation

1. Create:
```

World of Warcraft/*classic*/Interface/AddOns/Blackjack

```
2. Place files:
```

Blackjack.lua
Blackjack.toc

````
3. Ensure `.toc` has SavedVariables:
```ini
## Interface: 100207
## Title: Blackjack
## Notes: Trade-first Blackjack with license gate
## Author: Brewer
## Version: 1.0.0
## SavedVariables: Blackjack_DB

Blackjack.lua
````

4. `/reload` or relog.

If you see a SavedVariables warning, re-check the `## SavedVariables: Blackjack_DB` line.

---

## Config (in `Blackjack.lua`)

```lua
local MIN_BET_C       = 50  * 10000
local MAX_BET_C       = 1000 * 10000
local DEALER_STANDS_SOFT_17 = true
local BJ_PAY_NUM, BJ_PAY_DEN = 3, 2
local RULESET_ENHC    = true
local DO_EMOTES       = true
```

* Set **`DO_EMOTES = false`** to disable all emotes.

---

## Flow

1. **Player trades** the dealer with an allowed stake (e.g., 50g–1000g).

   * On accept: the addon starts the round and **emotes** the bet.
2. **Player rolls** `/roll 1-13` for two cards (prompts via whisper).
3. **Dealer shows one upcard** via `/roll`.
4. **Player acts** via whisper (`hit`, `stand`, `double`).
5. **Dealer resolves** (rolls hole + hits) and reveals.

   * The addon **emotes the final hands** (player vs dealer).
   * The addon **emotes the result amount**: `<Player> wins X.` or `<Player> loses X.`
6. **Payout trade** to deliver winnings (UI shows **Next Payout** + **Last Payout**).

---

## Minimal Emotes (wrapped in `{rt3}`)

* **Bet accepted:** `{rt3} accepts a bet of 100g from Player {rt3}`
* **Final hands:** `{rt3} Final — Player: A of Spades  K of Hearts (21)  vs  Dealer: 9 of Clubs  7 of Hearts (16). {rt3}`
* **Result:** `{rt3} Player wins 150g. {rt3}` or `{rt3} Player loses 100g. {rt3}`

No emotes for individual rolls, hits, doubles, or intermediate dealer cards.

---

## UI

* **Partner / Mode / Stake**
* **Next Payout / Last Payout**
* **Host Net (Today / Week)**
* **Top Players (weekly)**
* **Player Hand / Dealer Hand**
* Buttons: **Open Trade**, **Say Paying**, **Force Reveal**, **Reset Round**, **Rules**
* **Draggable & resizable** (grab the bottom-right handle)

---

## Resets & Persistence

* **SavedVariables:** `Blackjack_DB`
  Persists leaderboard, player stats, and host nets across reloads/logouts.
* **Daily Host Net reset:** 10:00 CST
* **Weekly reset (Leaderboard & Weekly Host Net):** Tuesday 10:00 CST

---

## Commands (whisper to dealer)

* `join`, `help`
* `balance`, `gold`, `daily`
* `hit`, `stand`, `double` (double only on first decision w/ two cards)
* `stats`, `leaderboard`

---

## Troubleshooting

* **Payout detection:** During payout, the addon reads **dealer’s** money (your side). For bets/doubles it reads **player’s** money (their side). Both must accept.
* **Roll parsing:** Expects English system text: `"<Name> rolls X (min-max)"`.

---

## Credits

Created by **Brewer** (`jbrewer.` on Discord).
Enjoy the table! 🎲🃏

```

If you want the emote text phrased differently (e.g., “wins **net** X” vs “wins **paid** X”), tell me your preferred wording and I’ll tweak the strings.
::contentReference[oaicite:0]{index=0}
```
