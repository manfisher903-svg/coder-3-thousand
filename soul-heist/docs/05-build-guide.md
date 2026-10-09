# 5. Step-by-Step Build Guide

The code generates a **playable greybox world and the whole UI by itself**. Your first goal is "it runs in Studio" (about 30 minutes). After that, replace the greybox with real art at your own pace.

---

## Phase 0: Setup (10 min)

1. Open Roblox Studio → **New → Baseplate**. Save it to Roblox as **"Steal a Soul"**.
2. **Home → Game Settings**:
   - **Security** → turn ON *Enable Studio Access to API Services* (DataStores in Studio).
   - **Avatar** → Avatar type **R15**. Leave *Player Choice*.
   - **Places → (your place) → Server Fill** → **Max Players = 8** (one per base; must equal `GameConfig.MaxBases`).
3. **View** → open **Explorer**, **Properties**, **Output**.

## Phase 1: Get the code in

### Option A: Rojo (recommended, keeps files synced)
1. Install Rojo (`aftman add rojo-rbx/rojo` or the VS Code extension) plus the Rojo Studio plugin.
2. In this `soul-heist/` folder run `rojo serve`.
3. In Studio: Plugins → Rojo → **Connect**. Done; the tree below is created for you.

### Option B: Manual copy-paste (no tools)
Create **exactly** this tree. Names are case-sensitive. For each file, create the object type shown and paste the file's contents.

```
ReplicatedStorage
└── Shared                         (Folder)
    ├── Remotes                    (ModuleScript)  ← src/shared/Remotes.luau
    ├── Formulas                   (ModuleScript)  ← src/shared/Formulas.luau
    ├── Types                      (ModuleScript)  ← src/shared/Types.luau
    ├── Config                     (Folder)
    │   ├── GameConfig             (ModuleScript)
    │   ├── EconomyConfig          (ModuleScript)
    │   ├── PetConfig              (ModuleScript)
    │   ├── BiomeConfig            (ModuleScript)
    │   ├── MonetizationConfig     (ModuleScript)
    │   ├── EventConfig            (ModuleScript)
    │   ├── RewardConfig           (ModuleScript)
    │   └── AbilityConfig          (ModuleScript)
    └── Util                       (Folder)
        ├── Format                 (ModuleScript)
        └── Signal                 (ModuleScript)

ServerScriptService
└── Server                         (Folder)
    ├── Main                       (Script)        ← src/server/Main.server.luau
    ├── Config                     (Folder)
    │   └── Codes                  (ModuleScript)
    ├── Util                       (Folder)
    │   ├── RateLimiter            (ModuleScript)
    │   └── Rewards                (ModuleScript)
    ├── World                      (Folder)
    │   ├── WorldBuilder           (ModuleScript)
    │   └── ModelFactory           (ModuleScript)
    └── Services                   (Folder)
        ├── PlayerDataService      (ModuleScript)
        ├── AntiExploitService     (ModuleScript)
        ├── DayNightService        (ModuleScript)
        ├── MonetizationService    (ModuleScript)
        ├── EconomyService         (ModuleScript)
        ├── BaseService            (ModuleScript)
        ├── PetService             (ModuleScript)
        ├── BiomeService           (ModuleScript)
        ├── StealService           (ModuleScript)
        ├── GuardianService        (ModuleScript)
        ├── UpgradeService         (ModuleScript)
        ├── RebirthService         (ModuleScript)
        ├── CodesService           (ModuleScript)
        ├── ToolService            (ModuleScript)
        ├── EventService           (ModuleScript)
        ├── RewardService          (ModuleScript)
        ├── LeaderboardService     (ModuleScript)
        └── CompanionService       (ModuleScript)

StarterPlayer
└── StarterPlayerScripts
    └── Client                     (Folder)
        └── Main                   (LocalScript)   ← src/client/Main.client.luau
```

> Tip: Insert a ModuleScript, rename it, double-click, select all, paste. The `.server` / `.client` suffixes in file names only tell you to use a **Script** or **LocalScript**; don't include them in the object name.

**RemoteEvents / RemoteFunctions:** you do **not** create these by hand. `Remotes.Init()` creates `ReplicatedStorage.Remotes` with: `Notify, StateChanged, HatchResult, Announce, Knockback, DropOrb` (RemoteEvents) and `GetState, RequestUpgrade, RequestRebirth, BuyPerk, RedeemCode, PetAction, RequestLock, ClaimDaily, ClaimPlaytime, ClaimQuest, BuyEventItem` (RemoteFunctions).

**UI:** also created in code (`SoulHUD` ScreenGui): top bar, side menu (Event / Gifts / Upgrades / Spirits / Rebirth / Shop / Index / Codes / Lock Base), carry bar, toasts, banners, and the hatch pop-up.

## Phase 2: First play test (5 min)

1. Press **Play**. Output should show:
   `[WorldBuilder] Generated greybox world…` and `[SoulHeist] Server ready - 18 services running`.
