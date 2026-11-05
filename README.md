# HideSomeSurnames

A WoW: Forever addon that hides **chosen** surnames from nameplates and unit frames.

In WoW: Forever every character has a forename and a surname. If your group all
share one surname ("Dave Mhmm", "Matt Mhmm"...), it's just visual clutter on
screen. This addon hides only the surnames you list; everyone else's surname
stays visible. It is display-only: whispers, mail and invites still use the
full name.

> **Status: v0.3.0 (in development), written before WoW: Forever's launch and untested in-game.**
> Expect a fix round once the client is available.

## Install
1. Download `HideSomeSurnames.zip` from the [latest release](../../releases/latest).
2. Unzip it into `World of Warcraft\<version>\Interface\AddOns\` so you end up with
   `AddOns\HideSomeSurnames\HideSomeSurnames.toc`.
3. Restart the game or `/reload`.

(Don't use "Code > Download ZIP": that bundles the whole repo and the addon folder is nested one level down.)

## Configure
In game, open **Esc > Options > AddOns > HideSomeSurnames** (or type `/hss config`):

- **Surnames to hide**: type a surname and press Enter or **Add**; **Remove** takes one off the list (up to 20).
- **Chat channels**: tick Say, Party, Guild and/or Guild officer.

Changes apply immediately and are saved for your whole account. If the settings panel isn't
available on your client, the slash commands below do the same job.

`HideSomeSurnames/Config.lua` only provides the **first-run defaults** (`Mhmm`, all four
channels) and what `/hss reset` goes back to. Editing it later doesn't change saved settings.

## Commands
- `/hss` - show status and the hidden surname list
- `/hss config` - open the settings panel
- `/hss add <surname>` / `/hss remove <surname>` / `/hss list` - manage surnames without the panel
- `/hss reset` - go back to the defaults in `Config.lua`
- `/hss debug` - diagnostics (client build, hook status, which Options API was used, target name before/after). Include this output in bug reports.

## Scope and limitations
- Covers nameplates, unit/party/raid frames, and chat in **say, party, guild and guild officer**. Whispers, world/custom channels, yell, raid and instance chat (including dungeon-finder party chat) always show full names. Tooltips, /who and LFG are not covered.
- Only the visible name in chat is shortened. The hidden link data keeps the full name, so clicking a name to whisper, invite etc. still works. Whispers are never modified.
- If the addon can't hide a surname for any reason (unsupported API, restricted content), it shows the full name instead. If a feature errors repeatedly it switches itself off for the session and says so; it never throws Lua errors.
- Un-hiding a surname (or turning a channel off) can't restore names in chat lines that were already shortened; new lines show the full name. Nameplates and frames revert the next time the game refreshes them.
- Third-party nameplate/unit-frame addons (Plater, ElvUI, ...) draw their own names and are not affected.

## Development
`luajit tests/strip_spec.lua` runs the name-logic tests with a plain Lua interpreter.

### Releasing
1. Bump `## Version:` in `HideSomeSurnames/HideSomeSurnames.toc` (and `VERSION` in `HideSomeSurnames.lua`).
2. Open a PR, review and merge it, then `git checkout master && git pull && git tag vX.Y.Z && git push origin vX.Y.Z`.
3. GitHub Actions runs the tests, checks the TOC version matches the tag, zips the addon and publishes the release.
