# Blackjack (WoW Classic MoP) — README

**Version:** 1.0.1
**Author:** Brewer (Discord: `jbrewer.`)
**Compatibility:** Classic Era / Classic MoP private servers
**Files:** `Blackjack.lua`, `Blackjack.toc`
**SavedVariables:** `Blackjack_DB`

---

## Overview

Trade-first, whisper-driven Blackjack for WoW with a clean, compact dealer UI and weekly leaderboard. Players **/roll 1–13** to draw their cards; the **dealer uses /roll** for the upcard and for all dealer actions (ENHC rules: no hole card until resolve). Bets are handled via the trade window, payouts are returned via trade, and the addon keeps session/weekly stats, a “Top Players” leaderboard, and “Host Net” (dealer profit/loss) tracking. Optional **/emote announcements** make your table feel like a real casino.

### Highlights

* **Trade-first flow** with strict min/max bet range
* **ENHC ruleset** (European No-Hole-Card): dealer shows only one upcard until resolution
* **Exact roll mapping** 1→A, 11→J, 12→Q, 13→K
* **Whisper-only commands** (`hit`, `stand`, `double`, `stats`, `leaderboard`, etc.)
* **TSM-like compact UI**, draggable, and **resizable**
* **Leaderboard** (persists across reloads), resets **Tuesdays 10:00 CST**
* **Host Net** (daily and weekly), daily reset **10:00 CST**
* **Last Payout** display for quick dealer reference
* **Optional emote** announcements for bets, rolls, cards, and results

---

## Installation

1. Create an addon folder:

   ```
   World of Warcraft/_classic_/Interface/AddOns/Blackjack
   ```
2. Place both files inside:

   ```
   Blackjack.lua
   Blackjack.toc
   ```
3. Ensure your `.toc` contains the SavedVariables line (needed for persistent leaderboard/stats):

   ```ini
   ## Interface: 100207
   ## Title: Blackjack
   ## Notes: Trade-first Blackjack with license gate
   ## Author: Brewer
   ## Version: 1.0.0
   ## SavedVariables: Blackjack_DB

   Blackjack.lua
   ```
4. Launch the game (or `/reload`). You should see:

   ```
   Blackjack loaded. ENHC dealer: one upcard via /roll; hole & hits roll during resolve...
   ```

> ❗ If you get a console warning about SavedVariables, double-check the `## SavedVariables: Blackjack_DB` line is present in your `.toc`.

---

## Configuration

All knobs live near the top of `Blackjack.lua`:

```lua
local MIN_BET_C       = 50  * 10000   -- 50g
local MAX_BET_C       = 1000 * 10000  -- 1000g
local DAILY_BONUS_C   = 1   * 10000
local STARTING_COPPER = 0
local DEALER_STANDS_SOFT_17 = true
local BJ_PAY_NUM, BJ_PAY_DEN = 3, 2    -- 3:2 blackjack
local USE_COLOR = false
local NUM_DEALER_SUITS = 4             -- 1..4 variety for suits
local RULESET_ENHC = true               -- European No-Hole-Card
local DO_EMOTES = true                  -- announce via /emote
```

* **MIN\_BET\_C / MAX\_BET\_C**: bet limits in copper
* **DEALER\_STANDS\_SOFT\_17**: set to `false` if you want H17
* **RULESET\_ENHC**: keep `true` for no-hole-card until resolve
* **DO\_EMOTES**: set `false` to silence table chatter

Time-based resets use server time with a simple DST approximation to match **CST** schedules.

---

## How to Play (Flow)

1. **Player joins (optional):**

   * Player whispers the dealer: `join` or `help` to see basics.

2. **Place a bet (trade-first):**

   * Player opens **Trade** with the dealer and adds a bet within the allowed range (e.g., 50g–1000g).
   * **Both accept** the trade. The addon announces the bet (if emotes are enabled) and starts the round.

3. **Initial deal:**

   * **Player** rolls twice: `/roll 1-13` for first and second cards (the addon whispers prompts).
   * **Dealer** rolls **once** for the **upcard** (ENHC). The hole card is not drawn yet.

4. **Player actions (via whisper):**

   * `hit`, `stand`, or `double` (double only on first decision with 2 cards):

     * If `double`: player opens a **second trade** equal to the original stake; both accept; player then rolls one final card.

5. **Dealer resolve:**

   * When player stands/doubles, the dealer plays out via **/roll**:

     * If only the upcard exists, the **next roll becomes the hole card**.
     * Dealer continues rolling hits until standing (S17 by default) or busting.
   * The addon reveals dealer’s hand, determines result, and **queues payout**.

6. **Payout (trade):**

   * Dealer clicks **“Say Paying”** or opens trade using **“Open Trade”**; the queued amount is shown in the UI as **Next Payout**.
   * Once both accept the payout trade, the addon marks it delivered and records **Last Payout**.

---

## Dealer Panel (UI)

* **Header:** “Blackjack — Host Panel”
* **Info (left):**

  * **Partner:** current player name (sticky during round)
  * **Mode:** `playing`, `dealing (dealer upcard)`, or current trade mode
  * **Stake:** active hand stake
  * **Next Payout:** payout currently queued
  * **Last Payout:** most recent payout delivered
  * **Host Net (Today):** dealer net, resets daily at **10:00 CST**
  * **Host Net (Week):** dealer net for the week, resets **Tuesday 10:00 CST**
