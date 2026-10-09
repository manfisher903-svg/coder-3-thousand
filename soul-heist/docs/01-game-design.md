# 1. Game Design Document: Steal a Soul

> **Working title:** *Steal a Soul*. Alt: *Soul Heist Simulator*. Use "Steal a Soul" in the store because "Steal a ___" is the search term players already type.
> **Genre:** Steal / tycoon / simulator hybrid with light PvP
> **Session target:** 20–40 min. **First rebirth:** about 80 min free, about 45 min with boosts.
> **Server size:** 8 players (one base each)

---

## 1.1 Core Fantasy

You are a **soul thief**. Glowing **Soul Orbs** float in guarded spirit biomes. You grab one, sprint home while a guardian chases you, and drop it on a pedestal in your **Soul Sanctum**. While it incubates, any other player can run in and steal it. Once it hatches into a **Spirit Pet**, it's safe and earns **Essence** every second. You spend Essence to get faster, unlock deeper biomes, steal better souls, and finally **rebirth** for a permanent multiplier.

## 1.2 Core Loop (step by step)

```
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ 1. SPAWN in your base (Soul Sanctum) with 3 pedestals                     │
 │ 2. RUN to the deepest biome your Speed allows (speed gates block the rest)│
 │ 3. STEAL a Soul Orb (hold-E prompt; rarer = longer hold)                  │
 │ 4. HEIST: sneak past guardian vision cones, hide behind cover, use your   │
 │    Companion's power; get spotted (!) and they chase + call backup        │
 │      ↳ caught or bonked → orb drops → anyone can grab it                  │
 │ 5. DELIVER: walk into your base → orb auto-places on a free pedestal      │
 │ 6. INCUBATE: timer counts down. Orb is STEALABLE by other players.        │
 │      ↳ defend: Lock Base, bonk thieves, buy Shield / Instant Hatch        │
 │ 7. HATCH: owner's luck rolls Ascension (+1 rarity) and Mutation (x2–x40)  │
 │ 8. EARN: Spirit Pet produces Essence/sec (works offline at a reduced rate)│
 │ 9. UPGRADE: Speed (Treadmill) → next biome; Pedestals; Soul Harness        │
 │10. STEAL BETTER: deeper biome = x3 to x2000 income per soul                │
 │11. REBIRTH at 10M+ Essence → permanent x multiplier + Rebirth Tokens       │
 │12. Repeat faster (perks: luck, start speed, income, hatch speed)          │
 └──────────────────────────────────────────────────────────────────────────┘
```

Why it hooks players:
- **Every trip is a gamble.** Will it be a Legendary? Will I make it home?
- **Your base is always at risk.** Incubating orbs get stolen, which creates drama, revenge, and urgency to buy Instant Hatch, Shield, or Lock.
- **Visible progress.** Pedestals fill with glowing pets, and the number goes up every second.
- **Social proof.** Server-wide announcements ("X hatched a Mythic Soul Devourer!") make everyone want that too.

> **What makes it different from other steal games:** see [09-what-makes-it-different.md](09-what-makes-it-different.md): stealth heists, Companion powers, Soul Fusion and Haunt revenge.

## 1.3 Biomes

Biomes form a straight line out from the bases. **Deeper means farther, which means a longer and more dangerous run home.**

| # | Biome | Speed Req | Income x | Hatch x | Max orbs | Guardian | G. Speed | Ability |
|---|-------|-----------|----------|---------|----------|----------|----------|---------|
| 1 | Whispering Meadow | 16 | x1 | 1.0 | 10 | Wisp Sentry (x2) | 12 | none (tutorial) |
| 2 | Ember Hollow | 22 | x3 | 1.15 | 10 | Cinder Hound (x3) | 16 | none (fast pack) |
| 3 | Frostveil Peaks | 30 | x9 | 1.3 | 9 | Glacial Warden (x3) | 20 | **Slow Pulse**: 18-stud AoE, 60% speed for 2s |
| 4 | Sunken Crypt | 40 | x25 | 1.45 | 9 | Bone Knight (x3) | 26 | **Slow Pulse** (16 studs, 55%, 1.5s) |
| 5 | Storm Spire | 52 | x70 | 1.6 | 8 | Thunder Djinn (x3) | 32 | **Blink**: teleports behind fleeing thieves |
| 6 | Void Rift | 66 | x200 | 1.8 | 8 | Void Stalker (x4) | 40 | **Blink** (shorter cooldown) |
| 7 | Celestial Garden | 82 | x600 | 2.0 | 7 | Seraph Sentinel (x4) | 50 | **Slow Pulse** (22 studs) |
| 8 | Abyssal Throne | 100 | x2000 | 2.3 | 6 | **The Soul Reaper** (x2, boss-sized) | 62 | **Blink** (6s CD), huge catch radius |

