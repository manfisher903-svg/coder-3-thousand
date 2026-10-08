# 3. Monetization Plan

All IDs go in `src/shared/Config/MonetizationConfig.luau`. Prices listed there are display-only; the real price is whatever you set in the Creator Hub, so keep them identical.

---

## 3.1 Game Passes (one-time, permanent)

| # | Pass | Price | Effect | Why it sells |
|---|---|---|---|---|
| 1 | **VIP Soul Thief** | **299 R$** | +10% Essence, +1 Pedestal, VIP chat tag/lounge | Status plus value bundle; cheap "first pass" |
| 2 | **2x Essence** | **449 R$** | All income x2, forever | The #1 earner in every tycoon/steal game |
| 3 | **Super Luck** | **399 R$** | Luck x2: more Ascensions and mutations | Gacha players chase Rainbow/Eclipsed |
| 4 | **+5 Pedestals** | **349 R$** | 5 extra pedestals | Early on it's +100% income |
| 5 | **Fast Hatch** | **249 R$** | Hatch 2x faster | Halves the time your souls can be stolen |
| 6 | **Phantom Steps** | **199 R$** | +4 Speed, souls 25% lighter | Wins chases; feels great immediately |
| 7 | **Reaper Scythe** | **299 R$** | Longer, faster bonk weapon, longer stun | PvP power fantasy, visible to everyone |
| 8 | **Fortress** | **249 R$** | Lock lasts 2x, cooldown halved | For players tired of getting robbed |
| 9 | **Soul Vault+** | **149 R$** | +3 spirits kept through rebirth | Bought right before the first rebirth |
| 10 | **Spirit Overtime** | **199 R$** | Offline: 50% for 12h (vs 10% for 2h) | "Earn while you sleep" |

Total for all passes: about 2,840 R$. Most whales buy 4–6.

## 3.2 Developer Products (repeatable)

| Product | Price | Effect | Trigger moment (where the UI shows it) |
|---|---|---|---|
| **Starter Pack** (once) | **99 R$** | Epic orb (best biome) + 5,000 Essence + 30-min 2x Essence | Shop top, first session only |
| **Instant Hatch** | **25 R$** | Hatch your slowest soul | Spirits panel whenever something incubates |
| **Hatch All** | **79 R$** | Hatch every soul | Same; best when several Legendaries are cooking |
| **Soul Echo** | **39 R$** | Copy of the last soul stolen from you (10 min) | Appears only right after you're robbed |
| **Essence Pouch** | **49 R$** | 15 min of income (min 1K) | Shop |
| **Essence Jar** | **149 R$** | 1 hour of income (min 5K) | Shop |
| **Essence Urn** | **399 R$** | 4 hours of income (min 25K), tagged "BEST VALUE" | Shop, anchor item |
| **Essence Reliquary** | **999 R$** | 12 hours of income (min 100K) | Shop, whale anchor |
| **2x Essence (30m)** | **79 R$** | 2x income; stacks with pass for 4x | Shop |
| **Lucky Potion (30m)** | **59 R$** | 2x Luck | Shop, at night |
| **Mega Luck (30m)** | **199 R$** | 5x Luck | Shop, during Eclipse |
| **Soul Shield (10m)** | **49 R$** | Base unrobbable for 10 min | When a Legendary+ is incubating |
| **Rebirth Skip** | **199 R$** | Rebirth now without the Essence | Rebirth panel |
| **Legendary Soul** | **399 R$** | Legendary orb from your best biome | Shop |
| **Mythic Soul** | **1,299 R$** | Mythic orb from your best biome | Shop, top of ladder |
| **Summon Soul Eclipse** | **499 R$** | 15-min server-wide 5x spawn luck, buyer named in banner | Shop; social flex |

**Essence packs scale with income** (`max(floor, income × seconds)`), so they stay worth buying at every stage of the game. That's the single most important rule for repeat purchases.

## 3.3 Pricing Ladder Strategy

