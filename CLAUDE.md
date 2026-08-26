# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Governing documents — read first, they are law

`Docs/ARCHITECTURE.md` and `Docs/DEVELOPMENT.md` define a **mandatory** target architecture
and workflow for this project. They are the source of truth; this file only condenses their
load-bearing rules so routine work doesn't require re-opening them. **If anything below ever
conflicts with those two files, the docs win — re-read them.** Every new line of game-logic
code from this point on must be written to fit this architecture, not the legacy shape
described later in this file.

## Migration status (read this before doing anything)

**The migration is complete.** The live Studio place now runs entirely on the `src/` tree via
Rojo Connect — the legacy `ServerScriptService.Server.Systems`/`Client.Bootstrap`/
`ReplicatedStorage.Shared.{Config,Remotes,Grid,ModuleCatalog,Objectives}` are gone, replaced by
the ported architecture, confirmed working end-to-end in Play mode (profile load, HUD, build
menu, embark, all verified live — see Stage 8 below). New work from here on is ordinary feature
work on top of this architecture, not migration. Concretely, as things stand:

**Done (Stage 1 — tooling, Profile, Economy):**

- Full local toolchain installed and working: `rokit.toml` pins `rojo 7.5.1`, `lune 0.9.3`,
  `selene 0.31.0`, `stylua 2.5.2`; `scripts/setup.ps1` downloads them straight from GitHub
  Releases into `.tools/` (git-ignored) without requiring Rokit itself to be installed — see
  that script for the exact per-tool asset-name/tag-prefix quirks (selene has no `v` tag
  prefix and writes `roblox.yml` itself rather than to stdout, etc.).
- `default.project.json` maps only `src/Shared → ReplicatedStorage.Shared`,
  `src/Server → ServerScriptService.Server`, `src/Client → StarterPlayer.StarterPlayerScripts.
Client` — deliberately never `Workspace` or `ReplicatedStorage` at the root, so a future
  `rojo serve` cannot delete `ModuleModels`/`Assets`/the runtime `Remotes` folder.
  `scripts/{setup,test,check,serve}.ps1` all exist and work; `./scripts/check.ps1` (format +
  lint + `rojo build` + tests) is green.
- `Profile` and `Economy`: `src/Shared/Domain/{Support/Result,Profile/Profile,
Economy/Credits}.luau`, `src/Server/Application/UseCases/{SpendCredits,AddCredits}.luau`,
  `src/Server/Adapters/{Persistence/{DataStoreProfileRepository,InMemoryProfileRepository},
Roblox/SystemClock}.luau`.

**Done (Stage 2 — Grid, module catalogue, station placement/upgrade rules):**

- `src/Shared/Domain/Grid/Grid.luau` — pure grid maths, no `fromWorld` (that one is inherently
  CFrame-based, stays a future Client Adapter concern).