**Guardian balance rule:** at the *minimum* Speed for a biome, carrying an Epic soul with 0 Soul Harness, you are only slightly faster than the guardian (Abyssal: 64 vs 62). At night guardians get +20% (Eclipse +35%) and **will** catch you unless you've upgraded Harness or Speed. That's what makes upgrades feel necessary.

Species per biome (one per rarity, Common to Secret):

| Biome | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Meadow | Wisplet | Glowmoth | Fernling | Dewdrop Sprite | Meadow Monarch | Elder Willowshade | The First Whisper |
| Ember | Cinderpup | Ashling | Flickerfox | Magma Imp | Phoenix Wraith | Inferno Djinn | Heart of the Hollow |
| Frost | Snowsoul | Frostkit | Icicle Owl | Glacier Golem | Aurora Stag | Rimefang Wyrm | Winter's Last Breath |
| Crypt | Bonewisp | Ghoulet | Lantern Lich | Grave Knight | Banshee Queen | Crypt Colossus | The Nameless King |
| Storm | Sparkling | Zephyr Kit | Thunder Ram | Storm Roc | Tempest Titan | Skyfather Shade | Eye of the Storm |
| Void | Voidmite | Shadowlurker | Riftwalker | Null Serpent | Abyss Watcher | Event Horizon | The Hollow Star |
| Celestial | Starlet | Moonhare | Comet Koi | Seraphling | Solar Archon | Galaxy Leviathan | Origin Soul |
| Abyssal | Soulshard | Dread Wisp | Chain Revenant | Reaper's Hound | Throne Wraith | Soul Devourer | The Reaper's Reflection |

That's 56 collectible spirits at launch, plus mutations. Every biome you add later brings 7 more.

## 1.4 Rarity System

| Rarity | Spawn weight | Base income/s | Hatch time | Carry slowdown | Pickup hold | Server announce |
|---|---|---|---|---|---|---|
| Common | 60% | 1 | 10s | 10% | 0.5s | no |
| Uncommon | 25% | 3 | 20s | 15% | 0.7s | no |
| Rare | 10% | 8 | 40s | 20% | 1.0s | no |
| Epic | 4% | 25 | 75s | 28% | 1.3s | no |
| Legendary | 0.9% | 80 | 2.5 min | 36% | 1.7s | **yes** |
| Mythic | 0.09% | 300 | 5 min | 45% | 2.2s | **yes** |
| Secret | 0.01% | 1,500 | 10 min | 55% | 3.0s | **yes** |

- **Pet income** = `BaseIncome × Biome.IncomeMult × Mutation.Mult`
- **Hatch time** = `Rarity.HatchSeconds × Biome.HatchMult × (1 − 5% × QuickIncubation) × (0.5 if Fast Hatch pass)`
- **Long hatch on rare souls is deliberate.** A Mythic sits stealable for 5–11 minutes, which drives Lock, Shield, Instant Hatch, and defensive play.
- **Spawn luck** (night x2, eclipse x5) multiplies Rare+ weights and gives Uncommon √luck.

### Ascension (hatch-time rarity upgrade)
On hatch: `chance = min(50%, 3% × Luck)` to jump **one rarity tier**. Luck comes from Super Luck pass (x2), potions (x2 / x5), and Soul Magnet perk (+10% per level). A 2x+5x stack gives 10x luck, so 30% ascension. The "ASCENDED!" pop-up is the gacha dopamine hit.

### Mutations (rolled at hatch, rarest first)

| Mutation | Income mult | Base chance | Condition |
|---|---|---|---|
| Gilded | x2 | 5% | always |
| Spectral | x3 | 2% | always |
| Moonlit | x5 | 0.8% | **night only** |
| Celestial | x8 | 0.3% | always |
| Voidtouched | x15 | 0.05% | always |
| Eclipsed | x40 | 0.3% | **Soul Eclipse only** |
| Rainbow | x25 | 0.01% | always |

Effective chance = `base × playerLuck × nightMutationLuck (x2 night, x4 eclipse)`, capped at 50%. Mutations of x15 or more get a server announcement.

## 1.5 Rebirth System