* **Leaderboard (right):** Top 3 weekly winners (persists; weekly reset Tuesday 10:00 CST)
* **Hands (center):**

  * **Player Hand:** card list + total
  * **Dealer Hand:** shows **upcard + \[??]** until reveal; full hand + total after resolve
* **Buttons (bottom-right):**

  * **Open Trade** – targets current partner and initiates trade
  * **Say Paying** – whispers the player to accept payout trade
  * **Force Reveal** – force dealer to complete plays and reveal (admin tool)
  * **Reset Round** – aborts round, clears pending rolls/trade state
  * **Rules** – opens a scrollable rules/commands window
* **Quality of life:**

  * **Draggable, resizable** (grab the bottom-right size handle)
  * Compact, TSM-like styling to avoid overlaps

---

## Player Commands (Whisper to Dealer)

* `join` — intro message
* `help` — brief help
* `balance` or `gold` — (if used with an internal bank; this addon tracks stats, not an actual balance by default)
* `daily` — grants a small daily bonus (cosmetic ledger entry)
* `hit` — draw a card (prompts `/roll 1-13`)
* `stand` — stop drawing; dealer resolves
* `double` or `double down` — double the stake (trade equal amount), one card, then stand
* `stats` — shows your personal record
* `leaderboard` — shows top winners

> Players **always** roll with `/roll 1-13`. The addon validates roll bounds and ignores other ranges.

---

## Emote Announcements (Optional)

Toggle with `DO_EMOTES` at the top of the file.

When enabled, the dealer will emote:

* **Bet accepted:** “accepts a bet of X from <Player>.”
* **Player roll:** “notes <Player>’s roll: N.”
* **Player cards:** “deals <Player> <Card>…”
* **Dealer upcard:** “shows an upcard: <Card>.”
* **Dealer hole/hits:** “draws a hole card.” / “draws a dealer hit card.”
* **Reveal:** “reveals <Dealer Hand> (Total).”
* **Results:** “<Player> wins. Paying X.” / “wins against <Player>.” / “push with <Player>. Returning X.”

If this is too chatty for your venue, set `DO_EMOTES = false`.

---

## Persistence & Resets

* **SavedVariables:** `Blackjack_DB`
  Persists **Leaderboard**, **Per-player stats**, **Weekly & Daily Host Net**, and **session totals** across `/reload` and relogs.
* **Leaderboards & Weekly Host Net:** reset **every Tuesday at 10:00 CST**
* **Daily Host Net:** resets **daily at 10:00 CST**
* Time is based on server time with an approximation for DST.

---

## ENHC Ruleset Details

* **ENHC (European No Hole Card)**: dealer **does not** take a hole card at the initial deal. Only one upcard is shown. The hole card is drawn later (via `/roll`) when resolving after the player has stood/doubled.
* **Insurance is disabled** under ENHC (no peek possible).
* **Blackjack payout:** Default **3:2** (configurable).
* **Double:** Only on first decision with a 2-card hand; one additional card, then stand.
* **Soft 17:** Dealer stands by default (toggle `DEALER_STANDS_SOFT_17`).

---

## Troubleshooting

**I see `SavedVariables missing` warning at login.**
→ Ensure your `.toc` includes:

```
## SavedVariables: Blackjack_DB
```

Reload the UI.

**UI elements overlap on small screens.**
→ The panel is resizable; grab the bottom-right handle to widen. Layout autoscales.

**“attempt to call global '...' (a nil value)”**
→ Make sure you replaced the entire `Blackjack.lua` with the latest full file. Partial merges often cause forward reference errors.

**Payout wasn’t detected unless the player accepted first.**
→ The addon reads the correct money source based on mode:

* **Bet/Double:** reads **target money** (player’s side)
* **Payout:** reads **player (dealer) money**
  If you still hit issues, confirm **both accept** the trade and that the correct copper amount is placed on the correct side.

**Rolls aren’t detected.**
→ The addon parses English system text:
`"<Name> rolls X (min-max)"`
If your client/server uses a different language/format, adjust `onChatMsgSystem`’s pattern.

---

## Security & Fair Play

* All card draws are mapped from visible **/roll 1–13** results (players) or from dealer `/roll` for transparency.
* Suits are randomized for display only (don’t affect totals).
* Whispers keep the flow tidy; emotes can be disabled.

---

## Development Notes

* Compact, dependency-free UI (TSM-inspired styling, no external libs).
* Classic-safe resize handling (`SetResizeBounds` used when available).
* Internal per-player stats: rounds, wins, losses, pushes, blackjacks, net.
* Extensible data model (`Blackjack_DB`) for future features.

---

## Changelog

**1.0.0**

* Initial public release: ENHC rules, resizable host UI, leaderboard persistence with weekly resets, daily & weekly Host Net, last payout tracking, optional emote announcements.

---

## License

**Proprietary** — © Brewer.
For permissions or custom licensing, contact **`jbrewer.`** on Discord.

---

## Credits

Designed and built by **Brewer**.
Thanks to testers and table regulars for feedback and feature ideas. 🎲🃏
