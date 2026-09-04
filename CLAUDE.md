# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Governing documents

`Docs/ARCHITECTURE.md` and `Docs/DEVELOPMENT.md` are the source of truth for architecture and
workflow. This file condenses their load-bearing rules. **If anything here conflicts with those
two files, the docs win.**

## Project overview

**Tycoon Orbital** — a Roblox tycoon game where players build orbital stations on a grid, with
production simulation (power/heat/resources), an onboarding objective chain, and a rebirth
(prestige) system. The codebase was fully migrated to a hexagonal (ports & adapters) architecture
under `src/`, synced to Studio via Rojo. The migration is complete — all new work is ordinary
feature work on top of this architecture.

## Commands

| Command                       | Effect                                                           |
| ----------------------------- | ---------------------------------------------------------------- |
| `./scripts/test.ps1`          | Run the whole Lune test suite                                    |
| `./scripts/test.ps1 <filter>` | Run only specs whose path contains the filter                    |
| `./scripts/check.ps1`         | Format + lint + Rojo build + tests — **run before every commit** |
| `./scripts/check.ps1 -Fix`    | Auto-format instead of just checking                             |
| `./scripts/serve.ps1`         | Serve the project to Roblox Studio (Rojo Connect)                |
| `./scripts/setup.ps1`         | Install tools (Rojo/Lune/Selene/StyLua) into `.tools/`           |

Tools are pinned in `rokit.toml`. `setup.ps1` downloads them into `.tools/` (git-ignored) without
requiring Rokit itself.

## Architecture (hexagonal / ports & adapters)

Game rules depend on no Roblox API — testable from a command line in milliseconds.

| Layer         | May depend on                                    | Never knows about            |
| ------------- | ------------------------------------------------ | ---------------------------- |
| `Domain`      | nothing                                          | Roblox, network, persistence |
| `Application` | `Domain`, ports                                  | Roblox, instances            |
| `Adapters`    | `Domain`, ports, Roblox                          | the use cases                |
| `Composition` | everything                                       | —                            |
| `Client`      | `Domain` (read only), `Balance`, network contract| server logic                 |

Enforced by: `grep -r "game:GetService" src/Shared/Domain` and
`grep -r "Instance.new" src/Server/Application` must return nothing.

### Source layout

```
src/
├─ Shared/                     → ReplicatedStorage.Shared
│  ├─ Domain/                  Pure rules (tested), one folder per subject
│  │  ├─ Economy/              Credits
│  │  ├─ Grid/                 Grid maths
│  │  ├─ Objectives/           Onboarding chain + completion checks
│  │  ├─ Plots/                Plot fan-layout maths
│  │  ├─ Production/           Orbit sunlight curve, simulation tick
│  │  ├─ Profile/              Persisted entity + sanitization
│  │  ├─ Rebirth/              Prestige rules (canRebirth, multiplier)
│  │  ├─ Station/              ModuleCatalog, Placement, Network (BFS)
│  │  └─ Support/              Result, Format
│  ├─ Balance.luau             The ONLY source of balancing constants
│  ├─ Icons.luau               Icon-id lookup table
│  ├─ Net.luau                 Shared network contract (RemoteFunctions/Events)
│  └─ Signal.luau              Minimal synchronous pub/sub
├─ Server/                     → ServerScriptService.Server
│  ├─ Application/
│  │  ├─ Ports.luau            Port contracts as types
│  │  ├─ SessionRegistry.luau  Volatile per-session state (never persisted)
│  │  ├─ Snapshot.luau         Attribute-compatible presentation model
│  │  ├─ StationProfileSync.luau  Sync station ↔ profile.modules
│  │  └─ UseCases/             One file each (the list IS the documentation)
│  ├─ Adapters/
│  │  ├─ Persistence/          DataStoreProfileRepository, InMemoryProfileRepository,
│  │  │                        InMemoryStationRepository
│  │  ├─ Replication/          AttributeStatsPublisher, RemoteNotifier
│  │  └─ Roblox/               StationSceneBuilder, CharacterTeleporter, SystemClock
│  ├─ Composition/
│  │  ├─ Container.luau        The ONLY assembly point
│  │  ├─ RemoteBindings.luau   Result→tuple, Player→userId
│  │  └─ Bootstrap.luau        Wiring, loops, PlayerAdded/Removing
│  └─ Bootstrap.server.luau    Entry-point Script (requires Composition/Bootstrap)
└─ Client/                     → StarterPlayerScripts.Client
   ├─ State.luau               Reads replicated attributes + Net.Notify → Signal
   ├─ Controllers/             HudController, BuildController, ObjectiveController,
   │                           LabelController, DevController
   ├─ UI/                      Theme, BuildPanel, DevPanel, GainFeed,
   │                           MissionComplete, ModuleVisuals
   └─ Bootstrap.client.luau    Entry-point LocalScript
```

