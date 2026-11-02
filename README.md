# HideSomeSurnames

A WoW: Forever addon that hides **chosen** surnames from nameplates and unit frames.

In WoW: Forever every character has a forename and a surname. If your group all
share one surname ("Dave Mhmm", "Matt Mhmm"...), it's just visual clutter on
screen. This addon hides only the surnames you list; everyone else's surname
stays visible. It is display-only: whispers, mail and invites still use the
full name.

> **Status: v0.1.0, written before WoW: Forever's launch and untested in-game.**
> Expect a fix round once the client is available.

## Install
1. Download this repo (Code > Download ZIP, or a release zip) and unzip.
2. Copy the inner **`HideSomeSurnames`** folder (the one containing the `.toc`) into
   `World of Warcraft\<version>\Interface\AddOns\`.
3. Restart the game or `/reload`.

## Configure
Edit `HideSomeSurnames/Config.lua`:

```lua
HSS.surnames = { "Mhmm" }
```

Then `/reload`. An in-game editor is planned.

## Commands
- `/hss` - show status and the hidden surname list
- `/hss debug` - diagnostics (client build, hook status, target name before/after). Include this output in bug reports.

## Scope and limitations
- v0.1 covers nameplates and unit/party/raid frames only. Chat, tooltips, /who and LFG still show full names.
- Third-party nameplate/unit-frame addons (Plater, ElvUI, ...) draw their own names and are not affected.

## Development
`lua tests/strip_spec.lua` runs the name-logic tests with a plain Lua interpreter.
