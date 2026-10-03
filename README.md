<<<<<<< HEAD
# M-Roulette
Mythic+ AddOn for World of Warcraft to help choose a key
=======
# Key Roulette (World of Warcraft Addon)

**Key Roulette** is a sleek, modern World of Warcraft addon (compatible with Midnight 12.1.0 and 11.x) inspired by **EllesmereUI**. It automatically reads the Mythic+ Keystones of your party members, displays them in a clean dark UI accented by your active character's **class color**, and lets you pick a random key with an interactive roulette wheel animation and output the winning key directly to party chat!

---

## 🌟 Key Features

- **EllesmereUI Aesthetics**: Clean dark slate theme (`#0d0d10`), 1px borders, subtle gradients, and class color accents.
- **Dynamic Class Color Theme**: Automatically tints the header accent bar, title, button glows, and minimap icon using your character's class color (e.g. Paladin Pink, Evoker Teal, DK Red, Warlock Purple).
- **Auto Mythic+ Key Scanning**: Automatically scans your bags and uses standard WoW `C_MythicPlus` & `C_ChallengeMode` APIs to retrieve dungeon names, icons, and key levels.
- **Addon-to-Addon Party Sync**: Automatically syncs keystones across party members over the `KeyRoulette` addon channel.
- **Manual Key Override**: Easily edit or manually set dungeon and key level (+2 to +30) for party members who don't have the addon installed.
- **Interactive Roulette Spin Wheel**: Spin button triggers a rapid visual slot/roulette animation with audio ticks, decelerating smoothly before locking onto the winning key with a gold winner highlight!
- **Chat Announcement System**: Automatically announces the winner to `PARTY`, `RAID`, `INSTANCE_CHAT`, `SAY`, or local `SELF` chat.
- **Minimap Button**: Convenient class-colored launcher icon on the minimap.

---

## ⚙️ Commands

- `/kr` or `/keyroulette` or `/keyr` — Open/close the Key Roulette window.
- `/kr spin` — Instantly spin the roulette wheel.

---

## 📁 Installation

1. Copy the `key_roulette` folder into your World of Warcraft AddOns directory:
   - **Retail**: `World of Warcraft\_retail_\Interface\AddOns\key_roulette`
2. Restart or reload World of Warcraft (`/reload`).

