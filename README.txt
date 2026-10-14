ZenSmartMounts v1.4.0 | WoW 3.3.5a (Interface 30300)
====================================================

This is the renamed Ebonhold Smart Mounts v1.3.2 with the embedded
ZenStylingPack v1.1.0 UI. Original selection and secure summon mechanics
are retained, with new names, themes, and macro migration.

INSTALLATION
------------
1. Exit the game. Back up the old addon and its SavedVariables first.
2. Remove/disable the old Ebonhold Smart Mounts addon to avoid duplicate
   slash commands or two competing summon buttons.
3. Extract the ZenSmartMounts folder into World of Warcraft/Interface/AddOns/.
   The correct folder must contain ZenSmartMounts.toc and UI/Init.lua.
4. (Optional, to preserve saved selections) Use the migration instructions below.
5. Start the game, enable ZenSmartMounts, type /zsm.

KEEPING YOUR OLD SELECTIONS
---------------------------
WoW saves variables in a per-addon file. Renaming the addon folder does not
load the old SavedVariables file automatically.

While WoW is CLOSED, locate the previous addon's SavedVariables file under
WTF/Account/<Account>/SavedVariables/. Typically it is named
EbonholdSmartMounts.lua, but it can follow the old addon folder name.
Back it up. If there is not already a ZenSmartMounts.lua file, COPY the old
file to ZenSmartMounts.lua in the same directory (do not delete the old file).
ZenSmartMounts accepts the legacy EbonholdSmartMountsDB variable in that
copied file and imports it into ZenSmartMountsDB on the next login.
If a ZenSmartMounts.lua file already exists, do not overwrite it without
backing it up / merging carefully.

MOUNTING
--------
- Separate Ground and Flying lists, with area auto-detection.
- Shift forces Ground, Control forces Flying.
- Rare / Normal / Frequent weights (1 / 2 / 4) and shuffle-bag selection.
- Zone/subzone Ground/Flying overrides; AQ mounts excluded.
- Built-in draggable summon button, right-click to configure.
- Mount Journal, companion collection, and EbonCompletionist cache support.

ZENSTYLINGPACK APPEARANCE
-----------------------
Use /zsm appearance or the Appearance button to open the theme editor.
Choose Classic, Obsidian, Glass, Flat, Brutal, Neon, accent colour, panel
opacity, scale and fonts. Settings can be local to ZenSmartMounts or shared
with other Zen addons through EbonAPI if installed and compatible.
ZenStylingPack is embedded: it does not require a separate addon.

MACRO AND KEYBINDINGS
---------------------
The new character macro is named "Zen Smart Mount" and contains:
    /click ZenSmartMountsButton
An existing "EH Smart Mount" macro is renamed and repaired IN PLACE if its
body is the recognised old addon click command or /ehmsummon. That keeps
its macro slot so existing action-bar placements can continue to work.
An unrelated macro with the same name is not overwritten. You can use
Create/Repair and Place on Cursor in the window.
Key bindings: ZenSmartMounts > Summon smart random mount.

COMMANDS
--------
/zsm, /zensmartmounts     Toggle config window
/zsm appearance           Open appearance editor
/zsm macro                Create/repair macro
/zsm button               Toggle summon button
/zsm lock                 Lock/unlock summon button
/zsm debug                Toggle diagnostic chat messages
/zsmsummon                Summon automatically or dismount
/zsmsummon ground         Force ground pool
/zsmsummon flying         Force flying pool

Legacy slash aliases /ehm, /ehmount, /smartmount, /ehmsummon remain supported.

NOTES
-----
The appearance integration and static Lua syntax have been reviewed, but
in-game runtime behaviour has not been verified with a WoW client.