**Note:** `Balance.luau` lives directly under `src/Shared/`, NOT in a `Config/` subfolder.
Don't recreate `Shared/Config/`.

### Ports

Declared in `Application/Ports.luau`, each implemented once for production and once as a test
double (`tests/fakes.luau`):

`ProfileRepository`, `StationRepository`, `StatsPublisher`, `Notifier`, `SceneBuilder`,
`Teleporter`, `Clock` (two clocks: absolute epoch + monotonic session).

`InMemoryStationRepository` is the **real production adapter**, not just a test fake — station
grid data was always session-only (only `profile.modules` survives disconnection).

### Container

`Composition/Container.luau` is the only file that assembles use cases. Key details:
- Dependencies cloned per use case (`setmetatable(table.clone(deps), UseCase)`)
- Config passed as argument (tests pass their own fixtures)
- `container.development` flag (from `RunService:IsStudio()`) gates dev-only use cases
- Dev use cases (`devSetPass`, `devSetRebirths`, `devSetUnlimitedMoney`, `devResetAll`,
  `devGiveCredits`) only exist when `development = true`

## Critical rules and pitfalls

### Cross-service requires

Relative string-requires work within a single Rojo service but **never across service
boundaries** (Server↔Shared, Client↔Shared). Every cross-service require uses a per-file
`fromShared` helper:

```lua
local function fromShared(path: string): any
    if game then
        local node: any = (game :: any):GetService("ReplicatedStorage").Shared
        for segment in path:gmatch("[^/]+") do
            node = node[segment]
        end
        return node
    end
    return "../../Shared/" .. path  -- adjust depth per file
end
-- Usage: require(fromShared("Domain/Economy/Credits"))
```

This is duplicated per-file on purpose. Same-service requires use plain relative strings.

### Domain purity

- **No Roblox datatypes** (`Vector3`, `Color3`, `CFrame`, `Enum.*`) in `Domain/` or
  `Balance.luau` — they crash Lune. Use plain `{X=, Y=, Z=}` tables, convert in Adapters/Client.
- **Domain takes config as parameters**, never `require`s `Balance.luau` itself. Callers pass a
  small `Rules` table. This is what makes domain specs use fixtures instead of production numbers.
- Domain modules may require other Domain modules directly (the "no dependencies" rule is about
  Roblox/persistence, not Domain-internal composition).

### Profile and station data

- `StationProfileSync.apply(profile, station.placements)` must be called **after** any in-place
  mutation of a placement (e.g. `UpgradeModule` bumping `level`), not before — the profile holds
  independent `{id,x,y,r,lv}` copies.
- `RestoreStation` replays `profile.modules` into the in-memory station + scene on first embark
  per session (gated by `SessionRegistry:hasRestored`).
- `RunProductionTick` updates credits in-memory only (no `save()`); persistence is handled by the
  autosave loop (`Balance.Save.AutosaveInterval`) + `PlayerRemoving` + immediate saves on
  explicit player actions.
- A failed profile load marks the session unsaveable — never overwrite a save with blank data.

### Upgrade rules

- Max level is 10 (`Balance.Upgrade.MaxLevel`).
- **No module may exceed the core's current level** — the core paces progression.
- The core has a flat dedicated cost (`Balance.Upgrade.CoreUpgradeCost = 375`), not the generic
  formula.
- `levelMultiplier` scales only what a module PRODUCES (power output, capacity, flow rate), never
  what it CONSUMES (power draw, heat).