- `src/Shared/Domain/Station/{ModuleCatalog,Placement}.luau` — the full 10-module catalogue
  (gameplay numbers only, see below), `sizeOf`/`levelMultiplier`/`upgradeCost`/`isUpgradable`,
  and `canPlace`/`canRemove`/`initial` (the grid/occupancy/uniqueness/adjacency rules, ported
  from `StationService:Place`/`:Remove`/`:EnsureStation`'s initial free core placement).
- `src/Server/Application/UseCases/{PlaceModule,RemoveModule,UpgradeModule}.luau` +
  `src/Server/Application/StationProfileSync.luau` (shared sync helper — see pitfall below) +
  `src/Server/Adapters/Persistence/InMemoryStationRepository.luau` (the **real** production
  adapter for station state, not just a test fallback — see below).
- `Ports.StationRepository` added; `Composition/Container.luau` now takes a second `rules`
  argument (`grid`, `refundRatio`, `upgrade`) alongside `ports`, and builds 5 use cases.
  `Bootstrap.luau` wires `InMemoryStationRepository` for real, not `DataStore` — see next point.
- 64 Lune specs pass under `tests/specs/{domain,application,config}/`.
- **Still not wired into the live Studio place** (Studio confirmed unchanged before/after, via
  `get_studio_state`); still no 3D geometry, no scene, no `PlotService` port — see "Not done
  yet" below.

**Done (Stage 3 — production simulation, objective chain):**

- `src/Shared/Domain/Station/Network.luau` — resource-network connectivity (BFS over
  `carries`-flagged adjacency), moved to sit with the other Station rules since both Production
  and Objectives need it, not just Production.
- `src/Shared/Domain/Production/{Orbit,Simulation}.luau` — the orbital sunlight curve and the
  full power/heat/resource-flow tick, ported from `ProductionService:GetSunlight`/`:_step`.
  Pure: takes `station`/`sunlight`/`charge`/`pendingCredit`/rules in, hands new values back,
  owns no state itself.
- `src/Shared/Domain/Objectives/{Objectives,Checks}.luau` — the chain's text/rewards and its 5
  station-based completion predicates. **`Checks` deliberately excludes "Embark"** — see the
  SessionRegistry point below.
- `src/Server/Application/SessionRegistry.luau` (new, not a port — see ARCHITECTURE.md's
  "volatile state never reaches the profile"; holds per-tick charge/pendingCredit and
  per-session "has embarked") + `UseCases/{EmbarkStation,RunProductionTick,
CheckObjectiveProgress}.luau`.
- `Ports.Clock` extended with `monotonic()` (backed by `os.clock()` in `SystemClock`, alongside
  the existing epoch `now()`/`os.time()`) — the orbital phase needed the second of
  ARCHITECTURE.md's "two clocks", the first Stage to actually need it.
  `Composition/Container.luau` now also takes a `sessionRegistry` argument (shared mutable
  state several use cases must operate on the same instance of, handed in like ports rather
  than constructed internally) and a bigger `rules` (`orbit`, `heat`, `resourceValues` added).
- 106 Lune specs pass under `tests/specs/{domain,application,config}/`. Studio was not
  connected to check at the end of this stage (the user had stepped away and closed it) — not a
  concern, this stage never touches it either.

**Done (Stage 4 — Replication: attributes + notifications):**

- Scoped down from the original "3D + Replication" plan for this stage: Studio had zero
  connected instances the whole time (`list_roblox_studios` returned `[]`), so the 3D
  scene-building work (which needs the real `ModuleModels` templates to build against and Play
  mode to verify in) is pushed to Stage 5, when Studio is available again — see "Not done yet".
- **Key reframe that shrank this stage's real scope:** a placed module's data (id/x/y/rotation/
  level) does NOT need custom replication once Stage 5 makes it a real Instance — ordinary
  Roblox instance replication already carries it to the client for free (this is how
  `LabelController` already works client-side today, watching `Workspace.Stations.*` for new
  children). Only _scalar_ state (credits, objective index, production stats, location) needed
  an explicit port — that's all this stage builds.
- `src/Server/Application/Snapshot.luau` (new — matches ARCHITECTURE.md's named `Snapshot` file
  exactly): one small builder function per concern (`credits`/`objective`/`location`/
  `production`), not one monolithic table — a use case publishes only the handful of fields it
  just changed, since `SetAttribute` on one key never touches another. Everything returned is
  attribute-compatible (numbers/strings only).
- `Ports.StatsPublisher` (state; production adapter `Adapters/Replication/
AttributeStatsPublisher.luau` calls `Player:SetAttribute`) and `Ports.Notifier` (one-off
  messages; production adapter `Adapters/Replication/RemoteNotifier.luau` — since
  `Net.luau`/`RemoteBindings` doesn't exist yet, this adapter creates and owns its own
  `ReplicatedStorage.Replication.Notify` RemoteEvent itself, mirroring how the legacy
  `Shared/Remotes.lua` self-creates remotes; a real shared contract can replace this later
  without touching any use case). Test doubles `RecordingStatsPublisher`/`RecordingNotifier`
  live in `tests/fakes.luau`, **not** under `src/Server/Adapters/` — unlike
  `InMemoryStationRepository`, there is no legitimate production use for either, so they don't
  get the "real adapter that doubles as a fake" treatment Stage 2 established.
- Every use case that changes state now publishes/notifies: `SpendCredits`/`AddCredits`/
  `PlaceModule`/`RemoveModule`/`UpgradeModule` publish `Credits`; `PlaceModule` also notifies
  `Power`/`Storage`/`Cooling` gains on a paid placement (ported from
  `StationService:_announceGains`); `EmbarkStation` publishes `Location`; `RunProductionTick`
  publishes the full production snapshot every tick; `CheckObjectiveProgress` publishes
  `Objective` and notifies `ObjectiveCompleted`. **Deliberately NOT reproduced:** legacy's
  ~1s gain-batching for the credits "+150" popup (`EconomyService`'s `_gains` table) — that
  needs a real recurring loop to flush into, which doesn't exist until Stage 5's live loop does;
  `AddCredits` publishes the new balance immediately instead, with no popup, for now.
- `Ports.StatsPublisher`/`Ports.Notifier` added to `Container.Ports`; every use case's
  dependency table extended accordingly. 115 Lune specs pass, including a new
  `tests/specs/application/snapshot.spec.luau` and gain-notification/publish assertions folded
  into the existing station/production integration specs.

**Done (Stage 5 — 3D scene building):**

- `src/Shared/Domain/Plots/Layout.luau` — the plot fan-layout maths (pure, plain `{x,y,z}`
  positions, ported from `PlotService:Start()`'s loop), Lune-tested with pinned reference
  points (`spread = 0` collapses every angle to 0, giving exact literal values without needing
  to hand-compute trig).
- `src/Server/Adapters/Roblox/StationSceneBuilder.luau` — merges what were two legacy systems
  (`PlotService`'s deck/rim/keel/wings structure building, `StationService.buildModel`'s
  template cloning) into one adapter, because placing a module needs the origin of an
  already-claimed plot. Owns state Domain deliberately doesn't (which slot each user owns,
  which Instance backs each placement — `ModulePlacement` still has no Model field). Per
  ARCHITECTURE.md adapters aren't Lune-covered, so this one was instead **hand-verified against
  the live place via `execute_luau`** before being written: cloned real `ModuleModels`
  templates and confirmed the pivot math matches `Grid.offset`, then separately ran the full
  deck/rim/keel/wings builder (126 parts, no errors) — both throwaway, destroyed immediately,
  nothing left in the place.
- `Ports.SceneBuilder` (`claimPlot`/`releasePlot`/`placeModule`/`removeModule`/
  `setModuleLevel`) wired into `PlaceModule`/`RemoveModule`/`UpgradeModule`/`EmbarkStation`.
  `EmbarkStation` now returns a `Result` (can fail: "every station is occupied", matching
  legacy) instead of always succeeding. New `ReturnToLobby` use case (publishes `Location =
"Lobby"` only — ported faithfully from the legacy remote, which does **not** release the
  plot; only a `PlayerRemoving` teardown does, and that wiring still doesn't exist — see below).
- `Composition/Bootstrap.luau` now also schedules the recurring simulation tick (`task.spawn`
  loop calling `runProductionTick`/`checkObjectiveProgress` for every connected player every
  `Config.Simulation.TickRate`, pcall'd per player like the legacy loop) — cheap, mechanical,
  no dedicated live verification needed beyond the use cases it calls already having their own.
- **Still NOT connected via Rojo, still not wired into the live Studio place.**
- 123 Lune specs pass, including a new `tests/specs/domain/plots/layout.spec.luau` and
  `SceneBuilder`-wiring assertions (using the new `Fakes.RecordingSceneBuilder`, which is
  test-only for the same reason `RecordingStatsPublisher`/`RecordingNotifier` are) folded into
  the station/production integration specs.

**Done (between Stage 5 and 6 — resolved the `Config` name collision noted above):**
`src/Shared/Config/Balance.luau` moved to **`src/Shared/Balance.luau`** — no more `Config/`
folder under `src/Shared` at all, so a future `rojo serve` will sync a `Balance` ModuleScript
directly under `ReplicatedStorage.Shared`, never touching the legacy `ReplicatedStorage.Shared
.Config` ModuleScript's name. The Lune harness's `Config` global now aliases `Shared.Balance`
directly (`require(Config)`, not `require(Config.Balance)` — see `tests/harness.luau` and
`tests/specs/config/balance.spec.luau`). This was a deliberate, user-approved rename, not
something to "fix" later — don't recreate a `Shared/Config/` folder.

**Done (Stage 6, server-networking half only — the client is still open):**

- `src/Shared/Net.luau` — the shared network contract; ported from the legacy
  `Shared/Remotes.lua`'s self-creating pattern almost verbatim, just renamed and under
  `ReplicatedStorage.Net` instead of `.Remotes` (so it coexists with the untouched legacy
  folder during the migration — confirmed live via `execute_luau`, no collision, nothing left
  behind). Four `RemoteFunction`s (`PlaceModule`/`RemoveModule`/`UpgradeModule`/
  `ReturnToLobby`) plus the `Notify` `RemoteEvent`. `Adapters/Replication/RemoteNotifier.luau`
  was updated to fire `Net.Notify` instead of the ad-hoc `Replication.Notify` folder it
  created for itself in Stage 4 — that stopgap is gone now that a real contract exists.
- `src/Server/Composition/RemoteBindings.luau` — the only place a use case's `Result<T, E>`
  becomes the `(ok, valueOrError)` tuple shape a `RemoteFunction` actually returns, and the
  only place a `Player` gets reduced to the `userId` every use case takes. Wired into
  `Bootstrap.start()` via `RemoteBindings.bind(container)`.
- **Decided:** the credits-gain immediate-publish behavior from Stage 4 (no "+150" popup
  batching) is the permanent design, not a placeholder — see the dedicated note below. Don't
  reintroduce batching later without being asked.
- 123 Lune specs still pass with just the networking half above (no new Domain/Application code
  in it — `Net.luau` and `RemoteBindings.luau` are both Composition/Adapter-layer,
  Roblox-touching, and correctly excluded from the Lune harness the same way `Server/Adapters`
  already was; `harness.luau`'s walk of `src/Shared` was narrowed to just `Domain/` + an
  explicit `Balance` require so it doesn't also try to eagerly `require()` the new `Net.luau`
  and crash on `game:GetService`).

**Done (rest of Stage 6's server side — `Teleporter` + Lobby wiring, in a follow-up pass):**

- `Ports.Teleporter` (`sendToLobby`/`sendToStation` — deliberately just two named actions, not
  a generic "go to this CFrame": Application never has a CFrame to hand it) +
  `Adapters/Roblox/CharacterTeleporter.luau`, ported from the teleport half of legacy
  `LobbyService:Send`/`StationService:SendToStation` (claiming the plot itself stays
  `StationSceneBuilder`'s job).
- `StationSceneBuilder` extended: `claimPlot` now also creates a `StationSpawn`
  `SpawnLocation` inside the station folder (ported from `StationService:EnsureStation`,
  `origin * CFrame.new(0, 1, 22)`), exposed via a new `:spawnLocationFor(userId)` — consumed
  by `CharacterTeleporter`, deliberately **not** added to the formal `Ports.SceneBuilder` type
  (it's an inter-adapter detail, not something Application ever calls).
- `Composition/Bootstrap.luau` now resolves the full legacy Lobby scene contract
  (`Workspace.Scenery.Lobby.{LobbySpawn,LaunchPad}` + its `ProximityPrompt`, same fail-loud
  `expect()` pattern as `LobbyService:_resolve`) — **confirmed live via `inspect_instance`
  against the actual Studio scene, still matches exactly, no drift**. Wires
  `LaunchPad.ProximityPrompt.Triggered → embarkStation:run`, `Players.CharacterAutoLoads =
false` + a `PlayerAdded` welcome (spawn in the lobby), and a `PlayerRemoving` teardown
  (final profile save as a safety net — every mutation already saves immediately, unlike
  legacy's 3-moments-only design — plus `profileRepository:release`/`stationRepository
:release`/`sceneBuilder:releasePlot`/`sessionRegistry:release`). This is the piece that
  makes `EmbarkStation` reachable by a real player, at last.
- `InMemoryStationRepository` gained a `:release(userId)` (was missing since Stage 2).
- 124 Lune specs pass, including `Fakes.RecordingTeleporter` and new assertions on
  `embarkStation`/`returnToLobby` actually calling the teleporter.
- **Still not wired into the live Studio place at this point.** `Bootstrap.start()` was
  complete and correct for everything ported so far, but nothing called it yet — see Stage 7,
  which finished the client that was the last blocker.

**Done (Stage 7 — the Client):**

- Full port of `StarterPlayer.StarterPlayerScripts.Client` into `src/Client`, following
  ARCHITECTURE.md's target layout exactly: `State.luau` (new), `Controllers/
{HudController,BuildController,ObjectiveController,LabelController}.luau`, `UI/
{Theme,BuildPanel,GainFeed,MissionComplete,ModuleVisuals}.luau`, `Bootstrap.client.luau` (the
  `.client.luau` suffix is what makes Rojo sync it as a `LocalScript` — confirmed by the
  `rojo build` in `check.ps1`, which produces exactly one `LocalScript` in the built place).
- `src/Client/State.luau` (new, not in the legacy game at all): the one place that reads
  `LocalPlayer`'s replicated attributes (`Ports.StatsPublisher`'s output) and `Shared/Net.luau`'s
  `Notify` event (`Ports.Notifier`'s output), and turns both into a `Signal`-based subscription
  surface (`State.Changed`, `State.Notified`). Every controller goes through this instead of
  touching `GetAttributeChangedSignal`/`Net.Notify` itself — this is what replaces the legacy
  `CreditsChanged`/`StationStats`/`Gain`/`ObjectiveChanged`/`LocationChanged` RemoteEvents.
  `BuildController` still calls `Net.PlaceModule`/`RemoveModule`/`UpgradeModule`/`ReturnToLobby`
  directly for actions (not state), matching `RemoteBindings.luau`'s contract.
- `src/Shared/Signal.luau` (new): a minimal synchronous pub/sub, no Roblox API, filling in
  ARCHITECTURE.md's target-layout entry for it. Lune-tested
  (`tests/specs/shared/signal.spec.luau`) since it has zero Roblox dependency, even though only
  the Client consumes it today.
- `src/Shared/Icons.luau` (new): the legacy icon-id lookup table, moved as-is — plain
  `rbxassetid://` strings, no Roblox datatypes, so (like `Balance.luau`) it stays loadable under
  Lune even though nothing but the Client reads it.
- `src/Client/UI/ModuleVisuals.luau` (new): the presentation-side module catalogue promised back
  in Stage 2's notes below (`color`/icon per module id, keyed the same as
  `Domain/Station/ModuleCatalog.luau`) — `Color3`/`Enum.Material` are Roblox datatypes, so they
  could never live in the Domain catalogue; this is where they ended up instead, Client-only.
- **A station's placed modules replicate as ordinary Instances, not a snapshot payload — but the
  client still needs each one's x/y/rotation, and nothing was publishing those.** The legacy
  client rebuilt its occupancy map from a `StationChanged` RemoteEvent payload; the new
  architecture deliberately has no equivalent (Stage 4's reframe: a placed module _is_ an
  Instance, ordinary replication carries id/level for free via the `ModuleId`/`Level` attributes
  `StationSceneBuilder` already stamped). But x/y/rotation were never stamped anywhere
  client-readable, and `BuildController` needs them to reconstruct occupancy for its
  (advisory-only, server-revalidated) ghost preview. Fixed by extending
  `StationSceneBuilder:placeModule` to also stamp `X`/`Y`/`Rotation` attributes — small,
  Adapter-layer, not Lune-covered by design, same as `ModuleId`/`Level` already were.
- **`BuildController` also needs its own plot's origin `CFrame`, and nothing exposed one either**
  (the legacy client got it from the same `StationChanged` payload). Fixed by having
  `StationSceneBuilder:claimPlot` stamp the origin directly as a `CFrame`-typed attribute
  (`Origin`) on the `Station_<userId>` folder — `CFrame` is an attribute-compatible engine type,
  so this needed no inverse-transform math or hardcoded offset on the client side, just
  `folder:GetAttribute("Origin")`.
- **A client with the server's Attributes/Notify design has no equivalent of a full initial
  snapshot, and nothing was publishing one.** `RunProductionTick`/`CheckObjectiveProgress` only
  publish `Credits`/`Objective` when they _change_ — a freshly-joined player would read `nil` off
  both attributes until their first sale or objective completion, since nothing publishes the
  loaded profile's starting values. Fixed in `Bootstrap.luau`'s `welcome(player)`: it now loads
  the profile and publishes `Snapshot.credits`/`Snapshot.objective` once, before
  `returnToLobby:run` (which already covered `Location`). This is server-side, Application-layer
  (`Snapshot.luau`), not a Client workaround — the gap was in what gets published, not in how the
  client reads it.
- Legacy's `ModuleCatalog.lua` also carried `icon`/`color`/`category` lookups tightly coupled to
  the gameplay fields Stage 2 already ported into Domain (`Categories`/`Order` stayed in Domain
  since they're not Roblox-typed) — `ModuleVisuals.luau` only holds the two genuinely
  Roblox-typed pieces (`Colors`, keyed the same as Domain's `ModuleCatalog.Modules`) plus the
  icon-id lookups (`Icons`, `CategoryIcons`), reusing Domain's `Categories`/`Order` rather than
  duplicating them.
- One bug fixed while porting, not carried forward: the legacy `Theme.lua`'s `Theme.corner`
  function body had `Theme.gaugePill`'s entire ~90-line definition nested dead-code inside it (a
  copy-paste artifact — Luau allows a nested `function` statement anywhere, so it parsed, but
  `Theme.gaugePill` would only become defined the first time `Theme.corner` was ever _called_,
  not at module load). Fixed by moving `Theme.gaugePill` back out to be its own top-level
  function; `Theme.corner` is back to its actual 3-line body. Everything else in `Theme.luau`
  ported behavior-for-behavior.
- 128 Lune specs pass (124 + 4 new `Signal` specs); `check.ps1` green including a clean
  `rojo build` of the full tree (Shared + Server + the new Client folder) and a clean `selene`
  pass (fixed 8 `UDim2.new(...)` → `fromScale`/`fromOffset` simplification warnings and 8
  `local self = {}` / `function self:Method()` shadowing warnings in the ported `Theme.luau` —
  both pre-existing in the legacy source, never caught before because nothing linted it there).
- Live-verified as part of Stage 8's cutover below, once relative-require resolution across
  service boundaries was fixed — see that stage for what broke and why.

**Done (Stage 8 — the cutover):**

- `rojo serve` connected to the live Studio place via the "Rojo Foundation" Studio plugin (there
  is no separate "rojo-rbx" plugin listing any more — this is the current official one). First
  connection attempt failed with a protocol-version mismatch (`ApiContext:28: attempt to index
number with 'protocolVersion'`) because the pinned CLI was still Rojo 7.5.1 against a materially
  newer plugin — fixed by bumping `rokit.toml`'s pin to **7.7.0** (the actual latest release) and
  re-running `scripts/setup.ps1`; `check.ps1` re-verified green on the new binary before
  reconnecting. **The `rojo-rbx/rojo@7.5.1` pin was stale enough to break the connection outright
  — don't assume a Stage-1 tool pin is still current by the time Rojo is actually connected months
  later; re-check against the latest release first.**
- Reconnecting succeeded and synced correctly: `ReplicatedStorage.Shared` now holds
  `Domain`/`Balance`/`Net`/`Signal`/`Icons` (the legacy `Config`/`Remotes`/`Grid`/`ModuleCatalog`/
  `Objectives` ModuleScripts are gone, replaced in place); `ServerScriptService.Server` now holds
  `Adapters`/`Application`/`Composition` (the legacy `Systems`/`Bootstrap` are gone); `StarterPlayer
.StarterPlayerScripts.Client` now holds `State`/`Controllers`/`UI`/`Bootstrap` (confirmed synced
  as a real `LocalScript`, resolving Stage 1's open question about the `.client.luau`/`.server.luau`
  suffix convention actually working in this engine — it does). `Workspace.Plots`/`Workspace
.Stations`/`Workspace.Scenery.Lobby` were already hand-authored, pre-existing empty scenery (not
  created by legacy scripts at runtime), so `StationSceneBuilder`'s/`Bootstrap`'s `WaitForChild`
  calls resolve immediately rather than hanging.
- **Found and fixed: nothing actually called `Composition/Bootstrap.start()`.** Every file under
  `src/Server` is a `ModuleScript`; unlike the Client (which got `Bootstrap.client.luau` in Stage
  7), the server side never got an equivalent entry-point `Script`. Fixed by adding
  `src/Server/Bootstrap.server.luau` — the only `Script` directly under `ServerScriptService
.Server`, mirroring the legacy `Server.Bootstrap`'s role, requiring `./Composition/Bootstrap` and
  calling `.start()`. This is the piece that makes the whole server side actually run, not just
  compile.
- **Found and fixed: relative string-requires do not cross Rojo's service boundaries.** Confirmed
  live the moment Play mode first ran: `error requiring "../../Shared/Balance": could not resolve
child component "Shared"`. Root cause (this was Stage 1's long-deferred open question, and the
  answer is more specific than "works" or "doesn't"): under Lune, `src/Server` and `src/Shared` are
  siblings on disk, so `require("../../Shared/Balance")` resolves correctly by walking the
  filesystem; but Rojo maps them to **different services** (`ServerScriptService.Server` vs
  `ReplicatedStorage.Shared`), which share `game` as a common ancestor but have no path of `..`
  that reaches between them the way sibling directories do — so the exact same relative-require
  convention that DEVELOPMENT.md mandated, and that worked throughout local Lune testing, cannot
  possibly resolve in the live engine for ANY cross-service require, no matter how many `..` segments
  are used. Same-service relative requires (Domain-internal, Server-internal, Client-internal) DO
  work fine — confirmed by isolating the failure with `execute_luau` probes before touching any
  code, so the fix stayed scoped to only the requires that actually cross a service boundary (~60
  lines across 28 files, every one crossing from `src/Server` or `src/Client` into `src/Shared`).
  **The fix is not a plain `require(script.Parent.Foo)` swap** (CLAUDE.md's originally-guessed
  fallback, written before this was ever tested) **because that would break Lune, which has no
  `script` at all.** Every affected file instead gained a small local `fromShared(path: string)`
  helper:
  ```lua
  local function fromShared(path: string): any
  	if game then
  		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
  		for segment in path:gmatch("[^/]+") do
  			node = node[segment]
  		end
  		return node
  	end
  	return "<the file's original relative prefix, e.g. \"../../../Shared/\">" .. path
  end
  ```
  `require("../../../Shared/Domain/Economy/Credits")` became
  `require(fromShared("Domain/Economy/Credits"))` — `if game then` is false under Lune (no such
  global exists there), so the risky branch never runs there; the fallback branch is the exact
  same string the code always used, so Lune's file-relative resolution is completely unchanged.
  Duplicated per-file rather than centralized into one shared helper module on purpose: a
  centralizing helper would itself need to be required across the same broken boundary, and/or
  would need its own per-file relative-depth calibration to resolve under Lune, buying no real
  simplicity — small deliberate duplication, same tradeoff CLAUDE.md already accepts for the
  quarter-turn rotation formula. **This is the actual, tested fallback going forward: any new
  cross-service require (Server or Client reaching into Shared) must use this pattern, not a bare
  relative string.** Same-tree requires (Domain-internal, same-service Server/Client code) keep
  using plain relative strings — those were confirmed working and don't need it.
  `src/Server/Adapters/Persistence/{InMemoryProfileRepository,InMemoryStationRepository}.luau`
  also picked this up despite their "Roblox-free" framing in their own header comments — that
  framing is still accurate: the `if game then` branch never executes under Lune, so nothing about
  their testability changed.
- **Live-verified end-to-end in Play mode, screenshots taken at each step:** an existing DataStore
  save loaded correctly (a returning profile from legacy play, `Credits = 20137`,
  `Objective = 7` i.e. chain already complete) and published to the client on join; the HUD
  rendered the purse capsule correctly in the lobby; walking onto the launch pad and pressing E
  triggered `EmbarkStation`, teleporting the character onto their claimed plot; the station HUD
  then showed all three gauges (energy/heat/sun) with live values, income, and module count; the
  build menu (`B`) opened showing all 9 buildable modules with correct per-module colors, real 3D
  thumbnails cloned from `ReplicatedStorage.ModuleModels`, an affordability badge, and working
  category tabs. No console errors from game code at any step (one unrelated error from the
  assistant's own diagnostic tooling, not the game, appeared once and was ignored).
- `check.ps1` still green after the whole fix (128 specs, stylua/selene/`rojo build` all clean) —
  the `fromShared` pattern's `if game then` branch is invisible to Lune by construction, so none of
  this touched test behavior.
- **Left as-is, not cleaned up:** `ReplicatedStorage.Remotes` (the legacy self-created remotes
  folder — orphaned now that nothing requires the script that made it, but harmless) and
  `Workspace.Script` (a pre-existing unrelated `print("Hello world!")` placeholder, not part of
  any legacy system this migration touched). Worth a tidy-up pass later; not blocking anything.

**Load-bearing design points, apply them to every later port:**

- **Domain code takes config as parameters, never `require`s `Shared/Balance` itself.**
  `Profile.blank(rules)`/`Profile.sanitize(raw, rules)` take a small `Rules` table; callers
  (Adapters, Composition) read the real `Balance` module and pass it in. This is what makes
  "domain specs use their own fixtures rather than the real configuration" (`DEVELOPMENT.md`)
  possible — a spec passes a tiny fixture `Rules` table instead of depending on production
  numbers. Don't let a new `Domain` module reach for `Shared/Balance` directly.
- **No Roblox datatypes (`Vector3`, `Color3`, `Enum.*`, `CFrame`, ...) in `Shared/Balance` or
  `Shared/Domain`.** They don't exist under Lune (confirmed: `Vector3.new` crashed the test
  harness the first time `Balance.lua` used it for `Lobby.Center`). Store plain
  `{ X = ..., Y = ..., Z = ... }` tables / numbers / strings instead, and convert to a real
  Roblox type only at the Adapter or Client/UI code that actually consumes it. This will matter
  a lot once `ModuleCatalog` (heavy on `Color3.fromRGB`/`Vector2.new`/`Enum.Material`) gets
  ported. Confirmed again in Stage 2: `ModuleCatalog.luau`'s Domain version deliberately drops
  every module's `color`/`material`/icon — those live in the presentation-side catalogue (keyed
  by the same id), `src/Client/UI/ModuleVisuals.luau`, added in Stage 7 when the Client needed
  one.
- **Domain modules may `require` other Domain modules directly** (`Placement.luau` requires
  `Grid.luau` and `ModuleCatalog.luau`) — the "Domain depends on nothing" rule is about
  Roblox/network/persistence, not about Domain-internal composition.
- **A repository whose state the legacy game never durably persisted should stay in-memory in
  production, not just as a test fallback.** `InMemoryStationRepository` backs
  `Ports.StationRepository` in `Bootstrap.luau` for real: the legacy `StationService._stations`
  table was always session-only too (only `profile.modules`, synced on every change, survived a
  disconnect). Don't reach for a `DataStoreStationRepository` that doesn't need to exist.
- **When a Domain object is mutated in place after being copied into a persisted snapshot, the
  snapshot needs re-syncing too, or the mutation is silently lost on save.** Caught in Stage 2:
  `UpgradeModule` bumped `existing.level` in place, but `profile.modules` holds independent
  `{id,x,y,r,lv}` copies (built by `StationProfileSync.apply`, required by all three station use
  cases) — the fix was calling `StationProfileSync.apply(profile, station.placements)` again
  after the mutation, not before. Check this whenever a use case mutates something already
  copied into the profile.
- **A repository that always synthesizes a default value on first load (per Stage 2's own
  pattern above) can quietly erase a real business rule if that rule depended on "this doesn't
  exist yet."** Caught while porting Objectives in Stage 3: `StationRepository:load()` always
  returns a usable station (core included), so `station ~= nil` — the legacy "Embark" check —
  would have been trivially true forever, and the whole point of that objective (the player
  must actually walk onto the launch pad and press E) would have silently stopped being
  checked. Fixed by tracking "has embarked this session" as its own boolean in
  `SessionRegistry`, independent of station data, and having `CheckObjectiveProgress`
  special-case "Embark" against it — same special-casing the legacy `ObjectiveService` did
  ("seul le premier objectif se juge sans station"), just with an explicit flag instead of
  nil-checking a station that, in this architecture, is never actually nil. When porting a rule
  that used to distinguish "doesn't exist yet" from "exists, empty," check whether the new
  repository's always-return-a-default design has quietly collapsed that distinction.
- The Lune test harness (`tests/{testkit,harness,fakes,run}.luau`) is a **deliberate
  simplification** of `ARCHITECTURE.md`'s literal description ("rebuilds the Roblox tree...
  provides `script`, `require` and `game:GetService`") — Lune has no `loadstring`, so a true
  fake-Instance/lazy-require emulation isn't possible. Instead `harness.luau` eagerly
  `require()`s every module under `src/Shared` and `src/Server/Application` (never
  `Server/Adapters` or `Server/Composition` wholesale — most of `Adapters` genuinely touches
  `game:GetService` and would crash Lune) into nested tables, and `run.luau` installs those as
  the globals (`Domain`, `Application`, `Config`, `Shared`, `Server`, `Composition.Container`,
  `Fakes`) plus a shadowed `require` that treats a non-string argument as already-resolved —
  so `require(Domain.Economy.Credits)` (the literal idiom `DEVELOPMENT.md`'s example spec uses)
  still works, it just resolves eagerly. **Specs must reach code through those globals, never
  through their own `require("./relative")` path** — such a path would silently resolve
  against `tests/` (where the shadow's real `require()` call is written), not against the spec
  file itself. If a later stage needs another Roblox-API-free adapter exposed to specs, add it
  to `harness.luau` by name next to `Composition.Container`, the same way.
- **Resolved in Stage 8 (see above):** relative string-requires resolve fine within a single Rojo
  service (Domain-internal, Server-internal, Client-internal) but never across a service boundary
  (Server or Client reaching into Shared) — there is no path of `..` between
  `ServerScriptService.Server` and `ReplicatedStorage.Shared` the way there is between sibling
  directories on disk. Every such require goes through a per-file `fromShared(path)` helper now
  (`if game then` an Instance-based lookup, `else` the original Lune-relative string) — **use that
  pattern for any new cross-service require; a bare relative string will build, pass every Lune
  spec, and then fail only in the live engine.**

**Post-cutover fixes (found by actually playing the live-synced place, not by Lune):**

- **The starting core had grid DATA but no 3D Instance.** `Placement.initial()` (and therefore
  `InMemoryStationRepository:load()`) always includes the core in `station.occupancy`/
  `station.placements`, but nothing ever told `StationSceneBuilder` to build its Model —
  `EmbarkStation` only ever called `claimPlot` (the deck/rim/keel/wings structure), never
  `placeModule` for the core. The core was therefore correctly load-bearing for every
  adjacency/occupancy check, just invisible. Fixed by having `StationSceneBuilder:claimPlot`
  build the core's Instance itself, in the same step it builds the plot structure — matching
  legacy `StationService:EnsureStation`, which did both atomically.
- **The HUD's module counter counted the station's `StationSpawn` as a module,** because
  `StationSceneBuilder` parents it into the same folder as the modules. Surfaced the moment the
  core fix above added a second child to count. Fixed by counting only `Model` instances in
  `HudController`'s `refreshModuleCount`.
- **The big one: a player's built station never survived a server restart.** `profile.modules`
  was written correctly on every place/remove/upgrade (`StationProfileSync.apply`, DataStore-saved
  by the profile use cases) but never READ back — there was no code path that turned a saved
  profile back into a live station. Since station DATA is intentionally memory-only (see
  `InMemoryStationRepository`'s header — this was never meant to change), this meant EVERY server
  restart reset every player's station down to just the core, credits and objective progress
  notwithstanding. This is not a Studio-testing artifact: it reproduces identically for real
  players any time their server instance cycles (not only on a game update — Roblox recycles
  server instances on its own). `PlaceModule.luau`'s own header comment had flagged this as
  deferred ("a separate RestoreStation-style use case, not this one") back when `PlaceModule` was
  first ported, and `Placement.canPlace`'s `free` parameter existed for exactly this purpose from
  the start — neither was ever finished. Fixed by adding
  `Server/Application/UseCases/RestoreStation.luau`: on `EmbarkStation`, once per session (gated
  by a new `SessionRegistry:hasRestored`, mirroring `hasEmbarked` — re-embarking after a lobby
  trip must not replay the save on top of a station the player already has), it loads
  `profile.modules` (via the new inverse mapping `StationProfileSync.restore`, undoing `apply`'s
  id/x/y/r/lv rename), and replays every entry except the core (already placed by `claimPlot`)
  through `Placement.canPlace(..., free = true)` — skipping, not crashing on, any entry that no
  longer fits (a corrupted save, or a module retired from the catalogue since) — into both the
  in-memory station and `sceneBuilder:placeModule`. 6 new Lune specs
  (`tests/specs/application/restore_station.spec.luau`), 134 total, all green.
- **Upgrading a module raised its level (and its cost) without changing a single simulated
  number.** `ModuleCatalog.levelMultiplier` existed and was even documented ("a level-1 module is
  worth EXACTLY its sheet") but nothing in `Simulation.step` ever called it — every power/heat/
  capacity/rate figure came straight off the level-1 base stats regardless of `placement.level`.
  Only found by playing a station with real level-2/3 modules and comparing the HUD numbers by
  hand; every existing Lune spec used level-1 fixtures throughout, so `levelMultiplier(1, ...) ==
1` made the bug invisible to the whole suite. Fixed by applying `levelMultiplier` in exactly the
  two places `Balance.Upgrade`'s own rule ("a level only ever increases what a module PRODUCES,
  never what it consumes") says it should: the producing branch of power, `capacity`, and a
  radiator's own heat-capacity contribution in the power/heat loop, and `rate` in the flow-stage
  loop — never the consuming branch, never raw `heat`. `StepParams` gained a required
  `upgradeRules` field (threaded through `RunProductionTick`'s `Dependencies` and
  `Container.luau`); 5 new Lune specs pin both halves of the rule (production/capacity/rate scale,
  consumption/heat do not), 139 total.
- **The HUD's module counter only ever refreshed once, at the moment `Location` became
  "Station."** It listened to `workspace.Stations.ChildAdded` (a new PLAYER's station folder
  appearing) instead of the player's OWN folder's children — so a module placed after that first
  snapshot was never counted, and worse, `RestoreStation` replaying a large station is a burst of
  many Instances that doesn't necessarily finish replicating before the `Location` attribute does,
  which is what actually surfaced this as "0 module" against a live 89-module station. Fixed by
  binding directly to the player's own station folder and refreshing on ITS `ChildAdded`/
  `ChildRemoved`, the same pattern `BuildController`'s occupancy sync already used correctly.
- **A busy factory made every OTHER action slow.** `RunProductionTick` called
  `profileRepository:save()` (a real, rate-limited `DataStore:UpdateAsync`) every time a tick
  earned whole revenue — for an efficient station that's nearly every 0.5s tick, continuously,
  which floods that key's DataStore write budget (visible as "DataStore request was added to
  queue... requests will be dropped" spam). Any OTHER action needing to save (upgrading, building,
  spending) then queued behind that flood and could take several seconds — `DataStoreProfile
Repository`'s own retry logic waits `retryDelay * attempt` (2s+) between attempts once
  rate-limited. Fixed by having `RunProductionTick` update the in-memory profile (still correct
  for every other use case's next `load()`, since every `ProfileRepository` caches by reference —
  see `DataStoreProfileRepository`'s header) without calling `save()`, and adding the periodic
  autosave loop `Balance.Save.AutosaveInterval` was defined for but never wired to anything —
  Bootstrap now saves every connected player every `AutosaveInterval` seconds, matching the
  legacy `SaveService`'s three-moments design (periodic + `PlayerRemoving` + every other
  mutation's own immediate save) that this migration had only ever built two thirds of.
- **The core's saved level reverted to 1 every time a player left and rejoined their station.**
  `RestoreStation` unconditionally skipped the core with a bare `continue` (its Instance is
  already built by `claimPlot`, so replaying it as an ordinary placement would double it) — but
  that skip also threw away the core's saved LEVEL, since `claimPlot` always hardcodes a fresh
  core Instance at level 1 and the core is upgradable like any other module. Fixed by resyncing
  just the level inside that same skip branch: if the saved entry's level differs from what's
  already in `station.occupancy`, bump it there and call `sceneBuilder:setModuleLevel` — still
  never touching the core's existence, only its level. 2 new Lune specs in
  `restore_station.spec.luau`.
- **Hovering to upgrade or demolish a module was unreliable, worse the taller the module and the
  more oblique the camera angle.** `BuildController` picked the hovered cell the same way it
  picks an empty cell for placement: intersecting the mouse ray with the station's flat deck
  plane. That's correct when there's nothing built yet, but wrong for an EXISTING module with
  real height — what's visually under the cursor (the side or top of a tall Fabricator, say)
  projects onto a different deck cell than what's actually on screen. Fixed by adding
  `BuildController:_hoveredEntry()`, a real `workspace:Raycast` against the station folder's
  Instances (`RaycastParams` with `FilterType = Include`), reading the hit's ancestor Model's
  `X`/`Y` attributes instead of projecting through the deck. Verified live by comparing the two
  methods' output for the same mouse position: the deck-plane method computed cell (0,0) for a
  Fabricator actually standing at (-1,-3), a 3+ cell miss; the raycast method landed exactly on
  it. `_cellUnderMouse()` (the plane projection) is unchanged and still correct for its one
  remaining job: picking an empty cell to place a NEW module, where there's nothing to
  raycast against yet.

## Post-migration feature work

Ordinary feature work on top of the now-complete architecture. Not a migration stage — no more
of those — but documented with the same level of detail as the stages above, since these are
still load-bearing design decisions worth not re-litigating.

**Modify mode (move + rotate an already-placed module):**

- A fourth build-menu mode, alongside Build/Upgrade/Demolish: pick up an already-placed module,
  reposition and reorient it, for free (no cost, no refund — this corrects a misplacement, it
  isn't an economic action). The core can never be moved: its position at `(-1, -1)` is
  load-bearing for `EmbarkStation`/`claimPlot`/`Placement.initial()`, all of which assume it.
- `Domain/Station/Placement.canMove(station, x, y, newX, newY, newRotation, gridRules)` (new):
  finds the existing placement at `(x, y)` (any cell of a multi-cell module, not just its
  anchor — a raycast-picked cell), refuses a `definition.unique` module (the core) outright,
  then validates the destination against a **shallow copy of `station.occupancy` with the
  module's own current cells cleared** — so a module vacating its old footprint never blocks
  itself from moving onto a spot overlapping, or identical to, where it already stands (a
  same-position "move" is a valid no-op, confirmed live against a real 180+ module station).
  Reuses `Placement.cellsFree`/`touchesStation` unchanged; a destination that doesn't touch the
  rest of the station is refused exactly like an ordinary placement.
- `Server/Application/UseCases/MoveModule.luau` (new): load → `Placement.canMove` → mutate the
  existing `ModulePlacement` in place (`x`/`y`/`rotation`) → `StationProfileSync.apply` →
  save → `sceneBuilder:removeModule` (at the OLD anchor, captured before the mutation above —
  the scene builder indexes a model by the anchor it was built at) →
  `sceneBuilder:placeModule` (at the new anchor, carrying the same `level` along since it's the
  same placement object). No `StatsPublisher` dependency at all: a move changes no credits, so
  there is nothing to publish. Wired into `Container.luau` and a new `Net.MoveModule`
  RemoteFunction bound in `RemoteBindings.luau`, following the exact same shape as
  `PlaceModule`/`RemoveModule`/`UpgradeModule`.
- Client (`BuildController`): a new `_modifying`/`_movingFrom` pair of fields sits alongside
  `_demolishing`/`_upgrading`. Hovering (via the raycast `_hoveredEntry()` above) shows the same
  action highlight, colored with a new `Theme.Function.Move` (teal) instead of demolish-red or
  upgrade-amber. Clicking a non-core hovered module "picks it up": this **reuses the ordinary
  placement ghost machinery** (`self._selected`/`self._rotation`/`_rebuildGhost`/`_updateGhost`)
  rather than building a parallel preview system — the only two changes needed were in
  `_canPlace`, which now (a) skips the credit-cost check while `self._movingFrom` is set (a
  move is free) and (b) excludes the module's own occupancy entries from the "is this cell
  free" check via a `self._occupancy` reference-equality comparison, mirroring
  `Placement.canMove`'s vacate-then-check shape on the server. Clicking again while holding a
  module confirms the move (`Net.MoveModule:InvokeServer`); right-click cancels the pick-up (or
  exits the mode if nothing is picked up yet), matching Demolish/Upgrade's own right-click
  convention. All three modes are mutually exclusive by construction: every mode-entry path
  (`_select`, `_toggleDemolish`, `_toggleUpgrade`, `_toggleModify`) now also clears the other
  two, and a catalog selection or a mode switch mid-move cancels that move rather than silently
  abandoning it (`_exitModify`).
- `BuildPanel`: a fifth dock button ("Modifier", `Icons.Menus["Teleport"]`, teal) between
  Upgrade and Demolish; the dock's height and every later button's `LayoutOrder` were bumped to
  fit it. `SetModifying(active)` follows the same shape as `SetUpgrading`/`SetDemolishing`.
- Live-verified end-to-end in Play mode against a real ~180-module station (not a fresh test
  station): a no-op move (same position) succeeds, proving the self-vacate logic actually holds
  under real dense occupancy, not just an empty fixture; a real reposition rebuilds the scene at
  the new position with the module's level preserved (confirmed via the `Level` attribute); an
  attempted core move is refused server-side; an invalid destination (occupied) is refused, the
  in-hand module's ghost is dropped, and the toast shows the server's exact refusal reason with
  nothing left stray in the scene. 15 new Lune specs across
  `tests/specs/domain/station/placement.spec.luau` and
  `tests/specs/application/station_integration.spec.luau`, 156 total.

**Upgrade cap raised to 10, gated on the core's own level:**

- `Balance.Upgrade.MaxLevel: 5 -> 10` — the only place that number lives; every use case/UI
  already reads it dynamically, so this alone is the whole change on its own.
- New rule, requested alongside the cap raise: **no module may be upgraded above the core's
  CURRENT level** — the core paces the whole station's progression, so the very first upgrade a
  player can ever buy is the core's own. `Placement.coreLevel(station)` (new, in
  `Domain/Station/Placement.luau`) finds it; `UpgradeModule.luau` refuses
  (`"cannot exceed the core's level"`) whenever a non-core module's level is already `>=` the
  core's, checked after the existing max-level-cap refusal but before the cost computation. The
  core itself is exempt from its own rule (nothing to compare it against).
- The core's own upgrade needed a cost independent of `MinCost`'s shared floor: raising `MinCost`
  itself to charge the core more would ALSO have raised every other module's cheap early levels
  (their base-cost-scaled price sits just above the old floor at level 1 — confirmed by hand
  computing each module's level-1 cost against the floor before picking this approach). Fixed by
  giving `ModuleCatalog.upgradeCost` a **core-specific special case**
  (`if definition.id == "Core" then return rules.coreUpgradeCost end`, checked before the generic
  formula) and a new `Balance.Upgrade.CoreUpgradeCost = 375` (1.5x the old flat 250) — flat at
  every level, same as before, just pricier.
- 7 new Lune specs (`Placement.coreLevel`, the core's dedicated cost, and four `UpgradeModule`
  "core gate" integration tests interleaving core-then-module upgrades) — several EXISTING
  upgrade tests in `station_integration.spec.luau` had to be updated to upgrade the core in
  lockstep first, since they previously upgraded a module directly from level 1 with the core
  left behind at 1, which the new gate now correctly refuses. 163 total at this point.
- Live-verified against the real ~180-module test station (core already at level 6-8 from prior
  sessions): a module below the core's level caught up to it successfully; a second attempt past
  the core's level was refused with the exact new message; the core's own upgrade cost read 375
  at every level tried, matching `Balance.Upgrade.CoreUpgradeCost` exactly.
- A companion change, floated the same day and reverted the same day: resource sell values
  (Ore/Alloy/Component) were multiplied by 10 to compensate for the higher level cap making a
  full build-to-max take an estimated ~35h of connected time (measured via a throwaway Lune
  simulation script using the real `Simulation.step`/`ModuleCatalog`/`Placement` code, not hand
  math — deleted after use, never part of the tracked tree). Reverted back to the original
  5/22/75 the same session, at the user's request, pending a revisit later — **don't reintroduce
  the x10 values without being asked; the catalogue's real values are still the original ones.**

**Rebirth (prestige) system, built modular and temporarily enabled to test:**

- The shape: once the core reaches a threshold level, a player may reset their station AND their
  credits for a small, permanent, per-rebirth production multiplier that stacks across every
  future rebirth. Two paid shortcuts sit on top: **Ultimate** (a flat x1.5 multiplier on
  everything, independent of rebirths) and **EarlyRebirth** (lowers the threshold from level 10
  to level 5 — the reward for rebirthing is identical either way, only the wait is shorter).
  Numbers (confirmed with the user, not guessed): `+25%` additive per rebirth, `x1.5` for
  Ultimate, thresholds `10`/`5`. **Deliberately NOT built this pass**: raising the level cap
  itself (e.g. to 20) after a rebirth, and any real Roblox Game Pass wiring — both were explicitly
  floated as "see if"/"later" by the user, not firm requirements.
- `Domain/Rebirth/Rebirth.luau` (new): `Rebirth.canRebirth(coreLevel, hasEarlyPass, rules)` and
  `Rebirth.multiplier(rebirths, hasUltimate, rules)`, both pure. `Rules.enabled` is the modular
  per-zone switch this was explicitly asked for — flip it off and `canRebirth` never returns
  true, whatever the core's level; only one zone/station design exists today, so it's one flag
  in `Balance.Rebirth`, not a per-zone table yet. `Rebirth.Passes` names the two pass-id strings
  once (`"Ultimate"`, `"EarlyRebirth"`) so nothing else hand-spells them.
- **No new Profile fields needed** — `profile.rebirths: number` and
  `profile.unlocked: {[string]: boolean}` already existed, reserved from early in the migration
  ("Reserved for progression... no migration to do the day they get wired up" — see
  `Profile.luau`'s own header). The two passes are just `profile.unlocked.Ultimate`/
  `.EarlyRebirth` booleans; nothing to migrate, nothing to sanitize differently.
- `Simulation.step` gained a required `globalBoost: number` field on `StepParams`, multiplied in
  at exactly the same three places `ModuleCatalog.levelMultiplier`'s own per-module boost already
  was (the producing branch of power, capacity/heat-capacity, flow-stage rate) — never
  consumption, same rule as levels. `RunProductionTick` computes it once per tick from
  `profile.rebirths`/`profile.unlocked.Ultimate` via `Rebirth.multiplier` and threads it through;
  every other `Simulation.step` caller (Lune fixtures) needed `globalBoost = 1` added for the
  no-op case.
- `Server/Application/UseCases/RebirthStation.luau` (new): load → `Placement.coreLevel` +
  `Rebirth.canRebirth` → tear down every non-core module's Instance
  (`sceneBuilder:removeModule`, reusing the existing port method — no new one needed) and reset
  the core's Instance level to 1 (`sceneBuilder:setModuleLevel`, ditto) → replace `station` with
  a fresh `Placement.initial()` → `profile.credits = startingCredits`, `profile.rebirths += 1` →
  `StationProfileSync.apply` → save both → publish `Snapshot.credits` and a new
  `Snapshot.rebirth(rebirths, hasUltimate, hasEarlyPass, boost)`. Deliberately resets ONLY the
  station and credits, not `profile.objective` — the onboarding chain is a one-time teaching
  device, replaying it on every rebirth would just be annoying, not requested either.
- `Server/Application/UseCases/DevGrantPass.luau` (new): the **testing stand-in for real
  monetization**, which can't be wired yet — no real Roblox Game Pass exists to check ownership
  of. Sets `profile.unlocked[passId] = true` and re-publishes the rebirth snapshot; takes the
  exact same grant -> save -> snapshot path CLAUDE.md's own dev-affordance rule requires, so a
  real `MarketplaceService.PromptGamePassPurchaseFinished` handler later would set the identical
  flag and go through nothing else. Wired into `Container` **only** when built with
  `development = true` (a new `Container.new` option, set from `Bootstrap.luau` via
  `RunService:IsStudio()`) — `Container.useCases.devGrantPass` is simply absent otherwise, and
  `RemoteBindings.bind` only sets `Net.DevGrantPass.OnServerInvoke` when it exists, so the remote
  Instance exists in production (`Net.luau` always creates every listed remote) but has no
  handler there at all.
- Client: a sixth dock button ("Renaissance", `Icons.Arrows["Rebirth"]` — an icon the pack
  already had, evidently ripped from a simulator game with the same mechanic — new
  `Theme.Function.Rebirth` magenta) opens a confirmation modal (`BuildPanel:ShowRebirthConfirm`)
  before doing anything: this is the one destructive, irreversible action in the whole build
  menu, unlike every toggleable mode next to it. The modal's "current -> next boost" preview is
  computed client-side from the published `GlobalBoost` attribute plus `Balance.Rebirth`'s own
  numbers (linear in rebirth count, no need to duplicate `Rebirth.multiplier` client-side) —
  purely cosmetic, the server still recomputes and publishes the real value once the rebirth
  actually happens. `HudController` shows a `Renaissances : N (x1.25) [· Ultimate]` line under
  the income line, only once it means something (`rebirths > 0` or `boost > 1`) — an eligibility
  check is NOT precomputed client-side at all (no client-side core-level tracking exists for
  this); clicking always asks the server, whose refusal reason is shown as an ordinary toast,
  same pattern every other action already uses. Dev-only **F9/EarlyRebirth F10** keybinds grant
  the two passes directly for live testing, gated by `RunService:IsStudio()` client-side too
  (belt-and-suspenders on top of the server never binding a handler outside dev mode).
- 18 new Lune specs (`Rebirth.canRebirth`/`.multiplier` in isolation, `Simulation.step`'s
  `globalBoost` stacking with per-module levels, and a dedicated `rebirth_integration.spec.luau`
  mounting the real `Container` — refusal below threshold, success at threshold resetting
  station/credits/core level, the early-pass shortcut, the `enabled` kill switch, SceneBuilder
  wiring, `DevGrantPass` including "does not exist without `development = true`", and the boost
  actually reaching `RunProductionTick`'s real income). 190 total.
- Live-verified in Play mode against the real ~185-module test station: the refusal path (core
  below threshold, no pass) was confirmed via a direct remote call with no side effects; granting
  Ultimate via `DevGrantPass` correctly bumped the published `GlobalBoost` to 1.5 and the HUD line
  appeared with the right multiplier and income scaled by exactly 1.5x; the dock button and
  confirmation modal rendered correctly with the right "current -> next" math (x1.50 -> x1.88).
  **Deliberately NOT confirmed live**: actually completing a rebirth against that real station,
  since doing so would irreversibly wipe ~185 real modules built up over many prior sessions —
  that half of the mechanic is covered by the Lune integration tests above instead (which
  exercise the exact same `RebirthStation` code path against fake ports), pending the user's own
  call on whether to test the real wipe against real data.
- **The user then actually did that real test themselves** (twice, reaching `rebirths = 2` on
  the real ~185-module station, which is what wiped it) — this is what surfaced the one real bug
  this feature's first pass had: the HUD showed a single blended
  `"Renaissances : 1 (x1.88) · Ultimate"` line, which reads as if Ultimate CAUSED that combined
  number, when the free rebirth bonus (+25%/rebirth), Ultimate (flat x1.5, unrelated to rebirth
  count), and EarlyRebirth (only ever changes the THRESHOLD, never the multiplier) are three
  independent facts that were never meant to be shown as one. Fixed by splitting the HUD into
  two lines that are never combined into a shared number — `HudController`'s
  `rebirthCount`/`rebirthPasses` captions (`"Renaissances : N (+25% chacune)"` and, on its own
  line, `"Ultimate actif (x1.5)"` and/or `"Renaissance dès niv. 5 débloquée"`, joined with " · "
  only when BOTH passes are owned, never with the rebirth count) — and by rewriting
  `BuildPanel:ShowRebirthConfirm` to state the flat `+25%` this specific rebirth grants, dropping
  the "current boost -> next boost" preview entirely (it was the same conflation, just in the
  confirmation dialog instead of the HUD). Re-verified live against the same (now much smaller,
  2-module) station: both lines render separately, and the confirm dialog's new wording fits
  the box cleanly.
- **A real in-game place to get Ultimate, and the rebirth line showing its actual result.** Two
  more requests from the same follow-up: (a) Ultimate had no discoverable UI at all yet, only the
  F9 dev keybind; (b) `"Renaissances : N (+25% chacune)"` showed the flat PER-rebirth rate, not
  what N rebirths actually add up to. Fixed (b) trivially:
  `Balance.Rebirth.BonusPerRebirth * 100 * rebirths` instead of the constant alone, so 2 rebirths
  reads `"(+50%)"`, 3 reads `"(+75%)"`. Fixed (a) with a seventh dock button
  (`Icons.Menus["VIP"]`, new `Theme.Function.Ultimate` gold, a permanent `"x1,5"` badge via the
  existing `SetBadge` — not an affordability count like Construire's) that **hides itself once
  owned** (`BuildPanel:SetUltimateOwned`, driven by the `HasUltimate` attribute) since it's a
  one-time purchase, not a repeatable action like its six dock neighbors. Confirming it still
  calls `Net.DevGrantPass:InvokeServer("Ultimate")` — the same dev-only stand-in as before, now
  reachable without knowing the hidden keybind, until a real Game Pass exists to swap it for.
- **Refactored the one-off Rebirth confirm modal into a generic `BuildPanel:ShowConfirm(title,
  body, confirmColor, onConfirm)`** so Ultimate's confirmation could reuse it instead of
  duplicating the whole dialog a second time — `confirmColor` tints the Confirm button
  (magenta for Rebirth, gold for Ultimate) so the two read as distinct actions sharing one
  mechanism, not the same dialog blindly reused. `onRebirth`/`ShowRebirthConfirm` are gone;
  BuildController now builds both dialogs' full title/body text itself and hands `ShowConfirm`
  a closure to run on confirm, matching BuildPanel's own header ("this module only displays,
  it decides nothing").
- Live-verified: the button appears with the gold "x1,5" badge, opens a gold-confirm-button
  dialog with the requested "x1.5 sur toute la production, permanent" wording, and granting it
  correctly disappears the button and restores the HUD's "Ultimate actif" line. One genuine
  red herring surfaced mid-test and is worth remembering for next time: forcing
  `player:SetAttribute("HasUltimate", false)` from the CLIENT to preview the "not yet owned"
  state, then granting for real, left the client stuck reading `false` even though the server's
  own attribute (and the persisted profile) were correctly `true` — Roblox only re-replicates an
  attribute on an actual server-side VALUE CHANGE, and the server's value never changed (it was
  already `true`, DevGrantPass set it to `true` again), so the client's own locally-forced
  override was never corrected. Not a game bug: real code never writes to a Player's own
  attributes from the client, only Bootstrap/the use cases do, server-side, on real transitions.

**Dev Mode panel (a real in-game dev tool, replacing the old F9/F10 keybinds):**

- A dock button (`DevController`, `DevPanel.luau`, top-right — deliberately far from the build
  dock, since this is a testing tool, not a player-facing one) opens a small window with: a
  rebirth-count override (a text box + "Appliquer") with its OWN toggle for whether applying it
  also wipes the station/credits like a real rebirth, an Ultimate on/off toggle, an
  EarlyRebirth on/off toggle, a "give yourself N credits" box + button, an "unlimited money" on/off
  toggle, and a two-step "TOUT RÉINITIALISER" (full reset) button. Only ever built at all under
  `RunService:IsStudio()` (`DevController:Start()`'s first line) — added last in
  `Bootstrap.client.luau`'s `CONTROLLERS` list specifically so it can never delay anything real.
- **`DevGrantPass` (grant-only, F9/F10-keybind era) became `DevSetPass` (toggle, on or off)** —
  `DevSetPass:run(userId, passId, enabled)` sets `profile.unlocked[passId] = enabled` instead of
  always `true`, so the panel's Ultimate/EarlyRebirth buttons are real toggles, not one-way
  grants. The old `BuildController` F9/F10 keybind block (and the file `DevGrantPass.luau`) were
  deleted outright, not kept alongside the panel — the panel is a strict superset, and CLAUDE.md's
  "don't build backwards-compat shims" rule applies to internal dev tooling too. The in-game
  Ultimate purchase button's confirm callback was updated to call `DevSetPass:InvokeServer
  ("Ultimate", true)` in place of the old `DevGrantPass` call.
- **New `Container` field: `container.development: boolean`.** Every dev-only use case
  (`devSetPass`/`devSetRebirths`/`devSetUnlimitedMoney`/`devResetAll`) was already gated by only
  existing on `container.useCases` in dev mode, per the pre-existing pattern — but `DevGiveCredits`
  needed to reuse the ALREADY-wired, not-dev-only `AddCredits` use case (the exact one real
  purchases/rewards use — no new use case needed, just a new remote exposing it to a player
  action for the first time), so `RemoteBindings.luau` can't gate that one binding by "does this
  use case exist" the way it gates the other four. `container.development` is the one flag that
  gates it directly instead: `if container.development then Net.DevGiveCredits.OnServerInvoke =
... end`.
- **"Unlimited money" is a periodic top-up, not an intercept on every spend path.** Toggling it
  sets a new `SessionRegistry` flag (`_unlimitedMoney[userId]`, alongside the pre-existing
  `_embarked`/`_restored` volatile per-session state — never reaches the profile, matching every
  other `SessionRegistry` entry) rather than touching `SpendCredits`/`PlaceModule`/`UpgradeModule`/
  `RebirthStation` individually. `RunProductionTick` (already running every
  `Balance.Simulation.TickRate` = 0.5s for every connected player, Lobby or Station, no location
  gate) checks it once per tick: if enabled and `credits < Balance.Dev.UnlimitedMoneyCeiling`
  (999,999,999 — a new `Dev` section in `Balance.luau`, explicitly dev-only numbers with "no
  bearing on real balance"), it sets and republishes `Credits` at the ceiling. Turning it back off
  simply stops that top-up on the next tick; nothing reverts credits downward on its own.
- **`DevResetAll` reuses `Profile.blank(rules)`** (the same pre-existing Domain function
  `InMemoryProfileRepository`'s cold-start path already used) rather than hand-building the
  "just joined" shape a second time — confirmed by reading `Profile.blank`'s source that it only
  reads `rules.startingCredits` internally, so passing the full `profileRules` through from
  `Bootstrap` (a new `rules.profileRules: Profile.Rules` field on `Container`, reusing the same
  local `Bootstrap.luau` already built for `DataStoreProfileRepository`) is correct even though
  `blank()` itself only needs one field of it. Wipes the station the same way `DevSetRebirths`'s
  `resetStation = true` branch does (remove every non-Core placement via `sceneBuilder
:removeModule`, reset the Core's level via `sceneBuilder:setModuleLevel(userId, -1, -1, 1)`,
  replace `station` with `Placement.initial()`), then republishes `Credits`/`Objective`/`Rebirth`
  snapshots so the client reflects the reset immediately without needing a rejoin.
- **Two-step arm/confirm for "TOUT RÉINITIALISER"**, not BuildPanel's full modal confirm — a
  dev-only destructive action doesn't need the same weight of protection as a real player-facing
  one, but still deserves more than a bare single click. First click "arms" the button (white
  background, red "CLIQUER POUR CONFIRMER" text, a `task.delay(4, ...)` auto-revert guarded by an
  incrementing `armToken` so a stale timer from an earlier arm can never revert a newer one);
  a second click while armed fires `onResetAll` and immediately repaints back to the resting
  state (not via the timer — the confirm branch itself resets the visuals as part of firing).
- **Two naming bugs found and fixed during live testing, both about MCP-driven verification, not
  gameplay:** (1) `DevPanel`'s `textBox`/`toggleButton`/`actionButton` helpers originally took no
  `Name` parameter, so every TextBox instance shared Roblox's default "TextBox" name and every
  chunky button shared "Frame" — harmless in-game (nothing there reads instance names), but it
  made `instance_path`-based MCP clicks ambiguous between the rebirths box and the credits box.
  Fixed by adding an explicit `name: string` first parameter to all three helpers and naming every
  call site distinctly (`RebirthsBox`, `CreditsBox`, `ResetToggle`, `ApplyRebirths`,
  `UltimateToggle`, `EarlyToggle`, `GiveCredits`, `UnlimitedToggle`, `ResetAll`). (2) A live click
  on "Donner" appeared to silently do nothing after a fresh Play session — root-caused via
  screenshot to the panel's `ScrollingFrame` having reset to its top scroll position, scrolling
  the button out of view; an `instance_path`-click on a scrolled-out-of-view element fails with no
  error at all. Not a code bug — same "must scroll a `ScrollingFrame` into view before clicking"
  gotcha `BuildPanel`'s own grid already has.
- **Live-verified end-to-end in Play mode:** Ultimate/EarlyRebirth toggles both flip the real
  `HasUltimate`/`HasEarlyRebirth` attributes and repaint green/off correctly; giving credits (via
  `DevGiveCredits`, tested with a negative amount too, to bring a balance back down for the next
  check) lands the exact requested delta; enabling "Argent illimité" tops a low balance up to the
  999,999,999 ceiling within one tick, and disabling it immediately stops any further top-up
  (confirmed by watching a manually-lowered balance stay put, not snap back); `DevSetRebirths`
  correctly leaves the station/credits untouched when `resetStation = false` and correctly wipes
  credits back to `startingCredits` when `true`; the "TOUT RÉINITIALISER" two-step confirm, once
  actually fired (arm click + confirm click, back-to-back with no MCP round-trip in between —
  see below), resets credits/rebirths/both passes/objective all at once, matching `DevResetAll`'s
  own Lune spec. No console errors at any point.
- **A testing-methodology dead end worth recording, not a product bug:** verifying the two-step
  arm/confirm via MCP by clicking, then making a SEPARATE tool call to read the button's color/text
  back, kept reading "unarmed" even right after an arm click — looking exactly like the click was
  being silently dropped. Root cause: each MCP tool call (click, screenshot, console read,
  attribute read) is its own round trip taking a couple of seconds, and several chained together
  routinely exceeded the 4-second auto-revert window between the arm click and the read-back —
  the arm genuinely happened and then genuinely auto-reverted before the check landed. Confirmed
  by attaching a temporary diagnostic `print` inside the real handler (proved it fires every
  click, in order) and then firing both the arm click and the confirm click in a single
  `user_mouse_input` call with no round trip in between — the reset fired correctly every time.
  Lesson for testing any short-lived armed/confirm UI state like this one via MCP again: batch the
  two clicks into one tool call, don't check state between them.
- **Not conclusively re-confirmed this pass: a `DevResetAll` reset surviving a Play session
  restart.** Two attempts (one with an explicit 5s wait before stopping Play, to let any DataStore
  write flush) both reloaded the OLDER pre-reset profile values instead of the reset ones, on an
  account that had just received a heavy burst of rapid-fire dev-remote calls (rebirths set
  several times, credits adjusted several times, multiple reset attempts) in a short span —
  consistent with the DataStore per-key write-rate limiting CLAUDE.md's "a busy factory made every
  OTHER action slow" note already documents elsewhere, not a new bug in this feature (`DevResetAll`
  calls `profileRepository:save()` through the exact same path every other verified use case does,
  and its own Lune spec already pins the save happening correctly in isolation from any real
  DataStore). Worth a clean re-check with normal, unhurried play if it ever matters, rather than
  assumed fixed.
- **Found right after, via live testing on-station (not in the Lobby, where every earlier check
  happened): the dock button overlapped the build dock's own "Construire" button.** Both are
  anchored to the same right screen edge; the build dock (`BuildPanel`) is vertically centered
  and, with 7 buttons (Construire/Améliorer/Modifier/Démolir/Lobby/Renaissance/Ultimate), tall
  enough that its topmost button already sits close to the very top of the screen (measured via
  `AbsolutePosition`: Construire's top edge at y=37 on a 868px-tall viewport) — the dev button's
  old position (`SPACE.xl` = 24px from the top, 48px tall) put its own bottom edge at y=72, a
  35px overlap. Fixed by shrinking the dock button to a bespoke 32x32 (smaller than every
  `Theme.Control` token, the smallest of which — `sm` — would still have clipped by 1px) flush
  against the very top of the screen (y=0), clearing Construire's top edge by a clean 5px;
  `DevPanel:new`'s window-open position was updated in lockstep (it was expressed as an offset
  from the button's own height, not a hardcoded number, so this only needed the two new
  `DEV_BUTTON_SIZE`/`DEV_BUTTON_TOP` locals threaded through, not a second magic number). Live-
  verified via `AbsolutePosition` reads before/after (35px overlap → 5px clear gap) and a
  screenshot on the same real station.

**Not done yet:** nothing migration-related. `ReplicatedStorage.Remotes` (orphaned legacy remotes
folder) and `Workspace.Script` (an unrelated pre-existing placeholder) are cosmetic leftovers, not
blockers — see Stage 8's last bullet. From here on, treat this as an ordinary, already-migrated
codebase: new features go straight into the `src/` architecture above, no more staged porting.

## Mandatory architecture (hexagonal / ports & adapters)

One goal: game rules depend on no Roblox API, so they're testable from a command line in
milliseconds and replaceable without a rewrite. Arrows point inwards only:

| Layer         | May depend on                                    | Never knows about            |
| ------------- | ------------------------------------------------ | ---------------------------- |
| `Domain`      | nothing                                          | Roblox, network, persistence |
| `Application` | `Domain`, ports                                  | Roblox, instances            |
| `Adapters`    | `Domain`, ports, Roblox                          | the use cases                |
| `Composition` | everything                                       | —                            |
| `Client`      | `Domain` (read only), `Config`, network contract | server logic                 |

Enforced in practice with two greps that must return nothing:
`grep -r "game:GetService" src/Shared/Domain` and `grep -r "Instance.new" src/Server/Application`.

Target layout:

```
src/
├─ Shared/                     → ReplicatedStorage.Shared
│  ├─ Config/                  The only source of constants (balance, progression, catalogues, monetization, Themes/)
│  ├─ Domain/                  THE RULES (pure Luau, tested) — one folder per subject
│  │  ├─ Economy/ Monetization/ Profile/ Support/ (Result · Format) ...
│  ├─ Net.luau                 The shared network contract
│  └─ Signal.luau
├─ Server/                     → ServerScriptService.Server
│  ├─ Application/             USE CASES (depend on ports only)
│  │  ├─ Ports.luau            The contracts, as types
│  │  ├─ SessionRegistry       Volatile state, never persisted
│  │  ├─ Snapshot              The presentation model sent to the client
│  │  ├─ RewardApplier         The shared path of every reward
│  │  └─ UseCases/             One file each — the list of things a player can cause to happen
│  ├─ Adapters/                Persistence/ (DataStore · InMemory) · Replication/ (attributes, leaderstats, notifications) · Roblox/ (character actuator, probe, teleporter, marketplace, logger)
│  └─ Composition/             Container · Adapters · Bootstrap · bindings — the ONLY wiring
└─ Client/                     → StarterPlayerScripts.Client
   ├─ State.luau               Local mirror of the replicated state
   ├─ Controllers/             Input, prediction, effects
   └─ UI/                      Theme · Widgets · HUD · windows
```

Ports (declared as types in `Application/Ports.luau`, implemented once for production and once
as a test double): `ProfileRepository` (DataStore / in-memory fake), `StatsPublisher`
(attributes+leaderstats / recording fake), `Notifier` (remote event / recording fake),
`MovementActuator` (Humanoid / recording fake), `Teleporter` (CFrame / recording fake),
`PassGateway`/`Marketplace` (MarketplaceService / scripted fake), `Clock` — **two** clocks, an
absolute epoch for anything surviving disconnection and a monotonic one for session-only
durations; never read `os.time()`/`os.clock()` directly from a rule.

`Composition/Container.luau` is the **only** file allowed to assemble anything (config → domain
objects → use cases, ports plugged into adapters). Three details worth preserving when writing
it: dependencies are cloned per use case (`setmetatable(table.clone(dependencies), UseCase)`,
never share one metatable across use cases); the container takes its configuration as an
argument (production default is a convenience, not a hard dependency — tests pass their own);
development-only affordances (dev codes, etc.) are appended by the container only when built in
development mode, decided once in the bootstrap via `RunService:IsStudio()`.

Structural decisions that are expensive to reverse, so don't relitigate them per-feature:

- **Progress is measured by the server** — cap credited displacement to what's physically
  reachable in elapsed time; never trust a client-reported gain.
- **Volatile state never reaches the profile** — anything belonging to one attempt lives in the
  session registry, not persistence.
- **State replicates through attributes, not RemoteEvents** — server writes attributes, engine
  replicates, client listens.
- **Comfort is client, authority is server**, decided per action (an action that pays out is
  never client-predicted).
- **Movement speed is bounded** regardless of the displayed number, to prevent tunnelling.
- **A failed profile load marks the session unsaveable rather than defaulting to an empty
  profile** — never overwrite a save with blank data because a read failed.
- **Every reward (purchase, daily, chest, code) takes the same one path**: credit → republish →
  notify → save, via one `RewardApplier`.

Tests: `Domain` and `Application` run **outside Studio** via a Lune harness that rebuilds the
Roblox tree from `default.project.json`; adapters are thin and intentionally untested (they'd
only assert the engine does what the engine does).

## Mandatory workflow & commands

Rojo-based project, tools managed via [Rokit](https://github.com/rojo-rbx/rokit)
(`rokit.toml` + `rokit install`), or `./scripts/setup.ps1` to fetch Rojo/Lune/Selene/StyLua into
git-ignored `.tools/` and generate `sourcemap.json`.

| Command                       | Effect                                                           |
| ----------------------------- | ---------------------------------------------------------------- |
| `./scripts/test.ps1`          | Run the whole suite                                              |
| `./scripts/test.ps1 <filter>` | Run only specs whose path contains the filter                    |
| `./scripts/check.ps1`         | Format + lint + Rojo build + tests — **run before every commit** |
| `./scripts/check.ps1 -Fix`    | Format instead of checking                                       |
| `./scripts/serve.ps1`         | Serve the project to Roblox Studio (Rojo Connect)                |

In Studio without DataStore API access, persistence falls back to memory automatically.

**Test-first.** Every rule starts as a spec in `tests/specs/domain/...spec.luau`, then the
implementation. Domain specs use their own fixtures, never the real balancing config (so
rebalancing can't break a test); a separate spec checks the real config for internal
consistency (ladders rise, ids unique, no required field missing). Write the test that would
have caught a bug, not the one that merely passes. Pin curve intent with fixed reference points.
Integration tests mount the real `Container` with fake ports — a use case that exists but was
never wired must fail a test, not fail silently in Studio.

Where things go: a rule/computation/validation → `src/Shared/Domain/`; a sequence of actions
(load → decide → publish) → `src/Server/Application/UseCases/`; a call to a Roblox API →
`src/Server/Adapters/`; a balancing number → `src/Shared/Config/` (**no magic numbers
elsewhere**); anything displayed → `src/Client/UI/`. A new use case is declared in
`Composition/Container.luau` and, if player-triggered, in `Composition/RemoteBindings.luau`. If
a rule needs a Roblox API, it isn't a rule yet — split the decision (domain) from the engine
call (adapter) behind a port.

Conventions: `PascalCase` modules, one per file, one table returned. **Comments in English**
going forward, on the _why_ (this is a change from the legacy French-comment convention below —
see "Language convention" note). Business failures go through `Result.ok`/`Result.err`;
`error()` is reserved for programming bugs. Anything from the network is type-checked before
use. No player-readable string in a view — words live in the theme module (icons + palette +
copy) so the UI can be reskinned as a data change; views only hold grammar (sizes/fonts/layout).
UI is sized in design pixels for one reference resolution with a single `UIScale` adapting it —
nothing else reads the viewport (remember: `UICorner` radius is capped by the smaller side it
rounds, and `ClipsDescendants` clips to the rectangle, not the rounded corners).

Development-only affordances (dev codes granting currency/progress/boosts) must take the exact
same path as a real promo code (redeem → grant → save → snapshot) and exist only in a table
merged in by the container in development mode — never a bypass around the pipeline.

Commits: [Conventional Commits](https://www.conventionalcommits.org/) —
`<type>(<scope>): <imperative description>`. Types: `feat`, `fix`, `refactor`, `test`, `docs`,
`chore`, `perf`. Scopes: `domain`, `application`, `server`, `client`, `monetization`, `ui`,
`build`. Body says _why_ and what was rejected. `./scripts/check.ps1` must be green before every
commit.

## Legacy implementation (historical reference — no longer live)

**As of the Stage 8 cutover, none of this runs in the live place any more.** Every script and
ModuleScript this section describes was replaced in place by the `src/` tree via Rojo Connect —
`script_read`/`script_search`/`multi_edit` against the paths named below will not find them.
This section is kept purely as the historical record of the behavior each `src/` module was
ported to preserve; it is not a pattern to extend with new code, and never was.

### Accessing it

There is (still, for now) no local source tree for the game code itself — only `CLAUDE.md` and
`Docs/` exist on disk. All reading/editing of the actual game happens through the
`Roblox_Studio` MCP server against the open Studio instance.

- Call `mcp__Roblox_Studio__list_roblox_studios` first to get the `studio_id` — every other
  call requires it. Confirm which instance you're targeting before making edits.
- The DataModel's internal name in Studio is **"Horreur coopérative"** (a stale/leftover place
  name, not a different project) — content (`EconomyService`, `PlotService`, `StationService`,
  `Config.GameName = "Orbital"`) confirms this is Tycoon Orbital.
- Use `script_read` / `script_search` to inspect Luau source, `multi_edit` to change it, and
  `execute_luau` for ad-hoc code. `get_console_output` surfaces `print`/`warn` from the running
  place. Editing requires Studio to be in **Edit** mode — `multi_edit` errors out during Play;
  use `start_stop_play(is_start=false)` first, and check `get_studio_state` since another
  collaborator may have started/stopped Play independently of you.
- No Rojo sync, no build/lint/test command exists yet for this code — validate a change with
  `start_stop_play` + `get_console_output` / `screen_capture`.

### Language and comment convention (legacy code only)

Legacy Studio code comments are in **French**, explaining _why_ rather than _what_. Preserve
that style when touching legacy code before it's ported. New code written under `src/` follows
`DEVELOPMENT.md`'s convention instead: **English**, why-focused. All scripts are `--!strict`.

### Server (`ServerScriptService.Server`)

`Server.Bootstrap` requires `ReplicatedStorage.Shared.Remotes` first, then requires and
`:Start()`s each system in `Server.Systems` **in a fixed order**, encoding a one-way dependency
rule (a system may only depend on systems earlier in the list):

```
SaveService → EconomyService → PlotService → LobbyService → StationService
→ ProductionService → ObjectiveService
```

- **SaveService** — owns the player `Profile` (credits, placed modules incl. `id/x/y/r/lv`,
  objective progress; DataStore key `OrbitalPlayer_v1`). Single source of truth for player
  state. Autosaves periodically, on leave, and on `BindToClose`. Falls back to memory-only in
  Studio without API access.
- **EconomyService** — the only code allowed to change a credit balance (`Add`/`TrySpend`).
  Batches gain notifications over ~1s.
- **PlotService** — 6 station plots in a fan around the lobby; a plot's structure is only built
  when claimed.
- **LobbyService** — wires the hand-built scenery under `Workspace.Scenery.Lobby`. Scene
  contract (must exist under these names or the server errors on startup): `Lobby` (Folder) →
  `LobbySpawn` (SpawnLocation) + `LaunchPad` (BasePart with a `ProximityPrompt`).
- **StationService** — per-player grid occupancy, placement/removal/upgrade validation
  (bounds, collision, adjacency, uniqueness, cost). Server is sole authority; client sends
  intent only. Module geometry clones from `ReplicatedStorage.ModuleModels.<id>` (contract:
  built at rotation 0, centered on origin, base at y=0, `WorldPivot` at origin, **no
  `PrimaryPart`** — stripped on clone). Falls back to a flat colored box if no template exists.
  Rotation is stored as quarter-turns **0-3, clockwise** (`turn = math.floor(rotation) % 4`);
  `CFrame.Angles(0, -math.rad(90) * rotation, 0)` is what makes the turn clockwise (negative
  sign) as seen from the top-down build camera. Every cloned descendant `BasePart` gets
  `Anchored = true` and `CanCollide = true` so decorative geometry (rails, pipes, masts...) —
  not just the base plate — blocks the player. `StationService:Upgrade` raises a placement's
  `level` (1 to `Config.Upgrade.MaxLevel`) for a scaling cost; `ModuleCatalog.isUpgradable`
  gates which modules qualify.
- **ProductionService** — tick simulation (`Config.Simulation.TickRate`), three dependent
  stages: power (solar depends on orbital sunlight phase; batteries buffer shortfalls) → heat
  (radiators dissipate in proportion to empty neighboring cells) → resource flow (per connected
  network: ore → alloy → component, sold by cargo bays). `Networks()` (BFS over
  `carries = true` adjacency) is reused by `ObjectiveService` rather than redefined.
- **ObjectiveService** — onboarding chain; text/rewards live in `Shared.Objectives`, this
  service only judges completion via per-objective predicates. Polls once/second rather than
  hooking `StationService` (loads after it; the dependency rule forbids the reverse link).

### Client (`StarterPlayer.StarterPlayerScripts.Client`)

`Client.Bootstrap` requires and `:Start()`s controllers in order: `HudController →
BuildController → ObjectiveController → LabelController`.

- **BuildController** — construction mode: menu (`UI.BuildPanel`), grid-snapped ghost preview,
  placement/demolition/upgrade (keys `B` menu, `R` rotate, `X` demolish, `U` upgrade), and a
  top-down "build camera". The ghost **clones the real module template** (same contract as
  `StationService`, translucent + a `Highlight` for valid/invalid tint) rather than a plain box,
  so shape and facing are visible before placing; falls back to a colored box if no template
  exists. Re-runs the server's validation locally only to color the preview — the server's
  response is still authoritative.
- **HudController** — credits/income/power/heat/sunlight capsules, visible only on-station.
- **ObjectiveController** — renders the objective banner from `Shared.Objectives`, indexed by
  the number the server sends (text never crosses the network).
- **LabelController** — floating name label above each placed module, via the `ModuleId`
  attribute the server stamps on each model.

`Client.UI` holds presentation-only modules: **Theme** (single source of truth for all
colors/spacing/fonts/radii — nothing hardcoded outside it), **BuildPanel**, **GainFeed**.

### Shared (`ReplicatedStorage.Shared`)

Read by both server and client; pure data/math, no state:

- **Config** — global settings: economy, save/DataStore, grid, plots, orbit, heat, simulation
  tick rate, and `Upgrade` (module leveling: `MaxLevel`, `GainPerLevel`, `CostFactor`,
  `MinCost` — a level only ever increases what a module _produces_, never what it consumes).
- **Remotes** — all RemoteEvents/RemoteFunctions from one `DEFINITIONS` table, including
  `UpgradeModule`. Adding a remote is a one-line addition here.
- **Grid** — pure math for the build grid (cell keys, bounds, world↔cell, neighbours,
  rotation-aware sizing). No Instances — server and client compute identical results.
- **ModuleCatalog** — data-only module definitions (cost, size, power/heat, resource
  input/output/rate, `carries` flag) plus `levelMultiplier`/`upgradeCost`/`isUpgradable` for the
  leveling system. `sizeOf(definition, rotation)` swaps width/depth for any odd quarter-turn
  (1 or 3), not just `rotation == 1`.
- **Objectives** — onboarding chain text/hints/rewards; server sends only an index.
- **Icons** — icon-id lookup table.

### Key gameplay rule to preserve

A **corridor** is walkable but carries nothing; only `carries = true` modules (conduits,
collectors, smelters, fabricators, cargo bays, the core) form a resource network via orthogonal
adjacency. This is the core teaching moment of the objective chain — don't blur the
corridor/conduit distinction, in the legacy code or when porting it into `Domain`.
