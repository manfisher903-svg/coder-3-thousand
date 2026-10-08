# 2. Economy Design

Every number here lives in **one** place: `src/shared/Config/EconomyConfig.luau`, `PetConfig.luau`, and `BiomeConfig.luau`. The client UI and the server both use `src/shared/Formulas.luau`, so the price shown is always the price charged.

---

## 2.1 Starting Numbers

| | Value |
|---|---|
| Essence | **50** |
| Speed | **16** (Roblox default WalkSpeed) |
| Pedestals | **3** |
| Treadmill | Tier 1 (Speed cap 30) |
| Soul Harness | 0 |
| Luck | x1 |

The first steal in Whispering Meadow pays back the first Speed upgrade within a minute.

## 2.2 Passive Income

```
PetIncome      = Rarity.BaseIncome × Biome.IncomeMult × Mutation.Mult
BaseIncome     = Σ PetIncome of spirits on ACTIVE pedestals
Income/sec     = BaseIncome × RebirthMult × Attunement × Social × Pass × Boost

RebirthMult    = 1 + 0.5 × rebirths
Attunement     = 1 + 0.10 × perkLevel                    (max +200%)
Social         = 1 + 0.10 Premium + 0.10 Group + 0.10 VIP + 0.10 × friends (max 4)
Pass           = 2  (2x Essence pass)
Boost          = 2  (2x Essence 30-min potion; stacks with the pass, so 4x)
```

Ticked server-side once per second. Offline earnings:

```
Offline = LastIncome/sec × min(secondsAway, cap) × percent
Free           : 10%, capped at 2 hours
Spirit Overtime: 50%, capped at 12 hours   (5x more, 30x more if away overnight)
```

**Average income of one soul by biome** (spawn luck 1, before mutations):

| Biome | Avg soul income/s | ×1.12 avg mutation value |
|---|---|---|
| Meadow | 4.3 | 4.8 |
| Ember | 12.9 | 14.4 |
| Frost | 38.6 | 43 |
| Crypt | 107 | 120 |
| Storm | 300 | 336 |
| Void | 858 | 961 |
| Celestial | 2,574 | 2,883 |
| Abyssal | 8,580 | 9,610 |

Each biome is worth about **3x** the previous one. That's the "steal better" pull: one Celestial Common (600/s) out-earns a full Meadow base.

## 2.3 Upgrade Costs

### Speed (Treadmill purchases)
`cost(s → s+1) = floor(25 × 1.18^(s − 16))`

| To unlock | Speed | Cumulative cost from 16 |
|---|---|---|
| Ember Hollow | 22 | 234 |
| Frostveil Peaks | 30 | 1,263 |
| Sunken Crypt | 40 | 7,225 |
| Storm Spire | 52 | 53,598 |
| Void Rift | 66 | 545,302 |
| Celestial Garden | 82 | 7.7M |
| Abyssal Throne | 100 | 151.6M |

### Treadmill tiers (Speed cap)
| Tier | Cap | Cost | Requires |
|---|---|---|---|
| 1 | 30 | free | n/a |
| 2 | 45 | 1,500 | n/a |
| 3 | 60 | 15,000 | n/a |
| 4 | 80 | 250,000 | n/a |
| 5 | 100 | 5,000,000 | n/a |
| 6 | 130 | 100,000,000 | 1 rebirth |
| 7 | 160 | 5,000,000,000 | 5 rebirths |

### Pedestals
`cost(n-th pedestal) = floor(500 × 1.9^(n − 4))`

| # | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 12 | 14 | 16 | 18 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Cost | 500 | 950 | 1.8K | 3.4K | 6.5K | 12.4K | 23.5K | 84.9K | 307K | 1.1M | 4.0M | 14.4M |

### Soul Harness (carry)
`cost(level L → L+1) = floor(150 × 2^L)`, giving −4% carry slowdown per level (max 15 levels = −60%).
150, 300, 600, 1.2K, 2.4K, 4.8K, 9.6K, 19.2K, 38.4K, 76.8K, 154K, 307K, 614K, 1.23M, 2.46M (total 4.9M).

### Carry slowdown
```
CarriedSpeed = Speed × (1 − Heaviness × max(0, 1 − HarnessReduction − 0.25 if Phantom Steps))
```
Example: Speed 100 carrying a Mythic (45%): no harness gives 55; max harness gives 82; max harness plus Phantom gives 93.

### Trails (cosmetic, *Update 1*)
Cosmetic trails sell for Essence as a late-game sink and status symbol, not a stat. Suggested: 50K, 1M, 25M, 1B, 100B, plus Robux-exclusive animated trails at 149–399 R$.

## 2.4 Rebirth Economics

| Rebirth # | Cost | Multiplier after | Tokens gained |
|---|---|---|---|
| 1 | 10M | x1.5 | 1 |
| 2 | 32M | x2.0 | 1 |
| 3 | 102M | x2.5 | 2 |
| 4 | 328M | x3.0 | 2 |
| 5 | 1.05B | x3.5 | 2 |
| 6 | 3.36B | x4.0 | 3 |
| 7 | 10.7B | x4.5 | 3 |
| 8 | 34.4B | x5.0 | 3 |
| 9 | 110B | x5.5 | 4 |
| 10 | 352B | x6.0 | 4 |

Cost grows 3.2x per rebirth while the multiplier grows linearly, so each rebirth takes a bit longer. Rebirth perks (Attunement +200%, Swift Start) and later biomes added in updates keep the curve climbable.

## 2.5 Pacing (simulated)

Monte-Carlo sim of a reasonable player (25% failed steals, greedy upgrades). Re-run with `python3 tools/pacing_sim.py` after retuning:

| Milestone | Free player | 4x (2x pass + potion) |
|---|---|---|
| Ember Hollow | 3 min | 2.6 min |
| Frostveil Peaks | 6 min | 4 min |
| Sunken Crypt | 10 min | 7 min |
| Storm Spire | 16 min | 10 min |
| Void Rift | 28 min | 16 min |
| Celestial Garden | 58 min | 31 min |
| **First Rebirth (10M)** | **80 min** | **45 min** |
| Abyssal Throne | 95 min | 51 min |

Real players will be somewhat slower, because others steal from them and they lose fights. That's healthy, since it's exactly the friction the products solve.

## 2.6 Free vs. Paying Balance

**Design principle: payers go faster and look cooler, but never lock free players out.**

- Every biome, stat, and spirit is reachable for free. No pay-only pets at launch.
- Biggest permanent accelerators: 2x Essence (x2), Super Luck (x2 luck, so more mutations), +5 Pedestals (+25–100% income early), Fast Hatch (half the vulnerable window).
- A typical "whale stack" (2x pass + 2x potion + VIP + Super Luck + Mega Luck) runs about **5–8x** a free player's speed. That's a meaningful lead without breaking the game.
- Free players get catch-up tools: codes that scale with income (`IncomeSeconds`), friend bonus, new-player protection, offline earnings, and a free natural Eclipse every 40 minutes.
- **Stealing is the great equalizer.** A skilled free player can rob a whale's incubating Mythic. That makes whales buy defense (Shield, Lock, Instant Hatch) and makes free players feel powerful, so both sides stay.

## 2.7 Sinks & Faucets Summary

| Faucets | Sinks |
|---|---|
| Spirit income (main) | Speed, Treadmill, Harness, Pedestals |
| Offline earnings | Rebirth (wipes Essence) |
| Selling spirits (income × 60s) | Losing incubating orbs to thieves |
| Codes, essence packs | Trails/cosmetics (Update 1), traps (Update 2) |