### Rebirth (prestige)

- `Balance.Rebirth.enabled` is a kill switch. `+25%` additive per rebirth, `x1.5` for Ultimate.
- Thresholds: core level 10 (or 5 with EarlyRebirth pass).
- Resets station + credits only, NOT `profile.objective`.
- `profile.rebirths` and `profile.unlocked` (booleans keyed by pass id) are pre-existing profile
  fields.
- `globalBoost` flows through `Simulation.step` at the same three points as `levelMultiplier`.

### Gameplay rule

A **corridor** is walkable but carries nothing; only `carries = true` modules form resource
networks via orthogonal adjacency (BFS in `Domain/Station/Network.luau`). Don't blur this
distinction.

### Rotation

Quarter-turns 0-3, clockwise. `CFrame.Angles(0, -math.rad(90) * rotation, 0)` — negative sign
makes it clockwise from the top-down build camera. `sizeOf` swaps width/depth for odd turns
(1 or 3).

## Testing

Tests run outside Studio via Lune (`./scripts/test.ps1`), in milliseconds.

### Test harness

`tests/harness.luau` eagerly requires `src/Shared/Domain/` + `src/Server/Application/` into
nested tables. `tests/run.luau` installs globals: `Domain`, `Application`, `Config`, `Shared`,
`Server`, `Composition.Container`, `Fakes`.

**Specs must reach code through these globals** (`require(Domain.Economy.Credits)`), never via
their own `require("./relative")` path — that resolves against `tests/`, not the spec file.

To expose a new Roblox-API-free adapter to specs, add it to `harness.luau` by name next to
`Composition.Container`.

### Test conventions

- Domain specs use **fixtures**, never real `Balance` numbers (rebalancing must not break tests).
- A separate spec checks the real config for internal consistency.
- Integration tests mount the real `Container` with fake ports from `tests/fakes.luau`.
- Pin curve intent with fixed reference points, not just arithmetic.
- Every `Simulation.step` call needs `globalBoost = 1` (or the intended value).
- Upgrade integration tests must upgrade the core in lockstep (core-gate rule).

## Workflow conventions

- **Test-first**: spec in `tests/specs/domain/...spec.luau`, then implementation.
- **`PascalCase`** modules, one per file, one table returned.
- **Comments in English**, on the _why_.
- **`Result.ok`/`Result.err`** for business failures; `error()` for programming bugs only.
- **No magic numbers** outside `Balance.luau`.
- **No player-readable strings in views** — text lives in Theme.
- **UI sized in design pixels** for one reference resolution, adapted by a single `UIScale`.
- **Conventional Commits**: `<type>(<scope>): <imperative description>`.
  Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`.
  Scopes: `domain`, `application`, `server`, `client`, `monetization`, `ui`, `build`.
- **`./scripts/check.ps1` must be green before every commit.**

## Structural decisions (don't relitigate)

- Progress measured by the server — never trust a client-reported gain.
- Volatile state never reaches the profile — session registry only.
- State replicates through attributes, not RemoteEvents.
- Comfort is client, authority is server (per action, not globally).
- Movement speed bounded regardless of displayed number (tunnelling prevention).
- Every reward takes one path: credit → republish → notify → save.
- Dev-only affordances take the real pipeline path, gated structurally by `development` mode.
- Resource sell values are the originals (5/22/75) — don't reintroduce x10 without being asked.

## Rojo / Studio notes

- `default.project.json` maps `src/Shared`, `src/Server`, `src/Client` only — never `Workspace`
  or `ReplicatedStorage` at the root.
- `.server.luau` / `.client.luau` suffixes make Rojo sync as Script / LocalScript.
- Scene contract in `Workspace`: `Scenery/Lobby/{LobbySpawn, LaunchPad}`, `Plots/`, `Stations/`.
- Module templates live in `ReplicatedStorage.ModuleModels.<id>` (rotation 0, centered, base at
  y=0, no `PrimaryPart`).
- The DataModel's internal name is "Horreur cooperative" (stale placeholder, not a different
  project).
- `ReplicatedStorage.Remotes` is an orphaned legacy folder (harmless).