2. You spawn in your base (row of 8 plots). Run **forward (+Z)** to the green **Whispering Meadow**.
3. Hold **E** on a glowing orb, run back, and walk into your plot. The orb lands on a pedestal and hatches in about 10s.
4. Open **Upgrades** and buy Speed to 22, then try **Ember Hollow**. Under-speed players get pushed back at the gate.
5. Multiplayer test: **Test → Clients and Servers → 2 players → Start**. Steal from the other player's pedestal (they need 15 min of playtime first; set `NewPlayerProtectionSeconds = 0` in `GameConfig` while testing).
6. Test passes: set `GameConfig.StudioGrantAllPasses = true` (remember to set it back).

## Phase 3: Monetization setup (20 min)

1. Publish the game (File → Publish to Roblox).
2. **Creator Hub → Creations → Steal a Soul → Monetization**:
   - **Passes** → create the 10 passes from `docs/03-monetization.md` (icon 512×512, name, price, description).
   - **Developer Products** → create the 24 products (16 core + 2 Halloween Candy packs + 6 Robux upgrades).
3. Copy each ID into `src/shared/Config/MonetizationConfig.luau` (`Id = 0` → real ID). Anything left at `0` shows "Coming soon".
4. Test purchases in Studio (Studio purchases are free test purchases), and check the Output for warnings.

## Phase 4: Replace the greybox with your map (week 1–2)

Delete `Workspace.Hub`, `Workspace.Bases`, and `Workspace.Biomes` once you build your own with **the same names**:

**Workspace.Bases** (Folder) → `Base1` … `Base8` (Models), each containing:
| Child | Type | Purpose |
|---|---|---|
| `Zone` | Part (Transparency 1, CanCollide off) | box covering the plot; delivery and lock area |
| `Spawn` | Part | owner spawn point |
| `Pedestals` | Folder | `Pedestal1` … `Pedestal25` (Parts; numbered in fill order) |
| `Barrier` | Part (ForceField material, Transparency 1) | shown while locked |
| `LockButton` | Part | gets a "Lock Base" prompt automatically |
| `Sign` | Part + BillboardGui → TextLabel named `Text` | owner's name |

**Workspace.Biomes** (Folder) → Models named exactly `Meadow, Ember, Frost, Crypt, Storm, Void, Celestial, Abyssal`, each containing:
| Child | Type | Purpose |
|---|---|---|
| `Zone` | Part (invisible) | biome volume. **Its Front face (−Z) must point toward the bases** |
| `SoulSpawns` | Folder of Parts | orb spawn points (≥ MaxOrbs + 4 recommended) |
| `GuardianSpawns` | Folder of Parts | optional guardian homes |
| `GateReturn` | Part | optional; where under-speed players get sent back |

Layout rule: **deeper biome = farther from the bases.** Run time home is the core tension. Put cover (rocks, trees, ruins) in biomes so players can juke guardians.

Keep a `SpawnLocation` in the hub (players are moved to their base after loading).

## Phase 5: Art pass (week 2–3)

- **Pets:** model 56 spirits (or start with 8 Legendary/Mythic/Secret "hero" pets and recolors). Put them in `ReplicatedStorage.Assets.Pets.<Species name>` (Model with PrimaryPart). They're used automatically.
- **Orbs:** `ReplicatedStorage.Assets.Orbs.<Rarity>`.
- **Guardians:** `ServerStorage.Guardians.<BiomeId>` (rig with `Humanoid` + `HumanoidRootPart`; R15 rigs from the Avatar/Rig Builder work).
- **Tools:** `ServerStorage.Tools.SoulLantern` / `ReaperScythe` (Tool with `Handle`).
- **UI:** the code-built HUD is functional. For a premium look, re-skin with your own images by editing the `THEME` table and the `button()`/`makePanel()` helpers in `Main.client.luau`.

## Phase 6: Pre-launch checklist (week 3–4)

- [ ] `StudioGrantAllPasses = false`, `NewPlayerProtectionSeconds = 900`
- [ ] All pass/product IDs filled, prices match Creator Hub
- [ ] Odds table shown (pass/product descriptions + in-game)
- [ ] Maturity questionnaire done; experience set Public; genre "Simulation"
- [ ] Icon + 3–5 thumbnails + a 30s trailer video uploaded
- [ ] Group created, game owned by the group, group ID in `GameConfig.GroupId`
- [ ] 10+ friends in a private-server stress test (8 players, 1 hour): no errors in Output, data persists across rejoin
- [ ] Launch codes added to `Codes.luau`

## Suggested 3–4 Week Schedule

| Week | Focus | Exit criteria |
|---|---|---|
| 1 | Code in, greybox playtests, tune numbers in configs, create passes/products | Full loop fun on greybox with 4 friends |
| 2 | Map: hub, 8 bases, first 4 biomes; guardian rigs; orb/pet art for Legendary+ | Looks good in screenshots |
| 3 | Biomes 5–8, remaining pets, VFX/sounds, UI skin, thumbnails/icon, trailer | Feature-complete |
| 4 | Closed test (30–50 players), fix bugs, retune pacing, influencer outreach, **launch Fri/Sat** | D1 ≥ 30% in test |
