# 6. Marketing & Launch Strategy

## 6.1 Positioning
**One-liner:** *"Steal glowing souls, outrun the Reaper, hatch spirits that make you rich, and steal your friends' souls too."*
**Hook vs. competitors:** same proven steal → hatch → upgrade loop, plus a **night/Eclipse event every 10 minutes** (always something happening) and **stealable incubation** (every hatch is a defend-your-base moment).

Title on the store: **`[🌑 ECLIPSE] Steal a Soul 👻`**. Rotate the bracket tag with each update (`[UPDATE 1]`, `[🔥 2X WEEKEND]`, `[NEW BIOME]`). Keep "Steal a" in the title for search.

## 6.2 Icon & Thumbnails

**Icon (most important asset, it decides click-through):**
- Close-up of a cute, glowing **Legendary spirit** (big eyes, purple/gold) held by a sneaky character hand, with a dark background and a strong rim light.
- 2–3 colors max, readable at 50×50 px. No small text; at most one word ("STEAL!").
- Make 3 variants and A/B test them using Roblox's built-in **thumbnail personalization / experiment** tools for 3–4 days each.

**Thumbnails (5):**
1. A player sprinting toward camera carrying a huge glowing Mythic orb, with **The Soul Reaper** right behind (motion blur, fear and excitement).
2. A base full of 20 glowing spirits with giant "+1.2B/s" numbers.
3. A friend stealing from a friend's base: red highlight thief, owner shocked, "HE STOLE MY MYTHIC!"
4. Eclipse sky (red) with a rainbow-mutated spirit hatching: "RAINBOW x25".
5. Biome collage (Meadow → Abyssal) with speed numbers: "16 → 100 SPEED".

Use large, bold outlined text (Fredoka/Luckiest Guy style) and saturated colors. Render in Blender or with a Roblox thumbnail artist (budget $30–150 each).

## 6.3 Code Strategy

| When | Code | Reward | Purpose |
|---|---|---|---|
| Launch | `RELEASE` | 500 Essence + 15m 2x Luck | Everyone; in description |
| Launch | `SOULTHIEF` | 10 min of income | Scales with progress |
| Launch | `FREEEPIC` | Epic Soul | Strong early hook |
| Like goal | `LIKE10K` | 30 min income + 2x Essence 15m | Pushes likes (ranking signal) |
| Eclipse events | `ECLIPSE` | 10 min 5x Luck | Social posts during events |
| First rebirth | `REBORN` | Legendary Soul (requires 1 rebirth) | Retention reward |

Rules:
- Put codes in the **description**, the **group shout**, and **Discord**, and have influencers give out their own creator code (e.g. `KREEK`) for attribution.
- New codes at **every like milestone** (1K, 5K, 10K, 25K, 50K, 100K…). Announce the next goal in-game ("Next code at 25K likes!").
- Codes that scale (`IncomeSeconds`) never go stale. Use flat rewards only for new players.
- Expire event codes (`Expires`) to create urgency.
- Always add 1–2 new codes with every update.

## 6.4 Influencer Outreach Plan

**Budget split (example $2–5K launch):** 60% micro creators, 30% mid creators, 10% Roblox Ads.

| Tier | Subs | How many | Cost | What you ask |
|---|---|---|---|---|
| Micro | 10K–100K | 15–25 | free (custom code + early access) to $50–200 | Play on stream/short, custom code |
| Mid | 100K–1M | 3–6 | $300–2,000 | Dedicated video in launch week |
| Large | 1M+ | 0–1 | $3K–20K+ | Only after you've proven retention |

**Sequence:**
1. **Week −2:** Build a list of 50 creators who covered "Steal a Brainrot" / "Steal an Egg" in the last 30 days (YouTube search, TikTok, Roblox Shorts). Note their email from the "About" page.
2. **Week −1:** DM/email with private-server access, their **own code** (adds a Codes.luau entry with their name), and a 30s clip. Offer an in-game **creator spirit** named after them (huge motivator).
3. **Launch day:** coordinated posting window (Friday 4–6 PM EST). Ask for the game link in the first line of the description.
4. **Week +1:** re-contact everyone who posted with update-1 early access. Double down on the 3 creators whose codes got the most redemptions (track via `RedeemedCodes`).

**DM template:**
> Hey {name}! I loved your {video} on Steal a Brainrot. I'm launching **Steal a Soul** on {date}: you steal glowing souls, outrun the Reaper, and hatch spirits (and yes, friends can steal yours mid-hatch 😈). I'd love to give you early access, a custom code **{NAME}** for your viewers, and a **Secret spirit named after you**. Want a private server link? Paid collab is possible too.

**TikTok/Shorts self-marketing (free, high leverage):** post 1–2 clips per day from launch week. Top formats: "stole my friend's Mythic," "Reaper almost caught me," "rainbow mutation hatch reaction," "0 to 100 speed."

**Roblox Ads:** after D1 retention ≥ 30%, run Sponsored Experiences for $50–100/day targeting the Simulator/Tycoon audience, optimized for plays. Scale up when cost per play is under about $0.02.

## 6.5 First 30-Day Update Roadmap

Ship **something every weekend**. The algorithm rewards update cadence and players return for events.

| Day | Update | Contents | Monetization hook |
|---|---|---|---|
| 0 (Fri) | **Launch** | 8 biomes, 56 spirits, rebirth, Eclipse | All passes/products |
| 3 | Hotfix + balance | Fix top bugs, tune guardian speeds from data | n/a |
| 7 (Sat) | **Update 1: Trails & Leaderboards** | Global leaderboards (Essence, Steals, Rebirths) via OrderedDataStore; Essence trails; daily login reward streak (7 days, day 7 = Epic Soul) | Robux-exclusive animated trails (149–399 R$) |
| 10 | **Weekend Event** | Admin abuse style: 2x Essence + guaranteed Eclipse every night for 48h | Mega Luck sales spike |
| 14 (Sat) | **Update 2: Base Traps** | Spirit Traps (slow tiles), Wraith Guard (NPC defender), base skins | Trap packs, Wraith Guard pass (349 R$) |
| 17 | Limited event | **Blood Moon** mutation (x60) for 72h | Luck potions |
| 21 (Sat) | **Update 3: New Biome 9 "Clockwork Necropolis"** | Speed 125, x6,000 income, new guardian "Time Warden" (rewinds thieves 3s), 7 new spirits | Biome-themed Legendary Soul bundle |
| 24 | **Trading** (if retention supports it) | Spirit trading with confirmations | Trade tokens / VIP trading hub |
| 28 (Sat) | **Update 4: Clans** | Clan bases / clan income bonus / weekly clan leaderboard | Clan creation (Essence) + clan boosts (R$) |
| 30 | Retro | Look at data: D1/D7, conversion, which products sell, then plan month 2 | n/a |

**Live-ops calendar:** a natural Eclipse every 40 min; weekend 2x; a mutation event every 2 weeks; a new biome every 2–3 weeks; holiday reskins (Halloween fits the soul theme perfectly. **Launching in October is a gift: run a "Hallow-Soul" event in the last week of October.**)

## 6.6 Community
- Roblox **group** (+10% income bonus drives joins), with shouts for codes.
- **Discord:** #codes, #trading, #suggestions, #clips. Bug-report form.
- Pin a "next update" countdown in-game (a sign at the hub).
