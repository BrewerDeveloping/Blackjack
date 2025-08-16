-- Blackjack (Trade-First, Auto-Reset After Round, Whisper-Only, ASCII-safe, Exact Roll Mapping)
-- GUI shows Player/Dealer hands; suits spelled out in display ("A of Spades", etc.)
-- Player /roll 1–13 for cards (1=A, 11=J, 12=Q, 13=K).
-- Dealer: ENHC rules — initial ONE upcard via /roll; hole & subsequent hits via /roll when resolving after player stands/doubles.
-- Author: Brewer | jbrewer. on Discord
-- IMPORTANT: Your .toc must include:  ## SavedVariables: Blackjack_DB

local ADDON = "Blackjack"

-- ===================== CONFIG =====================
local MIN_BET_C       = 50  * 10000   -- 50g
local MAX_BET_C       = 1000 * 10000  -- 1000g
local DAILY_BONUS_C   = 1   * 10000
local STARTING_COPPER = 0
local DEALER_STANDS_SOFT_17 = true
local BJ_PAY_NUM, BJ_PAY_DEN = 3, 2        -- 3:2 blackjack
local USE_COLOR = false
local NUM_DEALER_SUITS = 4                 -- how many suit varieties to randomize (1..4)
local RULESET_ENHC = true                  -- ENHC: no hole card until resolve
local DO_EMOTES = true                     -- announce key events via /emote (bet, final hands, win/loss only)

-- UI theme (TSM-style)
local TEX_WHITE = "Interface\\Buttons\\WHITE8x8"
local COLOR = {
  bg       = {0.09, 0.09, 0.09, 0.95},
  header   = {0.12, 0.12, 0.12, 1.00},
  panel    = {0.11, 0.11, 0.11, 0.95},
  line     = {0.20, 0.20, 0.20, 1.00},
  accent   = {1.00, 0.86, 0.26, 1.00},
  text     = {0.90, 0.90, 0.90, 1.00},
  subtext  = {0.75, 0.75, 0.75, 1.00},
  good     = {0.33, 0.82, 0.33, 1.00},
  bad      = {0.85, 0.33, 0.33, 1.00},
  btn      = {0.15, 0.15, 0.15, 1.00},
  btnHL    = {0.22, 0.22, 0.22, 1.00},
}

-- CST offsets (simple DST approx)
local CST_OFFSET_STD = -6 * 3600
local CST_OFFSET_DST = -5 * 3600

-- ===================== DB =====================
Blackjack_DB = Blackjack_DB or {}
local DB

local function approxIsDST(utcEpoch)
  local m = tonumber(date("!%m", utcEpoch)) or 1
  local d = tonumber(date("!%d", utcEpoch)) or 1
  if m >= 4 and m <= 10 then return true end
  if m <= 2 or m == 12 then return false end
  if m == 3 then return d >= 8 end
  if m == 11 then return d <= 6 end
  return false
end
local function nowCST()
  local utc = (GetServerTime and GetServerTime()) or time()
  local off = approxIsDST(utc) and CST_OFFSET_DST or CST_OFFSET_STD
  return utc + off
end

local function ensureDB()
  Blackjack_DB = Blackjack_DB or {}
  DB = Blackjack_DB
  DB.players = DB.players or {}
  DB.hands   = DB.hands or {}
  DB.session = DB.session or {
    rounds=0, playerWins=0, dealerWins=0, pushes=0, staked=0, paidOut=0,
    lastPayout=0
  }
  DB.wins    = DB.wins or { hostNet = 0, weekHostNet = 0, lastResetDayCST = "" }
  DB.leaderboard = DB.leaderboard or {} -- [player] = { profit = 0, lastWin = time() }
  DB.pstats = DB.pstats or {}           -- [player] = { rounds=0, wins=0, losses=0, pushes=0, bj=0, net=0 }
  DB.lbmeta = DB.lbmeta or { lastResetDayCST = "" } -- weekly reset tracker (Tuesday 10:00 CST)
  DB.meta = DB.meta or { installGUID = tostring((GetServerTime and GetServerTime()) or time()) .. "-" .. tostring(math.random(100000,999999)) }
end

local _didSVWarn = false
local function checkSavedVariables()
  if _didSVWarn then return end
  if not DB or not DB.meta or not DB.meta.installGUID then
    print("|cffff3333Blackjack: SavedVariables missing; add '## SavedVariables: Blackjack_DB' in your .toc or the leaderboard will reset on reload.|r")
    _didSVWarn = true
  end
end

local function ensurePlayer(name)
  ensureDB()
  DB.players[name] = DB.players[name] or { copper = STARTING_COPPER, lastDaily = "" }
  return DB.players[name]
end
local function ensureLB(name)
  DB.leaderboard[name] = DB.leaderboard[name] or { profit = 0, lastWin = 0 }
  return DB.leaderboard[name]
end
local function ensurePStats(name)
  DB.pstats[name] = DB.pstats[name] or { rounds=0, wins=0, losses=0, pushes=0, bj=0, net=0 }
  return DB.pstats[name]
end

-- Round owner (nil between rounds)
local CurrentPlayerName = nil

-- ===================== Trade state =====================
-- mode: "bet" | "double" | "payout" | nil
local Trade = { name=nil, mode=nil, amount=0 }
local function tradeReset()
  Trade.name=nil; Trade.mode=nil; Trade.amount=0
  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
end
local function readTradePartnerFromUI()
  if TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText() then
    local txt = TradeFrameRecipientNameText:GetText()
    if txt and txt ~= "" then return txt end
  end
  if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
    return Ambiguate and Ambiguate(UnitName("target"), "none") or UnitName("target")
  end
  return Trade.name
end

-- ===================== Utils =====================
local function myName()
  local n = UnitName and UnitName("player") or "Dealer"
  return Ambiguate and Ambiguate(n, "none") or n
end

local function esc(s) return tostring(s or ""):gsub("|","||") end
local function whisper(msg, player) SendChatMessage(esc(msg), "WHISPER", nil, player) end
local function emote(msg)
  if DO_EMOTES then
    SendChatMessage("{rt3} "..esc(msg).." {rt3}", "EMOTE")
  end
end

