# 4. Code Architecture

About 7,000 lines of Luau, server-authoritative, with no external dependencies. All of it parses with `luau-compile` and passes `luau-lsp analyze` against the Roblox API definitions.

```
src/
├── shared/                      → ReplicatedStorage.Shared   (client + server)
│   ├── Config/
│   │   ├── GameConfig.luau        data store name, base/lock/PvP/day-night/anti-cheat tuning
│   │   ├── EconomyConfig.luau     every price & formula constant
│   │   ├── PetConfig.luau         rarities, mutations, ascension
│   │   ├── BiomeConfig.luau       biomes, guardians, 56 species names
│   │   ├── MonetizationConfig.luau pass/product IDs, prices, effect constants
│   │   ├── EventConfig.luau       seasonal event settings (Halloween: dates, candy, shop)
│   │   └── RewardConfig.luau      daily streak, playtime gifts, quest pool, index bonus
│   ├── Util/Format.luau           1.2K / 3.4M / 5.6B number + time formatting
│   ├── Util/Signal.luau           tiny in-process event
│   ├── Formulas.luau              all cost/income math (UI and server agree 100%)
│   ├── Remotes.luau               single list of every RemoteEvent/RemoteFunction
│   └── Types.luau                 saved-data shape (documentation types)
├── server/                      → ServerScriptService.Server
│   ├── Main.server.luau           bootstrap: Remotes → WorldBuilder → Init all → Start all
│   ├── Config/Codes.luau          promo codes (server-only so they can't be datamined)
│   ├── Util/RateLimiter.luau      per-player per-action cooldowns
│   ├── Util/Rewards.luau          one reward format for codes/daily/quests/gifts/shop
│   ├── World/WorldBuilder.luau    generates a greybox map if you have none yet
│   ├── World/ModelFactory.luau    orb/pet/guardian/tool visuals (auto-uses your art if present)
│   └── Services/
│       ├── PlayerDataService      DataStore + session locking + autosave + snapshots
│       ├── EconomyService         income tick, multipliers, luck, boosts, offline, friends
│       ├── StealService           carry/weight/drop/deliver/base-steal, WalkSpeed authority
│       ├── PetService             pedestals, incubation, hatch rolls, inventory actions
│       ├── BiomeService           zones, speed gates, orb spawning, dropped orbs
│       ├── GuardianService        chase AI (patrol/chase/return, SlowPulse, Blink)
│       ├── BaseService            base assignment, lock, shield, newbie protection
│       ├── UpgradeService         Speed / Treadmill / Harness / Pedestals
│       ├── RebirthService         rebirth reset, vault, perk shop
│       ├── MonetizationService    pass ownership, ProcessReceipt, product effects
│       ├── CodesService           redeem codes
│       ├── DayNightService        cycle, night & Eclipse modifiers
│       ├── ToolService            Soul Lantern / Reaper Scythe hit logic
│       ├── AntiExploitService     movement checks + the only safe Teleport()
│       ├── RewardService          daily streak, playtime gifts, daily quests
│       ├── EventService           seasonal event (Halloween): lighting, decor, candy, shop
│       └── LeaderboardService     global top-10 boards (OrderedDataStore)
└── client/                      → StarterPlayer.StarterPlayerScripts.Client
    └── Main.client.luau           builds the entire HUD in code + VFX bobbing
```

## 4.1 Service Pattern

Every service is a ModuleScript returning a table with `:Init(Services)` and `:Start()`.
`Main.server.luau` requires all of them, calls every `Init` (wires signals, no yielding), then every `Start` (loops, remote handlers). `PlayerDataService:Start()` runs **last** so every service is listening to `ProfileLoaded` before the first player loads. Services reach each other through the shared `Services` table, which avoids circular `require`s.

## 4.2 Data & Session Locking (PlayerDataService)

Record shape in the DataStore: `{ Data = <profile>, Lock = { JobId, Time } }`

1. **Join:** `UpdateAsync` claims the lock unless another live server holds it (a lock is stale after 300s, which handles crashed servers). Up to 5 retries 6s apart, then a friendly kick.
2. **Autosave** every 60s (staggered) refreshes the lock. If another server stole the lock, the save **aborts and the player is kicked**. That stops server-hop duplication.
3. **Leave / BindToClose:** sync cleanup handlers run, then a final save releases the lock.
4. **Same-server rejoin guard** waits for an in-flight final save before re-reading.
5. **Reconcile** fills new default fields into old saves (safe schema growth) plus a `migrate()` hook.
6. **Studio:** without API access it falls back to an in-memory store automatically.

## 4.3 Receipts (MonetizationService)

`ProcessReceipt` → player present and data loaded? → `PurchaseId` already processed? → run handler → record PurchaseId (last 100) → **save** → `PurchaseGranted` only if the save succeeded. Handlers never fail a paid purchase; if the effect can't apply, they give Essence compensation.

## 4.4 Remotes

| Remote | Type | Direction | Payload |
|---|---|---|---|
| Notify | Event | S→C | message, kind |
| StateChanged | Event | S→C | full snapshot (batched ≤4/s) |
| HatchResult | Event | S→C | species, rarity, mutation, income, ascended |
| Announce | Event | S→all | message, color |
| Knockback | Event | S→C | velocity (client owns its physics) |
| DropOrb | Event | C→S | none |
| GetState | Function | C→S | returns snapshot |
| RequestUpgrade | Function | C→S | kind, amount |
| RequestRebirth | Function | C→S | none |
| BuyPerk | Function | C→S | perkId |
| RedeemCode | Function | C→S | code |
| PetAction | Function | C→S | "Store"/"Place"/"Sell"/"Lock", args |
| RequestLock | Function | C→S | none |

High-frequency numbers (Essence, Income, Speed, Rebirths, CarryingRarity…) replicate as **Player attributes**. Cheap, and the UI just listens to `GetAttributeChangedSignal`.

## 4.5 Trust Boundaries

| Client may… | Server always… |
|---|---|
| Ask to upgrade / rebirth / redeem / move pets | validates type, ownership, cost, rate-limit |
| Trigger ProximityPrompts | re-checks distance, carry state, speed gate, base protection |
| Activate a tool | finds the victim itself (cone + range), applies cooldown |
| Move its character | owns WalkSpeed, checks displacement, rubber-bands speed hacks |
| Never | sends targets, amounts of currency, rarities, or positions that are trusted |

## 4.6 Extending

- **New biome:** add an entry in `BiomeConfig` (and `Order`), build the biome model with `Zone` + `SoulSpawns` (+ optional `GuardianSpawns`, `GateReturn`). Done.
- **New pass/product:** add it to `MonetizationConfig`, then add a handler in `ProductHandlers` or a check via `HasPass`.
- **New code:** add it to `server/Config/Codes.luau`.
- **Custom art:** drop models into `ReplicatedStorage.Assets.Pets.<Species>`, `Assets.Orbs.<Rarity>`, `ServerStorage.Guardians.<BiomeId>`, `ServerStorage.Tools.SoulLantern|ReaperScythe`. The factory picks them up automatically.