| | |
|---|---|
| **Cost** | `10M × 3.2^rebirths` Essence (10M, 32M, 102M, 328M, 1.05B, 3.4B, 10.7B, 34B, …) |
| **Permanent multiplier** | `1 + 0.5 × rebirths` on all income |
| **Rebirth Tokens** | `1 + floor(rebirthsAfter / 3)` per rebirth |
| **Resets** | Essence → 50, Speed → 16 (+Swift Start), Soul Harness → 0, Treadmill tier → 1 (unless Treadmill Memory), all pedestals cleared, **all unvaulted spirits deleted** |
| **Keeps** | Pedestal count, rebirths, tokens, perks, vaulted spirits, pending orbs, passes, redeemed codes |
| **Vault** | `1 + floor(rebirths / 2)` spirits survive (+3 with Soul Vault+ pass) |
| **Unlocks** | Treadmill tier 6 (Speed cap 130) at 1 rebirth, tier 7 (cap 160) at 5 rebirths |

**Rebirth Perk Shop** (paid with tokens, permanent):

| Perk | Effect | Max | Cost per level |
|---|---|---|---|
| Soul Magnet | +10% Luck | 10 | 1,2,3,…,10 |
| Essence Attunement | +10% income | 20 | 1,2,3,…,20 |
| Swift Start | +4 starting Speed | 5 | 2,4,6,8,10 |
| Quick Incubation | −5% hatch time | 8 | 1,2,…,8 |
| Treadmill Memory | keep Treadmill tier | 1 | 5 |

## 1.6 Day / Night Cycle

10-minute cycle: **6 min day, then 4 min night.**

| Phase | Spawn luck | Mutation luck | Guardian speed | Special |
|---|---|---|---|---|
| Day | x1 | x1 | x1.00 | none |
| Night | x2 | x2 | **x1.20** | Moonlit mutation unlocked |
| **Soul Eclipse** (every 4th night, or bought) | x5 | x4 | **x1.35** | Eclipsed (x40) mutation; red sky; announcement |

Night is high risk and high reward: better souls, but guardians outrun under-upgraded players. A purchasable **Summon Soul Eclipse** (499 R$) boosts *the whole server*, which is great social proof and makes the buyer the hero of the lobby.

## 1.7 Player Base Defenses

| Defense | How | Notes |
|---|---|---|
| **Lock Base** | Button in base or HUD. 45s force field pushes out intruders and blocks steals | 120s cooldown. **Fortress pass:** 90s lock, 60s cooldown |
| **Soul Shield** | Dev product, 10 min of no steals (49 R$) | Stacks duration |
| **New-player protection** | First 15 min of playtime (pre-rebirth) = unrobbable | Retention: new players never lose their first souls |
| **Bonk back** | Soul Lantern (free) / Reaper Scythe (pass) knocks a carried soul loose | The owner can grab it back |
| **Thief highlight** | Anyone carrying a soul stolen from a base glows red | Easy to chase |
| **Soul Echo** | Dev product (39 R$) restores a copy of the last soul stolen from you (10-min window) | Impulse buy at peak frustration |
| *(Update 2)* Spirit Traps | Placeable slow-tiles in base | Essence sink |
| *(Update 3)* Wraith Guard | Your own NPC that chases intruders | Rebirth 3 unlock / pass |

## 1.8 PvP (light combat)

- **Soul Lantern** (everyone): 9-stud range, 1.2s cooldown. Hitting a *carrier* drops their soul, plus 0.8s 70% slow and knockback. Hitting a non-carrier only gives a small knockback, so it has no griefing value.
- **Reaper Scythe** (299 R$ pass): 13-stud range, 0.8s cooldown, 1.4s stun, bigger knockback.
- All hits are resolved **server-side** (nearest player in a 60° cone), so the client never names a target.

## 1.9 Progression Stats (all of them)

| Stat | Start | Max | Raised by |
|---|---|---|---|
| Essence | 50 | none | pets, packs, codes, offline |
| Speed | 16 | 160 (tier 7) | Treadmill purchases (+1 / +10 / MAX) |
| Treadmill tier | 1 (cap 30) | 7 (cap 160) | Essence (tiers 6–7 need rebirths) |
| Soul Harness (Carry) | 0 | 15 (−60% slowdown) | Essence |
| Pedestals | 3 | 20 bought (+5 pass, +1 VIP; hard cap 25 physical) | Essence |
| Luck | x1 | about x15 | passes, potions, Soul Magnet |
| Rebirths | 0 | none | rebirth |
| Rebirth Tokens | 0 | none | rebirth |
| Inventory | n/a | 60 spirits | n/a |
| Vault | 1 | 1 + R/2 (+3) | rebirths, pass |
| Lifetime stats | n/a | n/a | Steals, base steals, times robbed, hatched, playtime, Robux spent |

## 1.10 Social Systems
- **Friend bonus:** +10% income per friend in server (max +40%), which pushes invites.
- **Group bonus:** +10% for group members, plus group-only codes.
- **Premium:** +10% (also earns Premium Payouts).
- **Announcements:** rare spawns, rare hatches, big steals, rebirths, pass purchases.
