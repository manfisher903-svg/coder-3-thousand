# Steal a Soul 👻 (Roblox)

A complete design, economy, monetization plan, and **drop-in Luau codebase** for a "steal → hatch → upgrade → steal better" Roblox game, built on the loop behind *Steal a Brainrot* and *Steal an Egg*.

> Steal glowing Soul Orbs from guarded biomes (and from other players' bases), outrun the guardians, hatch them into Spirit Pets that print Essence, train Speed to reach deeper biomes, and rebirth for permanent multipliers.

## Documents (read in order)

| # | Doc | What's inside |
|---|---|---|
| 1 | [Game Design](docs/01-game-design.md) | Core loop, 8 biomes + guardians, rarities, mutations, rebirth, day/night, base defenses, all stats |
| 2 | [Economy](docs/02-economy.md) | Starting numbers, income formulas, every upgrade cost, rebirth table, simulated pacing |
| 3 | [Monetization](docs/03-monetization.md) | 10 Game Passes, 16 Developer Products, pricing ladder, revenue model, compliance |
| 4 | [Code Architecture](docs/04-code-architecture.md) | Services, data/session locking, receipts, remotes, trust boundaries |
| 5 | [Build Guide](docs/05-build-guide.md) | Exact Studio setup (Rojo or copy-paste), testing, map naming, 4-week schedule |
| 6 | [Marketing & Launch](docs/06-marketing-launch.md) | Icon/thumbnails, codes, influencer plan, 30-day update roadmap |
| 7 | [Polish & Anti-Exploit](docs/07-polish-and-anti-exploit.md) | VFX, sound design, anti-exploit priorities, retention polish |

## Quick start (about 10 minutes)

1. New **Baseplate** in Roblox Studio, then Game Settings → Security → *Enable Studio Access to API Services*; Max Players = 8.
2. `rojo serve` in this folder and connect the Rojo plugin, **or** copy the files by hand following [the build guide](docs/05-build-guide.md#option-b-manual-copy-paste-no-tools).
3. Press **Play**. A greybox map (8 bases plus 8 biomes), guardians, orbs, and the full HUD are generated automatically.
4. Fill in your Game Pass / Product IDs in `src/shared/Config/MonetizationConfig.luau`.

## What the code does

- **PlayerDataService**: DataStore with session locking, autosave, safe release, schema reconcile, Studio mock store
- **EconomyService**: 1 Hz income, multiplier stack, luck, timed boosts, offline earnings, friend/group/Premium bonuses
- **StealService**: carry weight slowdown, drops, delivery, stealing from bases, thief highlight, server-owned WalkSpeed
- **PetService**: pedestals, incubation timers, Ascension and mutation rolls, inventory (store/place/sell/vault)
- **BiomeService**: speed gates, luck-weighted orb spawning, rare-spawn announcements, dropped orbs
- **GuardianService**: patrol/chase/return AI with Slow Pulse and Blink abilities, night speed scaling
- **BaseService**: base assignment, lock/cooldown, Soul Shield, new-player protection, intruder push-out
- **UpgradeService / RebirthService**: Speed, Treadmill, Harness, Pedestals; rebirth with vault and perk shop
- **MonetizationService**: pass ownership + idempotent `ProcessReceipt` (save-before-ack) for 16 products
- **CodesService**, **DayNightService** (Soul Eclipse), **ToolService** (server-side bonk hits), **AntiExploitService**
- **Client**: entire HUD built in code (Upgrades, Spirits, Rebirth, Shop, Codes, Lock), toasts, banners, hatch pop-up

All tuning lives in `src/shared/Config/*`. Pacing can be re-simulated with `python3 tools/pacing_sim.py`.

## Verification

- Every `.luau` file compiles with the official `luau-compile`.
- `luau-lsp analyze` with the Roblox API definitions reports no errors.
- It has **not** been play-tested inside Roblox Studio from this repo. Run the Phase 2 checklist in the build guide on your first session.
