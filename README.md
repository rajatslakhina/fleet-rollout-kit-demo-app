# FleetRollout Demo

**Drag one slider and watch a 2,000-device fleet re-bucket in real time — then flip the kill switch and watch every flag in the app fall back to the value that shipped in the binary.**

This is a SwiftUI app that consumes [**fleet-rollout-kit**](https://github.com/rajatslakhina/fleet-rollout-kit) as a **version-pinned remote Swift Package dependency** (`upToNextMajorVersion` from `1.1.0` — not a branch, not a local path). Everything on screen is computed by the package's real evaluator and real simulator. Nothing is mocked and no number is hard-coded.

## Why this matters

On 21 September 2026 the iOS version stopped being a line. iOS 27.1 shipped **only** to iPhone Duo; every other iPhone went from 27.0 straight to 27.2 ([9to5Mac, 21 Sep 2026](https://9to5mac.com/2026/09/21/apple-releases-second-ios-27-2-developer-beta-for-iphone/); [downgrade window closed the same day](https://9to5mac.com/2026/09/21/iphone-users-running-ios-27-can-no-longer-downgrade-to-ios-26/)). The check almost every feature flag in the industry is written with — `osVersion >= "27.1"` — matches a 27.2 device that never ran a line of 27.1's code. On the same day Apple closed the downgrade path off iOS 27, so a user who takes a bad build on a bad OS train cannot roll themselves out of it.

A dashboard is the right way to show that, because the failure is a *distribution*, not an exception. You cannot see it in a log line. You can see it instantly as a bar that is 34× too long.

Three things the app lets you do, and what each one demonstrates:

| Interaction | What it shows |
|---|---|
| **Drag the ramp slider** | Exposure moves from 0 to ~37% of the fleet (0 → 739 of 2,000 devices; 72 at the 10% default it opens on), and the "Treated devices by OS train" panel shows the treatment reaching `ios-27.2` and `ios-27.1-duo` and **never** `ios-27.0` or `ios-26.5`. Widening never evicts a device that was already treated — the salt does not change when the width does. |
| **Flip the kill switch** | Every flag's evaluation reason flips to `killed` at once, and every value resolves to the app's compiled-in `FallbackCatalog` — not to the document's own default variant. Those are different values on purpose: the moment you reach for a kill switch is often the moment you stopped trusting the server's choices. |
| **Toggle "trust silent push and background refresh"** | For this app's 2,000-device fleet, coverage over an hour drops from 91.5% to 56.5% and p95 climbs from 40.5 to 55.5 minutes. The SLO badge shows a warning either way: neither configuration meets a naive 95%-in-15-minutes kill SLO, because the tail is devices that simply are not running your app. Silent push and background refresh are best-effort by Apple's own documentation. |

(The library's README quotes slightly different figures — 92.2% / 55.3% — because its test runs 5,000 devices at a fixed seed. The app runs 2,000 at the simulator's default seed. Same model, different sample.)

The app also owns the compiled-in configuration itself — see `CompiledInConfiguration` in `Demo/DemoApp.swift`. That split is the reason the demo imports the core `FleetRollout` module as well as `FleetRolloutUI`: the fallback values and the bundled document belong to the **app**, because they are the answer that ships in the binary and works with the network unplugged. A config system whose "off" state is defined by the server has no off state at all.

## Decisions made in *this* repo

The library's architectural decisions are argued in its own README. Three belong here, because they are about how a demo app is packaged rather than about how the rollout system works.

**The package reference is a version range, not a branch.** Branch-tracking means every clone and every CI run resolves whatever `main` happened to be that day, so "it built for me" and "it built for you" are claims about different code. `upToNextMajorVersion` from `1.1.0` bounds that to a compatible line, and the CI job prints the resolved `Package.resolved` on every run, so the exact version any given build used is recoverable from the log rather than from folklore. *Rejected:* an exact pin (`exactVersion`), which is fully reproducible but makes a patch release of the library invisible to the demo, so the pair drifts and the demo stops being evidence that the *current* library works. Also worth naming as a real gap: no `Package.resolved` is committed here, because the project has never been opened by Xcode on the machine that produced this repo — so a clone resolves the newest 1.x rather than exactly 1.1.0. Committing that lockfile is the one thing that would make this claim airtight, and it needs a run this repo has not had.

**`project.pbxproj` is hand-written and committed, along with a shared scheme.** That is unusual and it is deliberate: an Xcode-generated project carries the generating machine's local package checkout state and a per-user scheme, which means a fresh clone opens with no selectable scheme and an unresolved dependency. Everything here is either in the file or resolved from GitHub. *Rejected:* generating the project with XcodeGen or Tuist. Both are better for a real app, and both add a toolchain a reviewer would have to install before they could open the thing — which defeats the point of a demo.

**CI compiles for `generic/platform=iOS Simulator`, never a named device.** Pinning to `name=iPhone 16,OS=latest` ties the job to whichever simulator *runtimes* happen to be installed on that day's runner image, and they are not guaranteed. A compile-only check needs no device to exist. *Rejected:* booting a simulator in CI and running a UI test. That would be genuinely stronger evidence, and it triples the job's runtime and makes it fail on runner-image changes that have nothing to do with this code — a red X a reviewer reads as "broken" is worse than an honest compile-only green.

## Screenshots

**There are none, and this section exists to say so rather than to imply otherwise.**

The run that produced this repository attempted to open the project in Xcode and run it on a Simulator three times. Computer-use access was refused each time, verbatim:

> Computer-use access to "Xcode 26.3", "Simulator" can't be approved during a scheduled run. To grant it, send a message in this conversation (the approval card will appear), or add the app to the scheduled task's settings. (Retrying returns this same result.)

There is deliberately no `Demo/Screenshots/` directory. No image of this app exists in this repository.

## What was verified, and what was not

Stated separately, because "it builds for a Simulator" and "it ran on a Simulator" are different claims and only one of them is true here.

**Observed directly:**

- The library compiles clean and its tests pass. `swift build -Xswiftc -warnings-as-errors` from a clean `.build` on Swift 6.0.3 (Linux, aarch64) succeeded with zero warnings; `swift test` reported **110 tests, 0 failures**.
- The app's own configuration code — the whole of `CompiledInConfiguration`, verbatim — was compiled against the library and executed on Linux. `DocumentValidator` reported **zero defects** on the bundled document, and the ramp produced 0 / 72 / 370 / 739 treated devices at 0% / 10% / 50% / 100%, with the treatment confined to the two trains the rules name.
- `Demo.xcodeproj/project.pbxproj` was checked for balanced braces and parentheses and for dangling object references: 22 object ids defined, 22 referenced, none dangling. The shared scheme's `BlueprintIdentifier` matches the real target id.

**Delegated to CI, whose results are public rather than asserted here:**

- The macOS job resolves the **remote** package from GitHub at the pinned version, prints the resolved version, and then builds the `Demo` scheme for a generic iOS Simulator destination. That is the closest available substitute for a human opening the project. Its outcome is on the [Actions tab](https://github.com/rajatslakhina/fleet-rollout-kit-demo-app/actions) — read it there rather than taking this file's word for it.

**Not verified at all:**

- The app was never launched. No Simulator ran it, no UI was observed, and no interaction was exercised at runtime. The behaviour described in the interaction table above is traced from the source and from the Linux run of the configuration code, not from a recording.

## How to run it

```bash
git clone https://github.com/rajatslakhina/fleet-rollout-kit-demo-app.git
cd fleet-rollout-kit-demo-app
open Demo.xcodeproj
```

Then: select the **Demo** scheme (it is committed as a shared scheme, so it appears on a fresh clone), pick any iOS Simulator, and press **Build & Run**. Xcode resolves `fleet-rollout-kit` from GitHub on first open — no local checkout of the library is needed, and none is referenced.

Requires Xcode 16 or later (Swift 6, iOS 17 deployment target).

## Project layout

```
Demo.xcodeproj/
  project.pbxproj                       # hand-written; XCRemoteSwiftPackageReference, upToNextMajorVersion from 1.1.0
  xcshareddata/xcschemes/Demo.xcscheme  # shared, so the scheme exists on a fresh clone
Demo/
  DemoApp.swift                         # @main App + the app-owned compiled-in configuration
.github/workflows/ci.yml                # resolve the remote package, then compile for iOS Simulator
```

## The library

[rajatslakhina/fleet-rollout-kit](https://github.com/rajatslakhina/fleet-rollout-kit) — identity-based OS train targeting, a monotonic version floor that stops a stale CDN edge resurrecting a killed flag, deterministic sticky bucketing with a cross-process stability check, and a measured kill-switch propagation SLO.

## License

MIT