```
25 → 39 → 49 → 59 → 79 → 99 → 149 → 199 → 249 → 299 → 349 → 399 → 449 → 499 → 999 → 1299
 └ impulse ┘  └── "small treat" ──┘  └────── considered purchase ──────┘  └ whale anchors ┘
```

1. **Get the first purchase.** The 25 R$ Instant Hatch and 99 R$ Starter Pack exist to turn a free player into a payer. After the first purchase, players are far more likely to buy again.
2. **Moments, not menus.** Products appear at the emotional peak: Soul Echo right after a robbery, Instant Hatch while a Mythic is incubating, Shield when a thief is near, Mega Luck during an Eclipse.
3. **Anchoring.** 999/1,299 R$ items make 399 R$ look reasonable. The 399 R$ Urn is priced as "best value per Robux" (4h for 399 vs 15m for 49).
4. **Permanent > consumable for trust.** Passes are the backbone. Consumables are the recurring revenue.
5. **Stacking.** 2x pass plus 2x potion gives 4x. Super Luck plus Mega Luck gives 10x. Stacking makes a second purchase feel smart, not redundant.
6. **Social proof.** Every pass purchase, Eclipse, and rare hatch is announced server-wide.
7. **Never sell only power.** Speed passes are capped (+4), and anyone can steal anything, so free players stay, and free players are the content for payers.

## 3.4 Expected Revenue Logic

Roblox pays creators **70%** of the Robux price for passes and products (30% platform fee). DevEx converts at about **$0.0038 per Robux** (rate after the 2025 increase; check the current rate). Premium Payouts are extra.

```
Daily Robux (net) = DAU × payer conversion × avg Robux per payer-day × 0.70
Daily USD         = Daily Robux × 0.0038
```

Benchmarks for this genre: payer conversion 1.5–4% of DAU; average spend per paying user per day 200–500 R$ (the top 1% of whales pull this up a lot). DAU is roughly 10–15x peak CCU.

| Scenario | Peak CCU | DAU | Conversion | R$/payer | Net R$/day | ≈ USD/day | ≈ USD/month |
|---|---|---|---|---|---|---|---|
| Soft launch | 300 | 4K | 2% | 250 | 14K | $53 | $1.6K |
| Solid | 3K | 40K | 2.5% | 300 | 210K | $800 | $24K |
| Hit | 25K | 300K | 3% | 300 | 1.9M | $7.2K | $215K |
| Mega-hit (front page) | 250K+ | 3M | 3% | 350 | 22M | $84K | $2.5M |

These are illustrative, not promises. Revenue is driven by **CCU, which is driven by retention plus algorithm placement**. Priorities in order:
1. D1 retention ≥ 35%, D7 ≥ 12% (hook plus fair new-player protection plus offline earnings).
2. Session length ≥ 20 min (biome ladder plus night cycle plus rebirth goal).
3. Conversion (moment-based offers, the first-purchase ladder).
4. ARPPU (whale anchors, stacking, Eclipse).

**Expected revenue split** (typical steal/tycoon): 2x Essence pass about 20%, other passes about 25%, Essence packs about 20%, Instant Hatch/Hatch All about 12%, luck potions about 10%, orbs and Eclipse about 8%, Shield/Echo/Skip about 5%.

## 3.5 Compliance Notes (important)

- **Paid random items:** hatch rolls (Ascension/mutations) on purchased orbs are random. Roblox requires **disclosing odds** for paid random items. Put the rarity and mutation odds table in the product descriptions and in an in-game "Odds" info panel. Some regions restrict paid random items. The client shop already checks `PolicyService:GetPolicyInfoForPlayerAsync` (`ArePaidRandomItemsRestricted`) and hides the Legendary Soul, Mythic Soul, and Starter Pack products for those players.
- Never sell a guaranteed outcome you can't deliver. Products with no valid target (e.g. Instant Hatch with nothing incubating) **auto-compensate with Essence**, already implemented.
- Complete the **Maturity & Compliance questionnaire**. The theme is fantasy "souls/spirits" with no gore; keep it cute, not horror, to stay at the widest audience rating.
- Don't promise Robux or real-world value in codes, ads, or influencer deals.