local function fmtMoney(c)
  c = math.max(0, math.floor(tonumber(c) or 0))
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local k = c % 100
  local pg = (g>0) and (USE_COLOR and string.format("|cffffd700%dg|r", g) or (g.."g")) or nil
  local ps = (s>0) and (USE_COLOR and string.format("|cffc7c7cf%ds|r", s) or (s.."s")) or nil
  local pk = ((k>0) or (g==0 and s==0)) and (USE_COLOR and string.format("|cffeda55f%dc|r", k) or (k.."c")) or nil
  local t={} if pg then t[#t+1]=pg end; if ps then t[#t+1]=ps end; if pk then t[#t+1]=pk end
  return table.concat(t," ")
end

local function today() return string.format("%s-%s-%s", date("!%Y"), date("!%m"), date("!%d")) end

local function maybeResetHostNet()
  ensureDB()
  local cst = nowCST()
  local ymd = date("!%Y-%m-%d", cst)
  local hour = tonumber(date("!%H", cst)) or 0
  if DB.wins.lastResetDayCST ~= ymd and hour >= 10 then
    DB.wins.hostNet = 0
    DB.wins.lastResetDayCST = ymd
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
  end
end

-- Weekly leaderboard & weekly host net reset: Tuesdays 10:00 CST
local function maybeResetLeaderboardWeekly()
  ensureDB()
  local cst = nowCST()
  local dow = tonumber(date("!%w", cst)) or 0 -- 0=Sun, 1=Mon, 2=Tue ...
  local hour = tonumber(date("!%H", cst)) or 0
  local diff = (dow - 2) % 7
  local tueEpoch = cst - diff * 86400
  local tueYMD = date("!%Y-%m-%d", tueEpoch)
  if (dow > 2 or (dow == 2 and hour >= 10)) and (DB.lbmeta.lastResetDayCST ~= tueYMD) then
    for _, rec in pairs(DB.leaderboard or {}) do
      if type(rec) == "table" then
        rec.profit = 0
        rec.lastWin = 0
      end
    end
    DB.wins.weekHostNet = 0
    DB.lbmeta.lastResetDayCST = tueYMD
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
  end
end

-- ===================== Cards & display =====================
local suitCodes = {"S","H","D","C"}
local suitNames = { S="Spades", H="Hearts", D="Diamonds", C="Clubs" }

local function rankFromRoll(n)
  n = tonumber(n) or 1
  if n < 1 then n = 1 elseif n > 13 then n = 13 end
  if n == 1  then return "A"
  elseif n == 11 then return "J"
  elseif n == 12 then return "Q"
  elseif n == 13 then return "K"
  else return tostring(n)
  end
end

local function addSuit(rank)
  rank = tostring(rank or "A")
  local idx = math.random(1, NUM_DEALER_SUITS)
  local code = suitCodes[idx] or "S"
  return rank..code
end

local function splitRank(card)
  local r = (card or ""):gsub("[^%w]","")
  if r == "" then return "A" end
  local last = r:sub(-1)
  if suitNames[last] then r = r:sub(1, #r-1) end
  if r == "10" then return "10" end
  local h = r:sub(1,1)
  if h=="A" or h=="K" or h=="Q" or h=="J" then return h end
  return r
end

local function splitSuit(card)
  local r = (card or ""):gsub("[^%w]","")
  local last = r:sub(-1)
  if suitNames[last] then return last end
  return "S"
end

local function cardValue(rank)
  if rank=="A" then return 11 end
  if rank=="K" or rank=="Q" or rank=="J" or rank=="10" then return 10 end
  return tonumber(rank) or 0
end

local function handValue(cards)
  local total, aces = 0, 0
  for _,c in ipairs(cards) do
    local r=splitRank(c)
    if r=="A" then aces=aces+1 end
    total = total + cardValue(r)
  end
  while total>21 and aces>0 do total=total-10; aces=aces-1 end
  local minTotal=0
  for _,cc in ipairs(cards) do
    local rr=splitRank(cc)
    minTotal=minTotal+(rr=="A" and 1 or cardValue(rr))
  end
  local soft = (minTotal ~= total)
  return total, soft
end

local function isBlackjack(cards)
  if #cards ~= 2 then return false end
  local r1,r2 = splitRank(cards[1]), splitRank(cards[2])
  local v1,v2 = cardValue(r1), cardValue(r2)
  return (r1=="A" and v2==10) or (r2=="A" and v1==10)
end

local function fmtCard(card)
  local r = splitRank(card)
  local s = suitNames[splitSuit(card)] or "Spades"
  if r == "A" then return "A of "..s
  elseif r == "K" then return "K of "..s
  elseif r == "Q" then return "Q of "..s
  elseif r == "J" then return "J of "..s
  else return r.." of "..s end
end

local function fmtHandLong(cards, hideSecond)
  if hideSecond and #cards >= 2 then
    return fmtCard(cards[1]).."  [??]"
  end
  local t = {}
  for i,c in ipairs(cards) do t[i] = fmtCard(c) end
  return table.concat(t, "  ")
end

-- ===================== Dealer reveal helper =====================
local function emoteFinalHands(player, H)
  local pt = ({handValue(H.phand)})[1] or 0
  local dt = ({handValue(H.dhand)})[1] or 0
  emote(string.format("Final — %s: %s (%d)  vs  Dealer: %s (%d).",
    player or "Player", fmtHandLong(H.phand, false), pt, fmtHandLong(H.dhand, false), dt))
end

local function whisperDealerReveal(player, H)
  local total = ({handValue(H.dhand)})[1]
  whisper(string.format("Dealer reveals: %s (%d).", fmtHandLong(H.dhand, false), total), player)
  -- Emote the final hands (player vs dealer) at reveal time
  emoteFinalHands(player, H)
end

-- ===================== Hand model =====================
local function handFor(player)
  ensureDB()
  DB.hands[player] = DB.hands[player] or {
    bet=0, original=0, state="idle", phand={}, dhand={}, doubled=false
  }
  return DB.hands[player]
end
local function clearHand(player) DB.hands[player] = nil end

-- Host Net math (positive = host up, negative = host down)
local function addHostNetDelta(H, outcome)
  local d = 0
  if outcome == "dealer" then d = H.bet
  elseif outcome == "push" then d = 0
  elseif outcome == "player" then d = -H.bet
  elseif outcome == "blackjack" then
    local win = math.floor(H.bet * BJ_PAY_NUM / BJ_PAY_DEN + 0.5)
    d = -win
  end
  DB.wins.hostNet = (DB.wins.hostNet or 0) + d
  DB.wins.weekHostNet = (DB.wins.weekHostNet or 0) + d
  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
end

local function addLeaderboardWin(player, H, outcome)
  if not player or not H then return end
  local lb = ensureLB(player)
  if outcome == "player" then
    lb.profit = lb.profit + (H.bet or 0)
    lb.lastWin = GetServerTime and GetServerTime() or time()
  elseif outcome == "blackjack" then
    local profit = math.floor((H.bet or 0) * BJ_PAY_NUM / BJ_PAY_DEN + 0.5)
    lb.profit = lb.profit + profit
    lb.lastWin = GetServerTime and GetServerTime() or time()
  end
end

-- ===================== Settle =====================
local function settle(player, outcome, payout_c)
  if outcome=="player" then DB.session.playerWins = DB.session.playerWins + 1
  elseif outcome=="dealer" then DB.session.dealerWins = DB.session.dealerWins + 1
  elseif outcome=="push" then DB.session.pushes = DB.session.pushes + 1
  elseif outcome=="blackjack" then DB.session.playerWins = DB.session.playerWins + 1 end
  if payout_c and payout_c>0 then DB.session.paidOut = DB.session.paidOut + payout_c end

  local H = handFor(player)
  local PStats = ensurePStats(player)
  PStats.rounds = PStats.rounds + 1

  if outcome == "player" then
    PStats.wins = PStats.wins + 1
    PStats.net  = PStats.net + (H.bet or 0)
    emote(string.format("%s wins %s.", player, fmtMoney(payout_c or 0)))
  elseif outcome == "dealer" then
    PStats.losses = PStats.losses + 1
    PStats.net    = PStats.net - (H.bet or 0)
    emote(string.format("%s loses %s.", player, fmtMoney(H.bet or 0)))
  elseif outcome == "push" then
    PStats.pushes = PStats.pushes + 1
    -- No emote for push per request
  elseif outcome == "blackjack" then
    PStats.wins = PStats.wins + 1
    PStats.bj   = (PStats.bj or 0) + 1
    local profit = math.floor((H.bet or 0) * BJ_PAY_NUM / BJ_PAY_DEN + 0.5)
    PStats.net = PStats.net + profit
    emote(string.format("%s wins %s (Blackjack).", player, fmtMoney(payout_c or 0)))
  end

  addHostNetDelta(H, outcome)
  addLeaderboardWin(player, H, outcome)

  clearHand(player)
  if CurrentPlayerName == player then CurrentPlayerName = nil end

  if outcome == "dealer" then
    if player then whisper("Round finished. You can open a new trade to bet again.", player) end
  else
    if player then whisper("Round finished. I will pay you via trade now (you can also bet again any time).", player) end
  end

  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
end

-- ===================== Dealer rolls via /roll =====================
local PendingDealerRoll = { expect=false, hand=nil, min=1, max=13, cb=nil }

local function dealerRollOnce(H, cb)
  PendingDealerRoll.expect = true
  PendingDealerRoll.hand   = H
  PendingDealerRoll.min    = 1
  PendingDealerRoll.max    = 13
  PendingDealerRoll.cb     = cb
  if RandomRoll then RandomRoll(1,13) end -- triggers "<Dealer> rolls X (1-13)"
end

-- ENHC: ONLY the upcard is rolled initially
local function dealerInitialUpcard(H, done)
  H.dhand = H.dhand or {}
  dealerRollOnce(H, function()
    if done then done() end
  end)
end

-- Dealer plays: if only upcard exists, first roll here becomes the "hole", then continue hits
local function dealerPlayAsync(H, onDone)
  local function step()
    local dTotal, dSoft = handValue(H.dhand)
    local mustStand = dTotal >= 17 and (DEALER_STANDS_SOFT_17 or not dSoft)
    if mustStand then
      if onDone then onDone(dTotal) end
    else
      dealerRollOnce(H, step)
    end
  end
  step()
end

-- ===================== ROLL CAPTURE (player + dealer) =====================
local PendingRoll = {} -- [player] = { expect=true, stage="deal1"/"deal2"/"hit"/"double", min=1,max=13 }

local function askPlayerToRoll(player, stageText, stageKey, minv, maxv)
  PendingRoll[player] = { expect=true, stage=stageKey, min=minv or 1, max=maxv or 13 }
  whisper(string.format("%s Please /roll %d-%d.", stageText, minv or 1, maxv or 13), player)
  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
end

local function takePlayerRoll(player, value)
  local st = PendingRoll[player]; if not st or not st.expect then return false end
  local n = tonumber(value) or -1
  if n < st.min or n > st.max then
    whisper(string.format("That roll was %d. Please roll %d-%d.", n, st.min, st.max), player)
    return true
  end

  whisper(string.format("Roll received: %d.", n), player)

  local H = handFor(player)
  local card = addSuit(rankFromRoll(n))

  if st.stage == "deal1" then
    table.insert(H.phand, card)
    whisper(string.format("Got it: %s", fmtCard(card)), player)
    PendingRoll[player] = nil
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
    askPlayerToRoll(player, "Roll for your second card.", "deal2", 1, 13)

  elseif st.stage == "deal2" then
    table.insert(H.phand, card)
    whisper(string.format("Second card: %s", fmtCard(card)), player)

    -- Dealer draws ONE upcard via /roll (ENHC)
    H.state = "awaiting-dealer-up"
    H.dhand = H.dhand or {}
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
    dealerInitialUpcard(H, function()
      -- After upcard is in place, player acts
      H.state = "player"
      local pTotal = ({handValue(H.phand)})[1]
      local dUp = fmtHandLong({H.dhand[1]}, true)

      if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end

      if isBlackjack(H.phand) then
        -- Emote final known cards for BJ (dealer has only upcard in ENHC)
        emote(string.format("Final — %s: %s (21)  vs  Dealer shows: %s.",
          player, fmtHandLong(H.phand, false), fmtCard(H.dhand[1] or "A")))
        local win  = math.floor(H.bet * BJ_PAY_NUM / BJ_PAY_DEN + 0.5)
        local pay  = H.bet + win
        Trade.mode = "payout"; Trade.amount = pay; if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
        whisper(string.format("Player: %s (Blackjack!) | Dealer up: %s. You win %s (returned %s).",
          fmtHandLong(H.phand), dUp, fmtMoney(win), fmtMoney(pay)), player)
        whisper(string.format("Paying %s to you. Please open a trade to receive.", fmtMoney(pay)), player)
        settle(player, "blackjack", pay)
      else
        whisper(string.format("Your hand: %s (%d). Dealer shows: %s. Whisper: hit / stand%s.",
          fmtHandLong(H.phand), pTotal, dUp,
          ((not H.doubled and #H.phand==2) and " / double" or "")), player)
      end
    end)

    PendingRoll[player] = nil

  elseif st.stage == "hit" then
    table.insert(H.phand, card)
    local total, soft = handValue(H.phand)
    whisper(string.format("You draw: %s. Hand: %s (%d%s).",
      fmtCard(card), fmtHandLong(H.phand), total, soft and " soft" or ""), player)
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
    if total > 21 then
      whisper(string.format("Busted at %d. Dealer wins.", total), player)
      tradeReset(); settle(player, "dealer", 0)
    else
      whisper("Whisper: hit / stand"..((not H.doubled and #H.phand==2) and " / double" or ""), player)
    end
    PendingRoll[player] = nil

  elseif st.stage == "double" then
    table.insert(H.phand, card)
    local pTotal = ({handValue(H.phand)})[1]
    whisper(string.format("Double down draw: %s. Hand now %s (%d).",
      fmtCard(card), fmtHandLong(H.phand), pTotal), player)
    PendingRoll[player] = nil
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end

    -- Dealer plays via /roll until stand, then resolve
    dealerPlayAsync(H, function(dTotal)
      whisperDealerReveal(player, H)
      local pt = ({handValue(H.phand)})[1]
      if pt > 21 then
        whisper("Busted. Dealer wins.", player)
        tradeReset(); settle(player, "dealer", 0)
      else
        if dTotal > 21 or pt > dTotal then
          local ret = H.bet * 2
          Trade.mode = "payout"; Trade.amount = ret; if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
          whisper(string.format("You win %s. Returned %s.", fmtMoney(H.bet), fmtMoney(ret)), player)
          whisper(string.format("Paying %s to you. Please open a trade to receive.", fmtMoney(ret)), player)
          settle(player, "player", ret)
        elseif dTotal > pt then
          whisper("Dealer wins.", player)
          tradeReset(); settle(player, "dealer", 0)
        else
          local ret = H.bet
          Trade.mode = "payout"; Trade.amount = ret; if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
          whisper(string.format("Push. Returned %s.", fmtMoney(ret)), player)
          whisper(string.format("Paying %s to you. Please open a trade to receive.", fmtMoney(ret)), player)
          settle(player, "push", ret)
        end
      end
    end)
  end

  return true
end

-- Parse system roll line (English): "<Name> rolls X (min-max)"
local function onChatMsgSystem(msg)
  if not msg then return end
  local name, val, low, high = msg:match("([^%s]+)%s+rolls%s+(%d+)%s+%((%d+)%-(%d+)%)$")
  if not name then return end
  name = Ambiguate and Ambiguate(name, "none") or name

  local handled = false

  -- Player roll handling
  local st = PendingRoll[name]
  if st and st.expect and tonumber(low) == st.min and tonumber(high) == st.max then
    takePlayerRoll(name, tonumber(val))
    handled = true
  end

  -- Dealer roll handling (our own name)
  if name == myName() and PendingDealerRoll.expect and tonumber(low) == PendingDealerRoll.min and tonumber(high) == PendingDealerRoll.max then
    local n = tonumber(val) or 1
    local H = PendingDealerRoll.hand
    if H then
      table.insert(H.dhand, addSuit(rankFromRoll(n)))
      -- no emotes for intermediate dealer cards per request
    end
    PendingDealerRoll.expect = false
    local cb = PendingDealerRoll.cb
    PendingDealerRoll.cb = nil
    if cb then cb() end
    handled = true
  end

  return handled
end

-- ===================== Round + Actions =====================
local function startHand(player, bet_c)
  DB.session.staked = DB.session.staked + bet_c
  DB.session.rounds = DB.session.rounds + 1
  local H = handFor(player)
  H.bet = bet_c
  H.original = bet_c
  H.phand, H.dhand = {}, {}
  H.doubled = false
  H.state = "awaiting-rolls"
  CurrentPlayerName = player

  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
  askPlayerToRoll(player, "Roll for your first card.", "deal1", 1, 13)
end

local function resolveAndQueuePayout(player)
  local H = handFor(player)
  dealerPlayAsync(H, function(dTotal)
    whisperDealerReveal(player, H) -- will emote final hands
    local pTotal = ({handValue(H.phand)})[1]
    if dTotal > 21 or pTotal > dTotal then
      local ret = H.bet * 2
      Trade.mode = "payout"; Trade.amount = ret; if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
      whisper(string.format("You win %s. Returned %s.", fmtMoney(H.bet), fmtMoney(ret)), player)
      whisper(string.format("Paying %s to you. Please open a trade to receive.", fmtMoney(ret)), player)
      settle(player, "player", ret)
    elseif dTotal > pTotal then
      whisper("Dealer wins.", player)
      tradeReset(); settle(player, "dealer", 0)
    else
      local ret = H.bet
      Trade.mode = "payout"; Trade.amount = ret; if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
      whisper(string.format("Push. Returned %s.", fmtMoney(ret)), player)
      whisper(string.format("Paying %s to you. Please open a trade to receive.", fmtMoney(ret)), player)
      settle(player, "push", ret)
    end
  end)
end

local function doHit(player)
  local H = handFor(player)
  if H.state ~= "player" and H.state ~= "awaiting-rolls" then
    whisper("No active hand. Open a trade with 50g–1000g to start.", player); return
  end
  askPlayerToRoll(player, "Roll for your hit card.", "hit", 1, 13)
end

local function doStand(player)
  local H = handFor(player)
  if H.state == "awaiting-rolls" then
    whisper("Finish your initial card rolls first.", player); return
  end
  if H.state ~= "player" then whisper("No active hand.", player); return end
  if not H.dhand or #H.dhand == 0 then
    dealerInitialUpcard(H, function() resolveAndQueuePayout(player) end)
  else
    resolveAndQueuePayout(player)
  end
end

local function doDouble(player)
  local H = handFor(player)
  if H.state ~= "player" or #H.phand ~= 2 or H.doubled then
    whisper("You can only double on your first decision (2-card hand) and only once.", player)
    return
  end
  Trade.name = player; Trade.mode = "double"; Trade.amount = H.original
  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
  whisper(string.format("To double, open a trade and add %s exactly, then both accept.", fmtMoney(H.original)), player)
end

-- ===================== Whisper handler =====================
local function handleWhisper(rawMsg, rawPlayer)
  local player = Ambiguate and Ambiguate(rawPlayer, "none") or rawPlayer
  local msg = tostring(rawMsg or ""):gsub("^%s+",""):gsub("%s+$","")
  local lower = msg:lower()

  ensurePlayer(player)

  if lower == "join" then
    whisper("Welcome to Blackjack! To play: open a trade with 50g–1000g. Then use: hit / stand / double. You will /roll 1–13 for your cards.", player)
    return
  end
  if lower == "help" then
    whisper("Commands: join, balance, daily, hit, stand, double, stats, leaderboard.", player)
    return
  end
  if lower == "balance" or lower == "gold" then
    local P = ensurePlayer(player); whisper(string.format("You have %s.", fmtMoney(P.copper)), player); return
  end
  if lower == "daily" then
    local P = ensurePlayer(player); local t = today()
    if P.lastDaily == t then whisper("You've already claimed today's bonus.", player)
    else P.lastDaily = t; P.copper = (P.copper or 0) + DAILY_BONUS_C; whisper(string.format("Daily bonus: +%s. You now have %s.", fmtMoney(DAILY_BONUS_C), fmtMoney(P.copper)), player) end
    return
  end

  if lower == "hit" then doHit(player); return end
  if lower == "stand" then doStand(player); return end
  if lower == "double" or lower == "double down" then doDouble(player); return end

  if lower == "stats" then
    local S = ensurePStats(player)
    whisper(string.format("Rounds: %d | W:%d L:%d P:%d | BJs:%d | Net:%s",
      S.rounds, S.wins, S.losses, S.pushes, S.bj or 0, fmtMoney(S.net)), player)
    return
  end

  if lower == "leaderboard" then
    local top = {}
    for name, rec in pairs(DB.leaderboard or {}) do
      if rec and (rec.profit or 0) > 0 then
        top[#top+1] = { name = name, profit = rec.profit, t = rec.lastWin or 0 }
      end
    end
    table.sort(top, function(a,b) if a.profit == b.profit then return a.t > b.t end return a.profit > b.profit end)
    local lines = {}
    for i=1, math.min(5, #top) do
      lines[#lines+1] = string.format("%d) %s — %s", i, top[i].name, fmtMoney(top[i].profit))
    end
    whisper(#lines>0 and table.concat(lines, "  ") or "No winners yet.", player)
    return
  end
end

-- ===================== Trade helpers/events =====================
local function currentTargetMoney()
  if GetTargetTradeMoney then
    local v = GetTargetTradeMoney() or 0
    return tonumber(v) or 0
  end
  return 0
end
local function currentPlayerMoney()
  if GetPlayerTradeMoney then
    local v = GetPlayerTradeMoney() or 0
    return tonumber(v) or 0
  end
  return 0
end

local function bothAccepted(pAcc, tAcc)
  local function isYes(v)
    if v == true then return true end
    local n = tonumber(v)
    if n and n == 1 then return true end
    if type(v) == "string" then
      v = v:upper()
      if v == "READY_FOR_TRADE" or v == "ACCEPTED" then return true end
    end
    return false
  end
  return isYes(pAcc) and isYes(tAcc)
end

local function onTradeShow()
  Trade.name = readTradePartnerFromUI()
  Trade.amount = 0
  if Trade.mode == nil then Trade.mode = "bet" end
  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end

  if Trade.name then
    if Trade.mode == "double" then
      local H = handFor(Trade.name)
      whisper(string.format("To double, add %s exactly, then both accept.", fmtMoney(H.original or 0)), Trade.name)
    elseif Trade.mode == "payout" then
      whisper("Paying your winnings—please accept once you see the amount on my side.", Trade.name)
    else
      whisper(string.format("Place your stake (between %s and %s), then both accept.",
        fmtMoney(MIN_BET_C), fmtMoney(MAX_BET_C)), Trade.name)
    end
  end
end

local function onTradeMoneyChanged()
  Trade.amount = currentTargetMoney()
  if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
end

local function onTradeAcceptUpdate(playerAccepted, targetAccepted)
  if not bothAccepted(playerAccepted, targetAccepted) then return end

  Trade.name = readTradePartnerFromUI() or Trade.name
  local name = Trade.name; if not name then return end
  local H = handFor(name)

  local mode = Trade.mode or "bet"

  local amountAtAccept
  if mode == "payout" then
    amountAtAccept = math.max(Trade.amount or 0, currentPlayerMoney())
  else
    amountAtAccept = math.max(Trade.amount or 0, currentTargetMoney())
  end

  if mode == "bet" then
    if amountAtAccept <= 0 then
      whisper("Bet not detected. Please add 50g–1000g and accept again.", name)
      return
    end
    if amountAtAccept < MIN_BET_C or amountAtAccept > MAX_BET_C then
      whisper(string.format("Bet must be between %s and %s.", fmtMoney(MIN_BET_C), fmtMoney(MAX_BET_C)), name)
      return
    end
    emote(string.format("accepts a bet of %s from %s.", fmtMoney(amountAtAccept), name))
    whisper(string.format("Bet of %s accepted. We’ll use /roll 1–13 to draw cards.", fmtMoney(amountAtAccept)), name)
    DB.session.staked = DB.session.staked + amountAtAccept
    DB.session.rounds = DB.session.rounds + 1
    H.bet = amountAtAccept; H.original = amountAtAccept; H.phand = {}; H.dhand = {}; H.doubled=false; H.state="awaiting-rolls"
    CurrentPlayerName = name
    tradeReset()
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
    askPlayerToRoll(name, "Roll for your first card.", "deal1", 1, 13)

  elseif mode == "double" then
    if H.state ~= "player" or #H.phand ~= 2 or H.doubled then
      whisper("Double not available now (must be first decision on a 2-card hand).", name)
      tradeReset()
      return
    end
    if amountAtAccept ~= (H.original or 0) then
      whisper(string.format("Double must be exactly %s.", fmtMoney(H.original or 0)), name)
      return
    end
    whisper(string.format("Double of %s accepted. Roll one card (1–13).", fmtMoney(amountAtAccept)), name)
    tradeReset()
    H.doubled = true
    H.bet = (H.original or 0) * 2
    H.state = "player"
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
    askPlayerToRoll(name, "Roll one card for your double.", "double", 1, 13)

  elseif mode == "payout" then
    DB.session.lastPayout = amountAtAccept
    whisper("Winnings delivered. You can bet again any time.", name)
    tradeReset()
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
  end
end

local function onTradeClosed() end

-- ===================== Rules window & UI helpers =====================
BlackjackHost = BlackjackHost or {}

local function Fill(parent, layer, color, a, b, c, d, h)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(TEX_WHITE)
  t:SetVertexColor(color[1], color[2], color[3], color[4])
  if a then t:SetPoint("TOPLEFT", a, b) t:SetPoint("BOTTOMRIGHT", c, d)
  else t:SetAllPoints(true) end
  if h then t:SetHeight(h) end
  return t
end

local function Border(frame)
  local l = frame:CreateTexture(nil, "BORDER"); l:SetTexture(TEX_WHITE); l:SetVertexColor(unpack(COLOR.line)); l:SetPoint("TOPLEFT", 0, 0); l:SetPoint("BOTTOMLEFT", 0, 0); l:SetWidth(1)
  local r = frame:CreateTexture(nil, "BORDER"); r:SetTexture(TEX_WHITE); r:SetVertexColor(unpack(COLOR.line)); r:SetPoint("TOPRIGHT", 0, 0); r:SetPoint("BOTTOMRIGHT", 0, 0); r:SetWidth(1)
  local t = frame:CreateTexture(nil, "BORDER"); t:SetTexture(TEX_WHITE); t:SetVertexColor(unpack(COLOR.line)); t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", 0, 0); t:SetHeight(1)
  local b = frame:CreateTexture(nil, "BORDER"); b:SetTexture(TEX_WHITE); b:SetVertexColor(unpack(COLOR.line)); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(1)
  return {l=l,r=r,t=t,b=b}
end

local function MakeButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 22)
  Fill(b, "BACKGROUND", COLOR.btn)
  local hl = Fill(b, "HIGHLIGHT", COLOR.btnHL); hl:Hide()
  local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  txt:SetPoint("CENTER", 0, 0)
  txt:SetTextColor(unpack(COLOR.text))
  txt:SetText(text)
  b:SetScript("OnEnter", function() hl:Show() end)
  b:SetScript("OnLeave", function() hl:Hide() end)
  b.textFS = txt
  Border(b)
  return b
end

local function BuildRulesText()
  local function fmtMoneyLocal(c) return fmtMoney(c) end
  local betRange = fmtMoneyLocal(MIN_BET_C) .. " – " .. fmtMoneyLocal(MAX_BET_C)
  local bjPay = BJ_PAY_NUM .. ":" .. BJ_PAY_DEN
  local soft17 = DEALER_STANDS_SOFT_17 and "Dealer stands on soft 17." or "Dealer hits soft 17."
  local t = {}
  t[#t+1] = "|cffffd100Blackjack — Rules & Commands|r"
  t[#t+1] = ""
  t[#t+1] = "|cffffd100Gameplay|r"
  t[#t+1] = "- Trade-first: player opens a trade with their stake ("..betRange..")."
  t[#t+1] = "- Cards are drawn by player /roll 1–13 (1=A, 11=J, 12=Q, 13=K)."
  t[#t+1] = "- |cffffd100ENHC|r: Dealer shows only |cffffd100one upcard|r initially via /roll 1–13. The hole and further hits are rolled during dealer play after the player stands/doubles."
  t[#t+1] = "- Suits are randomized for display."
  t[#t+1] = "- Blackjack pays "..bjPay..". "..soft17
  t[#t+1] = "- Push returns the original bet."
  t[#t+1] = "- Double: only on your first decision with 2 cards; adds another stake equal to original; one extra card then stand."
  t[#t+1] = "- Insurance: |cffff3333Disabled|r under ENHC (no hole to peek)."
  t[#t+1] = "- Whisper-only game; all prompts and confirmations are sent via whisper."
  t[#t+1] = ""
  t[#t+1] = "|cffffd100Resets & Tracking|r"
  t[#t+1] = "- Host Net resets daily at 10:00 CST; Weekly Host Net and Leaderboard reset Tuesday 10:00 CST."
  t[#t+1] = "- \"Last Payout\" shows the most recent amount paid via trade."
  t[#t+1] = ""
  t[#t+1] = "|cffffd100Player Commands (whisper to dealer)|r"
  t[#t+1] = "- join | help"
  t[#t+1] = "- balance | gold"
  t[#t+1] = "- daily"
  t[#t+1] = "- hit | stand | double"
  t[#t+1] = "- stats | leaderboard"
  t[#t+1] = ""
  t[#t+1] = "|cffffd100Dealer Panel Buttons|r"
  t[#t+1] = "- Open Trade, Say Paying, Force Reveal, Reset Round, Rules"
  t[#t+1] = ""
  t[#t+1] = "|cffffd100Emotes|r"
  t[#t+1] = "- Only: Bet accepted, Final hands, Result amount (win/loss). Wrapped in {rt3} purple diamond."
  return table.concat(t, "\n")
end

local function CreateRulesUI()
  if BlackjackHost.rulesFrame then return end

  local f = CreateFrame("Frame", "BlackjackRulesFrame", UIParent)
  f:SetSize(620, 420)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  Fill(f, "BACKGROUND", COLOR.bg); Border(f)

  local header = f:CreateTexture(nil, "ARTWORK"); header:SetTexture(TEX_WHITE)
  header:SetVertexColor(unpack(COLOR.header))
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(26)
  local headerLine = f:CreateTexture(nil, "ARTWORK"); headerLine:SetTexture(TEX_WHITE)
  headerLine:SetVertexColor(unpack(COLOR.accent))
  headerLine:SetPoint("TOPLEFT", 1, -27); headerLine:SetPoint("TOPRIGHT", -1, -27); headerLine:SetHeight(1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("LEFT", f, "TOPLEFT", 10, -14)
  title:SetTextColor(unpack(COLOR.text))
  title:SetText("Blackjack — Rules")

  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 10, -38)
  body:SetPoint("BOTTOMRIGHT", -10, 40)
  Fill(body, "BACKGROUND", COLOR.panel); Border(body)

  local scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(560, 1)
  scroll:SetScrollChild(content)

  local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", 0, 0)
  text:SetWidth(560)
  text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
  text:SetText(BuildRulesText())
  content:SetHeight(2000)

  local closeBtn = MakeButton(f, "Close", 90, 22)
  closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  BlackjackHost.rulesFrame = f
end

function BlackjackHost.ToggleRules()
  if not BlackjackHost.rulesFrame then CreateRulesUI() end
  if BlackjackHost.rulesFrame:IsShown() then
    BlackjackHost.rulesFrame:Hide()
  else
    local sf = BlackjackHost.rulesFrame
    sf:Hide(); BlackjackHost.rulesFrame = nil; CreateRulesUI(); sf = BlackjackHost.rulesFrame
    sf:Show()
  end
end

-- ===================== Dealer GUI (TSM-style, compact + RESIZABLE) =====================
local function CreateHostUI()
  if BlackjackHost.frame then return end

  local f = CreateFrame("Frame", "BlackjackHostFrame", UIParent)
  f:SetSize(620, 420)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Make resizable (Classic-safe)
  f:SetResizable(true)
  local MIN_W, MIN_H, MAX_W, MAX_H = 560, 410, 1200, 900
  if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end

  Fill(f, "BACKGROUND", COLOR.bg)
  Border(f)

  local header = f:CreateTexture(nil, "ARTWORK"); header:SetTexture(TEX_WHITE)
  header:SetVertexColor(unpack(COLOR.header))
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(26)
  local headerLine = f:CreateTexture(nil, "ARTWORK"); headerLine:SetTexture(TEX_WHITE)
  headerLine:SetVertexColor(unpack(COLOR.accent))
  headerLine:SetPoint("TOPLEFT", 1, -27); headerLine:SetPoint("TOPRIGHT", -1, -27); headerLine:SetHeight(1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("LEFT", f, "TOPLEFT", 10, -14)
  title:SetTextColor(unpack(COLOR.text))
  title:SetText("Blackjack — Host Panel")

  -- Left info grid (compacted)
  local left = CreateFrame("Frame", nil, f)
  left:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -38)
  Fill(left, "BACKGROUND", COLOR.panel); Border(left)

  local function addRow(container, idx, label)
    local y = -8 - (idx-1)*20
    local l = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 10, y)
    l:SetTextColor(unpack(COLOR.subtext))
    l:SetText(label)
    local v = container:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    v:SetPoint("LEFT", l, "RIGHT", 8, 0)
    v:SetTextColor(unpack(COLOR.text))
    v:SetText("-")
    return v
  end

  local partnerFS   = addRow(left, 1, "Partner:")
  local modeFS      = addRow(left, 2, "Mode:")
  local stakeFS     = addRow(left, 3, "Stake:")
  local payoutFS    = addRow(left, 4, "Next Payout:")
  local lastPayFS   = addRow(left, 5, "Last Payout:")
  local hostnetFS   = addRow(left, 6, "Host Net (Today):")
  local hostnetWFS  = addRow(left, 7, "Host Net (Week):")

  -- Right leaderboard (compacted)
  local right = CreateFrame("Frame", nil, f)
  right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -38)
  Fill(right, "BACKGROUND", COLOR.panel); Border(right)

  local lbTitle = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lbTitle:SetPoint("TOPLEFT", 10, -8)
  lbTitle:SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], COLOR.accent[4])
  lbTitle:SetText("Top Players — Weekly")

  local line = right:CreateTexture(nil, "ARTWORK"); line:SetTexture(TEX_WHITE)
  line:SetVertexColor(unpack(COLOR.line))
  line:SetPoint("TOPLEFT", 10, -24); line:SetPoint("TOPRIGHT", -10, -24); line:SetHeight(1)

  local lb1 = right:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  lb1:SetPoint("TOPLEFT", 10, -32); lb1:SetTextColor(unpack(COLOR.text)); lb1:SetText("-")
  local lb2 = right:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  lb2:SetPoint("TOPLEFT", 10, -52); lb2:SetTextColor(unpack(COLOR.text)); lb2:SetText("-")
  local lb3 = right:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  lb3:SetPoint("TOPLEFT", 10, -72); lb3:SetTextColor(unpack(COLOR.text)); lb3:SetText("-")

  -- Hands panels (compacted)
  local pBox = CreateFrame("Frame", nil, f)
  Fill(pBox, "BACKGROUND", COLOR.panel); Border(pBox)
  local pLbl = pBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); pLbl:SetPoint("TOPLEFT", 10, -6)
  pLbl:SetTextColor(unpack(COLOR.subtext)); pLbl:SetText("Player Hand")
  local pFS = pBox:CreateFontString(nil, "OVERLAY", "GameFontWhite"); pFS:SetPoint("TOPLEFT", 10, -24)
  pFS:SetTextColor(unpack(COLOR.text)); pFS:SetJustifyH("LEFT"); pFS:SetText("-")

  local dBox = CreateFrame("Frame", nil, f)
  Fill(dBox, "BACKGROUND", COLOR.panel); Border(dBox)
  local dLbl = dBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); dLbl:SetPoint("TOPLEFT", 10, -6)
  dLbl:SetTextColor(unpack(COLOR.subtext)); dLbl:SetText("Dealer Hand")
  local dFS = dBox:CreateFontString(nil, "OVERLAY", "GameFontWhite"); dFS:SetPoint("TOPLEFT", 10, -24)
  dFS:SetTextColor(unpack(COLOR.text)); dFS:SetJustifyH("LEFT"); dFS:SetText("-")

  -- Footer status & sig
  local statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusFS:SetPoint("BOTTOMLEFT", 12, 8); statusFS:SetTextColor(unpack(COLOR.subtext))
  statusFS:SetText("Ready.")
  local sigFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sigFS:SetPoint("BOTTOMRIGHT", -12, 8); sigFS:SetTextColor(unpack(COLOR.subtext))
  sigFS:SetText("Made by Brewer - jbrewer. on Discord")

  -- Buttons
  local btnW, pad = 100, 8
  local resetBtn = MakeButton(f, "Reset Round", btnW, 22); resetBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 34)
  local revealBtn = MakeButton(f, "Force Reveal", btnW, 22); revealBtn:SetPoint("RIGHT", resetBtn, "LEFT", -pad, 0)
  local sayPayBtn = MakeButton(f, "Say Paying", btnW, 22);  sayPayBtn:SetPoint("RIGHT", revealBtn, "LEFT", -pad, 0)
  local tradeBtn  = MakeButton(f, "Open Trade", btnW, 22);  tradeBtn:SetPoint("RIGHT", sayPayBtn, "LEFT", -pad, 0)
  local rulesBtn  = MakeButton(f, "Rules", btnW, 22);       rulesBtn:SetPoint("RIGHT", tradeBtn, "LEFT", -pad, 0)

  resetBtn:SetScript("OnClick", function()
    local p = CurrentPlayerName or Trade.name
    if p and PendingRoll[p] then PendingRoll[p] = nil end
    PendingDealerRoll.expect = false; PendingDealerRoll.cb = nil; PendingDealerRoll.hand = nil
    tradeReset()
    if p then whisper("Round reset. Ready for next bet.", p) end
    if BlackjackHost and BlackjackHost.SetStatus then BlackjackHost.SetStatus("Round reset.") end
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
  end)
  revealBtn:SetScript("OnClick", function()
    local p = CurrentPlayerName
    if not p then if BlackjackHost.SetStatus then BlackjackHost.SetStatus("No active round.") end; return end
    local H = DB.hands[p]; if not H then if BlackjackHost.SetStatus then BlackjackHost.SetStatus("No active hand.") end; return end
    dealerPlayAsync(H, function()
      whisperDealerReveal(p, H)
      if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
      if BlackjackHost.SetStatus then BlackjackHost.SetStatus("Dealer revealed.") end
    end)
  end)
  sayPayBtn:SetScript("OnClick", function()
    if Trade.name and Trade.mode == "payout" and Trade.amount and Trade.amount > 0 then
      whisper(string.format("Paying %s to you. Please open a trade to receive.", fmtMoney(Trade.amount)), Trade.name)
      if BlackjackHost.SetStatus then BlackjackHost.SetStatus("Pay message sent.") end
    else
      if BlackjackHost.SetStatus then BlackjackHost.SetStatus("No payout queued.") end
    end
  end)
  tradeBtn:SetScript("OnClick", function()
    local n = CurrentPlayerName or Trade.name
    if not n then if BlackjackHost.SetStatus then BlackjackHost.SetStatus("No partner to trade.") end; return end
    if TargetByName then TargetByName(n, true) end
    if UnitExists("target") and UnitIsPlayer("target") and UnitName("target") == n and InitiateTrade then
      InitiateTrade("target"); if BlackjackHost.SetStatus then BlackjackHost.SetStatus("Trade opened.") end
    else
      if BlackjackHost.SetStatus then BlackjackHost.SetStatus("Could not target/trade.") end
    end
  end)
  rulesBtn:SetScript("OnClick", function()
    if BlackjackHost.ToggleRules then BlackjackHost.ToggleRules() end
  end)

  -- ===== Size grip (bottom-right) =====
  local sizer = CreateFrame("Button", nil, f)
  sizer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  sizer:SetSize(16, 16)
  sizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  sizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  sizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  sizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  sizer:SetScript("OnMouseUp",   function() f:StopMovingOrSizing(); if BlackjackHost.Relayout then BlackjackHost.Relayout() end end)

  -- Store refs
  BlackjackHost.frame       = f
  BlackjackHost.partner     = partnerFS
  BlackjackHost.mode        = modeFS
  BlackjackHost.stake       = stakeFS
  BlackjackHost.payout      = payoutFS
  BlackjackHost.lastpayout  = lastPayFS
  BlackjackHost.hostnet     = hostnetFS
  BlackjackHost.hostnetWeek = hostnetWFS
  BlackjackHost.playerFS    = pFS
  BlackjackHost.dealerFS    = dFS
  BlackjackHost.statusFS    = statusFS
  BlackjackHost.SetStatus   = function(text) if BlackjackHost.statusFS then BlackjackHost.statusFS:SetText(text or "") end end

  -- ---------- Responsive layout ----------
  local TOP_OFFSET = 38
  local TOP_H      = 160
  local HAND_H     = 68
  local GAP        = 10
  local LR_GAP     = 10
  local MARGIN     = 10

  BlackjackHost.Relayout = function()
    local W = f:GetWidth()
    local contentW = W - (MARGIN*2)
    local leftW  = math.max(280, math.floor((contentW - LR_GAP) * 0.56))
    local rightW = math.max(220, contentW - LR_GAP - leftW)

    left:SetSize(leftW, TOP_H)
    right:SetSize(rightW, TOP_H)

    local pTop = -(TOP_OFFSET + TOP_H + GAP)
    pBox:ClearAllPoints(); pBox:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, pTop)
    pBox:SetSize(contentW, HAND_H)

    local dTop = pTop - (HAND_H + GAP)
    dBox:ClearAllPoints(); dBox:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, dTop)
    dBox:SetSize(contentW, HAND_H)

    local innerW = contentW - 20
    if innerW > 0 then
      pFS:SetWidth(innerW)
      dFS:SetWidth(innerW)
    end
  end

  f:SetScript("OnSizeChanged", function(self, w, h)
    local MIN_W, MIN_H, MAX_W, MAX_H = 560, 410, 1200, 900
    local cw = math.max(MIN_W, math.min(MAX_W, w or self:GetWidth()))
    local ch = math.max(MIN_H, math.min(MAX_H, h or self:GetHeight()))
    if cw ~= (w or cw) or ch ~= (h or ch) then
      self:SetSize(cw, ch)
      return
    end
    if BlackjackHost.Relayout then BlackjackHost.Relayout() end
  end)

  BlackjackHost.Relayout()

  local function uiHandText(name)
    if not name then return "-", "-" end
    local H = DB and DB.hands and DB.hands[name]
    if not H then return "-", "-" end
    local pt = ({handValue(H.phand)})[1] or 0
    local ptxt = (#H.phand > 0) and (fmtHandLong(H.phand, false).."  ("..pt..")") or "-"
    local dtxt
    if not H.dhand or #H.dhand == 0 then
      dtxt = "-"
    else
      if H.state == "player" or H.state == "awaiting-rolls" or H.state == "awaiting-dealer-up" then
        dtxt = fmtHandLong({H.dhand[1]}, true)
      else
        local dt = ({handValue(H.dhand)})[1] or 0
        dtxt = fmtHandLong(H.dhand, false).."  ("..dt..")"
      end
    end
    return ptxt, dtxt
  end

  local function setLBLine(fs, rec)
    if not fs then return end
    if not rec then fs:SetText("-"); return end
    fs:SetText(string.format("%s — %s", rec.name, fmtMoney(rec.profit)))
  end

  BlackjackHost.Update = function()
    maybeResetHostNet()
    maybeResetLeaderboardWeekly()
    if not BlackjackHost.frame then return end

    local activeName = CurrentPlayerName or Trade.name
    local activeHand = activeName and DB.hands and DB.hands[activeName] or nil

    local modeText
    if CurrentPlayerName then
      if activeHand and activeHand.doubled then modeText = "playing (doubled)"
      elseif activeHand and activeHand.state == "awaiting-dealer-up" then modeText = "dealing (dealer upcard)"
      else modeText = "playing" end
    else
      modeText = Trade.mode or "-"
    end

    local stakeCopper = nil
    if activeHand and (activeHand.bet or 0) > 0 then
      stakeCopper = activeHand.bet
    elseif Trade.mode == "bet" or Trade.mode == "double" then
      stakeCopper = Trade.amount
    end

    BlackjackHost.partner:SetText(activeName or "-")
    BlackjackHost.mode:SetText(modeText or "-")
    BlackjackHost.stake:SetText(stakeCopper and stakeCopper > 0 and fmtMoney(stakeCopper) or "-")

    if Trade.mode == "payout" and (Trade.amount or 0) > 0 then
      BlackjackHost.payout:SetText("|cff00ff00"..fmtMoney(Trade.amount or 0).."|r")
    else
      BlackjackHost.payout:SetText("-")
    end

    local lp = DB and DB.session and DB.session.lastPayout or 0
    BlackjackHost.lastpayout:SetText((lp or 0) > 0 and fmtMoney(lp) or "-")

    local net = DB and DB.wins and DB.wins.hostNet or 0
    local netW = DB and DB.wins and DB.wins.weekHostNet or 0
    local color = net >= 0 and COLOR.good or COLOR.bad
    local colorW = netW >= 0 and COLOR.good or COLOR.bad
    BlackjackHost.hostnet:SetText(string.format("|cff%02x%02x%02x%s|r",
      math.floor(color[1]*255), math.floor(color[2]*255), math.floor(color[3]*255),
      fmtMoney(math.abs(net))
    ))
    BlackjackHost.hostnetWeek:SetText(string.format("|cff%02x%02x%02x%s|r",
      math.floor(colorW[1]*255), math.floor(colorW[2]*255), math.floor(colorW[3]*255),
      fmtMoney(math.abs(netW))
    ))

    local ptxt, dtxt = uiHandText(activeName)
    BlackjackHost.playerFS:SetText(ptxt)
    BlackjackHost.dealerFS:SetText(dtxt)

    local arr = {}
    for name, rec in pairs(DB.leaderboard or {}) do
      if rec and (rec.profit or 0) > 0 then
        arr[#arr+1] = { name = name, profit = rec.profit, t = rec.lastWin or 0 }
      end
    end
    table.sort(arr, function(a,b) if a.profit == b.profit then return a.t > b.t end return a.profit > b.profit end)
    setLBLine(lb1, arr[1]); setLBLine(lb2, arr[2]); setLBLine(lb3, arr[3])
  end
end

-- ===================== Events =====================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("TRADE_MONEY_CHANGED")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("TRADE_CLOSED")
f:RegisterEvent("CHAT_MSG_SYSTEM")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...; if name == ADDON then ensureDB() end

  elseif event == "PLAYER_LOGIN" then
    ensureDB()
    checkSavedVariables()
    if math.random and type(math.randomseed) == "function" then
      local seed = (GetServerTime and GetServerTime() or time()) + (math.floor((GetTime() or 0) * 1000) % 100000)
      math.randomseed(seed); for i=1,5 do math.random() end
    end
    maybeResetHostNet()
    maybeResetLeaderboardWeekly()
    CreateHostUI()
    if BlackjackHost and BlackjackHost.Update then BlackjackHost.Update() end
    print("|cFFFFD700Blackjack|r loaded. ENHC dealer: one upcard via /roll; hole & hits roll during resolve. Trade 50g–1000g to start. Resizable compact TSM-style UI.")

  elseif event == "CHAT_MSG_WHISPER" then
    local msg, player = ...; handleWhisper(msg, player)

  elseif event == "TRADE_SHOW" then
    onTradeShow()

  elseif event == "TRADE_MONEY_CHANGED" then
    onTradeMoneyChanged()

  elseif event == "TRADE_ACCEPT_UPDATE" then
    local pAcc, tAcc = ...
    onTradeAcceptUpdate(pAcc, tAcc)

  elseif event == "TRADE_CLOSED" then
    -- no-op

  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = ...
    onChatMsgSystem(msg)
  end
end)
