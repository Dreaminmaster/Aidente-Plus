# Third-Party Notices

Aidente is a modified GPL-3.0 work based on:

- Stasis, commit `e521505c0e7cdd98ca11ed1dc45b0d1db8682ab2`
  - Copyright belongs to the Stasis contributors.
  - License: GNU General Public License version 3.
  - Source: <https://github.com/srimanachanta/Stasis>
- SMCKit
  - Copyright belongs to the SMCKit contributors.
  - License: MIT.
  - Source: <https://github.com/srimanachanta/SMCKit>
- Defaults 9.0.6
  - Copyright belongs to Sindre Sorhus and contributors.
  - License: MIT.
  - Source: <https://github.com/sindresorhus/Defaults>

The project also references publicly documented behavior and feature descriptions
from AppHouseKitchen solely to understand user-facing battery-management
workflows. No current AlDente source code, application binary, artwork, license
mechanism, or proprietary asset is included.

AlDente is a trademark of its respective owner. Aidente is independent and is
not affiliated with or endorsed by AppHouseKitchen.

The firmware register identifiers and byte-level charging protocol were checked
against public research in charlie0129/batt (commit
`ee86539e977049d9f15d2641f4545c17eabf679f`, `pkg/smc/charging.go`) and read-only
probes on a MacBook. No batt source is bundled or linked; the Swift register
adapter, transactional rollback, and integration are independently implemented.
Protocol reference: <https://github.com/charlie0129/batt>.

The PowerUI smart-charge selector names and ABI were cross-checked against
charlie0129/batt commit `2b9f8b579670b3d07365772f6f8e56b4f53912be`
(`pkg/powerui`) and independently verified with read-only runtime queries.
The Swift runtime bridge is independently implemented; no batt code is bundled.
Apple owns PowerUI; its private API may change without notice.

PowerUIAgent's two-preference protocol and the relationship between a current-level
hold and an explicit lower discharge target were cross-checked against Sail's public
design research (jiraffekiller/sail, commit
`7f1d5cd302dc9ddc7d5949e80f6881caf168859c`, docs/DESIGN.md). The Swift
transaction, recovery snapshot, frozen hold policy and integration are independently
implemented. Sail is GPL-3.0; no Sail binary, UI asset or source is bundled.
Research reference: <https://github.com/jiraffekiller/sail>.

Native policy application delays, latched reported gauge behavior, and the need to
unregister a powerd limit before restoring disabled preferences were cross-checked
against az-code-lab/ampere public README research, commit
`843498d7beb711c0e1b18e48c8520debe67f6e3f`. No Ampere code, binary,
assets, licensing logic or sudoers configuration is included or executed.
Reference: <https://github.com/az-code-lab/ampere>.

Hardware power sensor key meanings were cross-checked against public research in
<https://github.com/exelban/stats/issues/3621> (M5 PZC0 includes CPU/GPU) and
<https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift>
(display backlight key PBwo on M5). Only key/protocol facts are used; no Stats
source code or UI assets are included. Other M5 rails are intentionally unmapped
until their physical meaning can be verified. USB power is currently unavailable.
