# 8. Retention Features & the Halloween Event

These are the "come back every day" systems most top Roblox games have, plus the **Hallow-Soul Festival** for Halloween.

## 8.1 Daily Login Streak 🎁
Claim once per day (resets at 00:00 UTC). Miss a day and the streak goes back to Day 1. The Gifts panel pops open automatically when today's gift is waiting.

| Day | Reward |
|---|---|
| 1 | 500 Essence (or 10 min of income, whichever is bigger) |
| 2 | 2x Luck for 15 min |
| 3 | 2,000 Essence (or 30 min of income) |
| 4 | 2x Essence for 30 min |
| 5 | **Epic Soul** from your best biome |
| 6 | 10,000 Essence (or 1 h of income) + 50 Candy during events |
| 7 | **LEGENDARY Soul** + 5x Luck for 15 min, then the cycle repeats |

## 8.2 Playtime Gifts ⏱️
Unlock by minutes played in the current session: **3 min** Essence, **10 min** Rare Soul, **20 min** 2x Luck plus Candy, **35 min** Epic Soul, **60 min** Essence jackpot plus Candy. A red **"!"** badge on the Gifts button shows when anything is claimable.

## 8.3 Daily Quests 📜
3 quests per player per day, picked from a pool: bring souls home, hatch spirits, rob a base, bring home Rare+ souls, buy Speed, bonk thieves, collect Candy, steal at night. **Finishing all 3 gives a Legendary Soul.** Quests are fixed per day (rejoining doesn't reroll them).

## 8.4 Spirit Index 📖
Every unique spirit you hatch is added to your Index permanently and gives **+1% Essence forever** (56 spirits = +56%). The Index panel shows "???" for undiscovered spirits, which gives collectors something to chase. The hatch pop-up shouts **"NEW SPIRIT DISCOVERED!"**

## 8.5 Global Leaderboards 🏆
Three boards in the hub (between the bases and the first biome): **Richest Soul Thieves** (lifetime Essence), **Most Souls Stolen**, and **Most Rebirths**. They update every 2 minutes. They need API access, so they show "offline" in Studio without it. To place them yourself, make `Workspace.Leaderboards` with Parts named `Essence`, `Steals`, `Rebirths`.

## 8.6 Hallow-Soul Festival 🎃 (Halloween event)
Runs automatically until **Nov 2, 2026 00:00 UTC** (`EventConfig.EndsAt`). Set `EventConfig.Active = false` to switch it off early.

- **Spooky world:** purple-orange lighting and haze, jack-o'-lanterns on every base corner, tombstones and glowing pumpkins in the hub and every biome. The whole UI turns orange and purple.
- **Candy 🍬** (event currency, kept after the event):
  - glowing **pumpkins** spawn everywhere (1–4 Candy, more in deeper biomes; **golden pumpkins** give 15)
  - every soul you bring home: 1 + rarity tier (Common 2 … Secret 8)
  - daily quests and playtime gifts
  - Robux: **Candy Bag** 49 R$ (120), **Candy Cauldron** 199 R$ (600)
- **Haunted mutation (x10 income):** 1% base chance on any hatch during the event (boosted by luck).
- **Candy Shop:**

| Item | Candy |
|---|---|
| Haunted Rare Soul | 60 |
| Haunted Epic Soul | 180 |
| Haunted Legendary Soul | 600 |
| Haunted Mythic Soul | 2,000 |
| Witch's Brew (2x Luck 15m) | 40 |
| Pumpkin Spice (2x Essence 15m) | 60 |

Haunted souls come from your **best unlocked biome**, so they're valuable at every stage of the game.

**Store title during the event:** `[🎃 HALLOWEEN] Steal a Soul 👻`. Post a "Haunted Mythic hatch" clip on TikTok/Shorts on launch day.

## 8.7 Other polish added
- **Guide beam:** a golden beam points to the nearest soul you can reach (first 15 steals) and points home whenever you're carrying a soul.
- **Next goal hint** under the Essence counter: "Next: 22 Speed unlocks Ember Hollow (x3 souls)" or the next rebirth with % progress.
- **Sounds:** pickup, hatch (pitch rises with rarity), claim, knockback, and UI clicks. They use built-in Roblox sounds; swap in Creator Store audio in the `SOUNDS` table of `Main.client.luau`.

## 8.8 Running the next event
Copy the Halloween block in `src/shared/Config/EventConfig.luau`: change `Id`, `Name`, `EndsAt`, `Lighting`, and the `Shop`. Add a new event-only mutation to `PetConfig.Mutations` with `EventOnly = true` (e.g. **Frostbitten** for a December "Winter Soulstice"). Decorations live in `EventService` (`decorate()`).
