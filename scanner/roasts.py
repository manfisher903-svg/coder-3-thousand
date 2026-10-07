"""Rotating 'username taken' roasts.

- 100 built-in lines (savage / funny / dark — but no slurs, and nothing aimed
  at race, gender, religion, orientation or disability).
- A different set of lines is featured each week (seeded by the ISO week), and
  one is picked at random within that week's set — so it stays fresh.
- You can add your own: drop one line per message into a file named
  `roasts.txt` next to the app and they're mixed into the pool automatically.
"""

from __future__ import annotations

import os
import random
from datetime import date

ROASTS = [
    "That username's TAKEN bruh 😂 — think of another one.",
    "Damn, somebody already got that one 💀 try again, champ.",
    "Nope. Taken. L + ratio 🤡 — pick a new one.",
    "That name's spoken for, big dawg 😤 cook up something else.",
    "Taken! You really thought you were the only one 😂🤦",
    "Someone beat you to it, slowpoke 🐌 — new username, let's go.",
    "That's taken 💅 be more original.",
    "Bro really tried a taken username 😭 pick another one.",
    "Taken. Skill issue 🎮 — try again.",
    "Nah that one's gone 🚫 think harder.",
    "Taken. Did you really think you were that special? 😂",
    "That username retired before you got here 👴 pick another.",
    "Already claimed. Better luck next brain cell 🧠",
    "Taken 💀 the audacity to even try.",
    "That one's booked solid 📅 next.",
    "Someone with more imagination grabbed it first 🎨",
    "Taken! Try again, but like… try this time.",
    "That username ghosted you — it's taken 👻",
    "Gone. Snoozed, loozed. Pick a new one 😴",
    "Taken. This is why we can't have nice things 🙄",
    "Nope, that's mine now (in spirit). Taken. Choose again.",
    "Taken 💀 even the server's embarrassed for you.",
    "That name's taken, and honestly? Upgrade. Try again.",
    "Taken. Your creativity is on airplane mode ✈️",
    "Already taken 😂 who hurt your originality?",
    "That username's taken. So is my patience. Again.",
    "Taken! Spin the wheel of names one more time 🎡",
    "Gone before you woke up 🌅 taken. New one.",
    "Taken. The good names don't wait around, slowpoke.",
    "That one's claimed 🏴 plant your flag somewhere else.",
    "Taken 💀 you fumbled a username. Impressive.",
    "Nope. Occupied. Vacate and pick another 🚪",
    "Taken! Even autocomplete could do better. Try again.",
    "That username is unavailable, superstar 🌟 next.",
    "Taken. History will not remember this attempt. Again.",
    "Gone. Poof. Taken ✨ think of something fresh.",
    "Taken 😤 bring your A-game next try.",
    "That's taken — and that's a YOU problem. Retry.",
    "Taken. The queue for originality starts behind you.",
    "Already gone 💀 you're late to your own party.",
    "Taken! The server said 'absolutely not.' Try again.",
    "That username clocked out. Taken. Pick a new shift.",
    "Taken. We both know you can do better. Maybe.",
    "Nope. Dibs were called. Taken 🫡",
    "Taken 💅 serve us something new.",
    "That one's gone fishing 🎣 taken. Cast a new one.",
    "Taken. Your username game needs a patch update 🩹",
    "Already claimed. The early bird got your name 🐦",
    "Taken! Legendary fumble. Try once more.",
    "That username's in witness protection now. Taken. Next.",
    "Taken. Even a random number generator has more flair.",
    "Gone 💀 and it's not coming back. New name.",
    "Taken. This ain't it, chief. Reload and retry.",
    "That name's taken. Manifest a different one ✨",
    "Taken! You walked right into that one 🚶",
    "Nope. Spoken for. Try harder, legend.",
    "Taken 😂 the second-hand embarrassment is real.",
    "That username rage-quit. Taken. Pick a new main.",
    "Taken. Press F for your creativity 🇫",
    "Already gone. You snooze, you lose the username 😴",
    "Taken! Great minds think alike — too alike. Retry.",
    "That one's off the menu 🍽 order something else.",
    "Taken 💀 the server physically cringed.",
    "Nope. Claimed. Decommission that idea and retry.",
    "Taken. Even your shadow wouldn't use that twice.",
    "That username's taken. Blink twice and think again.",
    "Taken! Respawn with a better name 🎮",
    "Gone. Yesterday's news 📰 taken. Fresh print, please.",
    "Taken 😤 the competition is NOT playing fair (they were faster).",
    "That one's locked 🔒 find another door.",
    "Taken. You brought a spoon to a name fight. Retry.",
    "Already taken 💀 somewhere, someone's laughing.",
    "Taken! Plot twist: not yours. Choose again.",
    "That username expired like old milk 🥛 taken. Pour a new one.",
    "Taken. The bar was on the floor and you… tripped. Again.",
    "Nope. Reserved. VIP's only, and it's not you. Retry.",
    "Taken 😂 the recycle bin called, it wants your idea.",
    "That name's taken. Deploy a backup brain cell 🧠",
    "Taken. Somewhere a server is shaking its head.",
    "Gone before the loading bar finished ⏳ taken. New one.",
    "Taken! You had one job… and someone else did it first.",
    "That username's booked till the heat death of the universe. Taken.",
    "Taken 💀 even the 404 page feels bad for you.",
    "Nope. Occupied real estate. Build elsewhere 🏗",
    "Taken. The council has denied your name 🧙",
    "That one's gone. Not today. Not ever. Taken. Retry.",
    "Taken! Swing again, slugger ⚾",
    "Already claimed 😂 originality left on read.",
    "Taken. Your username is in another castle 🏰",
    "That name tapped out. Taken. Send in a sub.",
    "Taken 💀 the disrespect of even trying.",
    "Nope. That's a wrap on that one. Taken. New take.",
    "Taken! Somebody speedran your idea. Try again.",
    "That username's taken — and slightly judging you.",
    "Taken. Reroll those stats 🎲 new name.",
    "Gone 💀 taken. The void thanks you for your sacrifice.",
    "Taken! You and 400 other people had that thought. Retry.",
    "That one's claimed. Cope, seethe, and pick another 😤",
    "Taken. The username gods have spoken: nah. Again.",
    "Already taken 😂 better luck in your next life.",
]


def _week_seed() -> int:
    y, w, _ = date.today().isocalendar()
    return y * 100 + w


def _pool():
    pool = list(ROASTS)
    # Fold in any user-added lines from roasts.txt (one per line).
    try:
        with open("roasts.txt", "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    pool.append(line)
    except Exception:
        pass
    return pool


def pick_roast() -> str:
    pool = _pool()
    if not pool:
        return "That username is already taken — pick another."
    # Feature a rotating subset each week, then pick randomly within it.
    weekly = random.Random(_week_seed()).sample(pool, k=min(25, len(pool)))
    return "⚠️ " + random.choice(weekly)
