# ShadeTap fork of GameCenterKit

This repository is ShadeTap's public fork of
[`keremvatandas/godot-ios-gamecenter`](https://github.com/keremvatandas/godot-ios-gamecenter)
(GameCenterKit, an Apple Game Center bridge for Godot). It pins the bridge for ShadeTap's
games and adds ShadeTap's own documentation (this file) and one GDScript wrapper
(`shadetap/game_center_service.gd`). The upstream `README.md` is unchanged except for one
line near its top that points here.

## What this fork is

- A pinned copy of upstream **v1.0.1**, the tag at commit
  `65274996c3cb8a432947faed155713df94d2e5fe`.
- The pinned build is the release asset `gamecenter-addon.zip` of the release `v1.0.1` of
  this fork, SHA-256
  `b27db4e3192d6fa07ec33b6af8d109d6ee4dab5a0b4b0895d23dd5f26e50b92f`.
- No changes to the bridge so far: `src/`, `SConstruct`, `tools/`, `tests/`, the example
  project and the CI workflow are upstream's.
- Licence: MIT, as upstream (see `LICENSE`); the release package also carries the MIT
  notice of the statically linked `godot-cpp`.

## Why this bridge

Facts measured on the v1.0.1 iOS binary and the sources:

- It references only GameKit, UIKit and Foundation.
- Minimum iOS 14.0 (`IOS_MIN_VERSION` in `tools/build_xcframework.sh`).
- Small: about 530 lines of C++/Objective-C++ in `src/` (`src/game_center_kit.mm` is 384 of them).
- It ships as a prebuilt static xcframework, so it is not rebuilt for every Godot version.
  The extension declares `compatibility_minimum = "4.5"`.

## Bridge contract

The bridge registers one `Engine` singleton, `GameCenterKit`
(`src/register_types.cpp`). Check `Engine.has_singleton("GameCenterKit")` before using it;
the singleton is absent where no binary is declared. All calls belong on the Godot main
thread; results come back as deferred signals.

Methods (registered in `GameCenterKit::_bind_methods`, `src/game_center_kit.mm`):

| Method | Arguments |
| --- | --- |
| `authenticate()` | none |
| `is_authenticated()` | none, returns `bool` |
| `player_display_name()` | none, returns `String` |
| `submit_score(leaderboard_id, score)` | `String`, `int` |
| `show_leaderboard(leaderboard_id)` | `String` |
| `report_achievement(achievement_id, percent)` | `String`, `float` (0 through 100) |
| `show_achievements()` | none |
| `set_access_point_visible(visible)` | `bool` |

Signals:

| Signal | Arguments |
| --- | --- |
| `authenticated` | `ok: bool, error: String` |
| `score_submitted` | `ok: bool, leaderboard_id: String, error: String` |
| `achievement_reported` | `ok: bool, achievement_id: String, error: String` |
| `panel_closed` | `panel: String` |
| `panel_failed` | `panel: String, error: String` |

Not in the bridge (upstream README, "Scope and alternatives"): saved games, friends,
challenges, leaderboard queries, matchmaking, multiplayer and turn-based matches.

## The wrapper: `shadetap/game_center_service.gd`

`GameCenterService` (a `RefCounted`) sits between a game and the bridge. The game says
what Game Center should show, as scores and achievement percents by component ID; the
service signs the player in, sends what is new and opens the system panels. It knows
nothing about any game, so every game uses the same file.

Public surface:

- `GameCenterService.bridge()` (static): the `GameCenterKit` singleton, or `null` when it
  is not present.
- `GameCenterService.new(backend)`: the backend is injected. Pass the bridge, `null`
  (no Game Center) or a test double that has the bridge's methods and signals.
- `available() -> bool`: whether a backend is present.
- `start()`: signs in, once per launch; later sign-ins and account switches arrive through
  the same `authenticated` signal.
- `sync(desired: Dictionary)`: `desired` is
  `{"scores": {id: int}, "achievements": {id: percent 0..100}}`.
- `open_achievements() -> bool` and `open_leaderboard(id: String) -> bool`: open the system
  panels; they return `false` without Game Center or before sign-in, and the caller decides
  what to show.
- `signed_in: bool` and the signal `state_changed`, emitted when `signed_in` changes.
- `trace: Callable`: optional debug hook, called as `trace.call(event, details)`. The
  service itself prints nothing.

Rules:

- It sends only what is new: a score or percent goes out only when it is above the value
  already sent in this session, and zero is never sent.
- It keeps its record of what was sent in memory only.
- A failed send is dropped from the record, so the next `sync` repeats it. There are no
  timers, retries or queues.
- Every sign-in (the first, a later one, another account) clears the record and sends the
  whole wanted state again; a refusal, cancel or offline result only marks the player as
  signed out.
- Without the bridge it does nothing.
- It shows no UI of its own.

A game carries an unchanged copy of this file. Changes are made here first and then copied
into the games.

## Connecting a ShadeTap game

1. **Describe the components once**, in a data file: leaderboards and achievements with
   permanent keys, rule kinds, thresholds, points and localized texts. This file is the only
   description of the components.
2. **Write one pure function** from the game's save to
   `{"scores": {...}, "achievements": {...}}`, keyed by component ID. It reads the save and
   the data file and makes no calls to Game Center.
3. **Copy the wrapper unchanged** and create it with
   `GameCenterService.new(GameCenterService.bridge())`. Call `start()` once after the first
   window exists, and call `sync(...)` with the function's result after sign-in and after
   every change of the save that matters.
4. **Give the player an entry to the system panel** from the game's settings, through
   `open_achievements()` and `open_leaderboard(id)`. When they return `false`, show a quiet
   hint instead of an error.
5. **The build.** The ShadeTap release toolchain
   ([`ShadeTap/game-release`](https://github.com/ShadeTap/game-release)) is meant to turn on
   the `com.apple.developer.game-center` entitlement and to place this pinned release into
   the build. This part is being implemented in the toolchain and is not done yet; see
   <https://github.com/ShadeTap/game-release/issues/78>.
6. **Create the components in App Store Connect** by the toolchain's guide. The IDs, and
   the points of an achievement once it is live, never change afterwards.

## Principles

- The game never waits for Game Center; it works fully without it.
- The save format does not change for Game Center.
- One description of the components.
- Test the pure function and the wrapper on any platform with a recording fake backend;
  test GameKit itself only on a device.

## Rebuilding the bridge

Requirements, as the repository's own scripts and CI define them:

- macOS with Xcode. CI builds on `macos-15-intel` with
  `DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer`.
- SCons (CI: `pipx install scons`), Bash, Python 3 and `ripgrep`.
- The `godot-cpp` submodule (`.gitmodules`: branch `4.5`; pinned at commit
  `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`). The README says the release is built against
  `godot-cpp` `godot-4.5-stable`.

Sequence (upstream README and `.github/workflows/build.yml`):

```bash
git clone --recurse-submodules https://github.com/ShadeTap/godot-ios-gamecenter.git
cd godot-ios-gamecenter
tools/run_cpp_tests.sh
tools/build_xcframework.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
tools/package_addon.sh
```

`tools/build_xcframework.sh` builds the iOS device and simulator static libraries (minimum
iOS 14.0) and the macOS 11.0 editor libraries with SCons, merges `godot-cpp` into the
static libraries with `libtool` and creates `libgamecenter.ios.xcframework` in
`example/addons/gamecenter/bin/`. `tools/package_addon.sh` writes `dist/gamecenter-addon.zip`.

Every change to the bridge is a new release of this fork with a new checksum, and the games
that pin it are updated to that release.

## Not verified yet

- The iOS export with Godot 4.7.2. Upstream CI exports iOS projects with Godot 4.5.2 only
  and loads the add-on in both 4.5.2 and 4.7.2.
- The panels on iOS 26: they use `GKGameCenterViewController`, which is deprecated there.
- Whether a privacy manifest is needed.
