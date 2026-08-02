Ebonhold Smart Mounts 1.2.1
================================

For Project Ebonhold / World of Warcraft 3.3.5 (Interface 30300).

Version 1.2.1 fixes the Weight button so it visibly cycles between Normal,
Frequent and Rare. Version 1.2 simplified configuration to two pools. Every
learned mount is classified as Ground or Flying and only the matching
selection box is shown.
Ahn'Qiraj mounts are excluded automatically. The old pool and filter cycling
controls have been removed, and the window copy has been shortened to fit.

Core behavior
-------------
- Uses separate Ground and Flying pools.
- Automatically chooses a pool from the current area's flyability.
- Shift forces Ground and Control forces Flying.
- Zone and sub-zone overrides can force Ground or Flying where automatic
  detection is not correct.
- Uses a shuffle bag: every selected mount appears once before weighted
  repeats begin, and immediate repeats are avoided where possible.

Configuration
-------------
Open the window with /ehm or right-click the summon button.

- Tick Ground for a detected ground mount or Flying for a detected flying
  mount. The checkbox for the wrong mount type is hidden.
- Search filters the visible list by mount name without changing its order.
- Weight cycles through Rare, Normal and Frequent.
- Refresh Mounts rescans the live collection several times.
- Ahn'Qiraj Qiraji mounts are hidden and removed from saved selections.
- The zone controls allow Automatic, Ground or Flying overrides for the
  current zone or sub-zone.

Availability
------------
Ready mounts are confirmed by the live mount collection. Cached mounts came
from EbonCompletionist's account-wide cache. Ready mounts are preferred; cache
entries are used only when no selected Ready mount exists in that pool.

Macro management
----------------
The addon creates a character macro named "EH Smart Mount" containing:

    /click EbonholdSmartMountsButton

The configuration window can create/repair the macro and place it directly on
the cursor so it can be dropped onto an action bar.

Commands
--------
/ehm                         Open or close configuration.
/ehmsummon                   Automatically select and summon.
/ehmsummon ground            Force Ground.
/ehmsummon flying            Force Flying.
/ehm macro                   Create or repair the action-bar macro.
/ehm button                  Show or hide the summon button.
/ehm lock                    Lock or unlock the summon button.
/ehm debug                   Toggle detailed selection messages.
