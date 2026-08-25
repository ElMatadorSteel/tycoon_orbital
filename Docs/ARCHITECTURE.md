# Architecture

A **hexagonal architecture** (ports & adapters) for a Roblox game. One goal: the
rules of the game depend on no Roblox API, which makes them testable from a
command line in milliseconds and replaceable without a rewrite.

```
                    ┌─────────────────────────────┐
                    │           DOMAIN            │  pure Luau
                    │   rules, no API, no state   │  0 dependencies
                    └──────────────▲──────────────┘
                                   │ uses
                    ┌──────────────┴──────────────┐
                    │         APPLICATION         │  use cases
                    │   orchestrates via PORTS    │  0 Roblox API
                    └──────────────▲──────────────┘
                                   │ implements the ports
      ┌────────────────────────────┴────────────────────────────┐
      │                        ADAPTERS                         │
      │   DataStore · attributes · Humanoid · Marketplace        │
      └─────────────────────────────────────────────────────────┘
                                   ▲
                    ┌──────────────┴──────────────┐
                    │         COMPOSITION         │  the only wiring
                    └─────────────────────────────┘
```

## The dependency rule

Arrows point inwards only.

| Layer         | May depend on                                    | Never knows about            |
| ------------- | ------------------------------------------------ | ---------------------------- |
| `Domain`      | nothing                                          | Roblox, network, persistence |
| `Application` | `Domain`, ports                                  | Roblox, instances            |
| `Adapters`    | `Domain`, ports, Roblox                          | the use cases                |
| `Composition` | everything                                       | —                            |
| `Client`      | `Domain` (read only), `Config`, network contract | server logic                 |

Two greps enforce it in practice:

```bash
grep -r "game:GetService" src/Shared/Domain        # must return nothing
grep -r "Instance.new"    src/Server/Application   # must return nothing
```

The rule is not bureaucracy. It is what lets the entire rule set run outside
Studio: a module that never touches an API has nothing to mock.

## Layout

Folder names under `Domain/` follow the areas of the rules, not the layers — one
folder per subject, each holding the modules that decide something about it.

```
src/
├─ Shared/                     → ReplicatedStorage.Shared
│  ├─ Config/                  The only source of constants
│  │  Balance · progression tables · catalogues · monetization · Themes/
│  ├─ Domain/                  THE RULES (pure Luau, tested)
│  │  ├─ <Subject>/            One folder per area of the rules
│  │  ├─ Economy/              Catalogues, prices, purchase validation
│  │  ├─ Monetization/         Grants, receipts, boosts, schedules, codes
│  │  ├─ Profile/              The persisted entity and its schema migration
│  │  └─ Support/              Result · Format
│  ├─ Net.luau                 The shared network contract
│  └─ Signal.luau
│
├─ Server/                     → ServerScriptService.Server
│  ├─ Application/             USE CASES (depend on ports only)
│  │  ├─ Ports.luau            The contracts, as types
│  │  ├─ SessionRegistry       Volatile state, never persisted
│  │  ├─ Snapshot              The presentation model sent to the client
│  │  ├─ RewardApplier         The shared path of every reward
│  │  └─ UseCases/             One file each
│  ├─ Adapters/                ROBLOX IMPLEMENTATIONS
│  │  ├─ Persistence/          DataStore · InMemory
│  │  ├─ Replication/          Attributes and leaderstats · Notifications
│  │  └─ Roblox/               Character actuator, probe, teleporter,
│  │                           Marketplace, logger
│  └─ Composition/             Container · Adapters · Bootstrap · bindings
│
└─ Client/                     → StarterPlayerScripts.Client
   ├─ State.luau               Local mirror of the replicated state
   ├─ Controllers/             Input, prediction, effects
   └─ UI/                      Theme · Widgets · HUD · windows
```

A use case is one file. The list of files in `UseCases/` is the list of things a
player can cause to happen, which makes it the cheapest documentation in the
repository.

## Ports

Declared as types in `Application/Ports.luau`, implemented twice: by a Roblox
adapter in production, by a double in tests.

| Port                          | Role                         | Production                 | Test                    |
| ----------------------------- | ---------------------------- | -------------------------- | ----------------------- |
| `ProfileRepository`           | load / save                  | DataStore adapter          | in-memory fake          |
| `StatsPublisher`              | replicate state              | attributes and leaderstats | recording fake          |
| `Notifier`                    | player messages              | remote event               | recording fake          |
| `MovementActuator`            | apply state to the character | Humanoid adapter           | recording fake          |
| `Teleporter`                  | move the character           | CFrame adapter             | recording fake          |
| `PassGateway` / `Marketplace` | passes and purchases         | MarketplaceService         | scripted fake           |
| `Clock`                       | time                         | `os.time` / `os.clock`     | a clock the test drives |

The clock is a port for the same reason the DataStore is one. A rule that reads
`os.time()` directly cannot be tested at a date of the test's choosing, and
expiries, streaks and cooldowns are exactly the rules worth testing.

Two clocks, not one: an absolute epoch for anything that must survive a
disconnection, and a monotonic reading for durations that only make sense within
a session. Using the wall clock for a cooldown breaks when the system time moves;
using a monotonic clock for an expiry breaks on reconnect.

## The composition root

`Composition/Container.luau` is the **only** file that assembles anything:
configuration → domain objects → use cases, with ports plugged into adapters.
Everything else receives what it is handed.

```lua
local container = Container.new({ ports = fakePorts })
container.useCases.buyUpgrade:run(player, "someUpgrade")
```

Integration tests mount that same container with doubles, so the production
wiring is covered by the suite rather than by hope. A use case that was added but
never wired fails a test instead of failing in Studio.

Three details worth copying:

**Dependencies are cloned, not shared.** Each use case is built with
`setmetatable(table.clone(dependencies), UseCase)`. Setting a metatable on the
caller's table directly makes every use case share one metatable, and the last
one built silently wins.

**The container takes its configuration as an argument.** Defaulting to the real
one is a convenience for production, not a dependency: a test that needs a
three-step progression passes a three-step table instead of bending the real one.

**The composition root decides what exists.** Development-only affordances are
appended to the configuration by the container when it is built in development
mode, and the bootstrap is the only place that reads the environment. A published
build does not contain them, so nothing has to be remembered before shipping.

## Structural decisions

The ones that would be expensive to reverse.

**Progress is measured by the server.** The client never sends a gain. A loop
samples the real position of the character and caps the credited displacement to
what is physically reachable in the elapsed time. A teleport or a client-side
multiplier is therefore worth nothing, and the check is one comparison rather
than an anti-cheat subsystem.

**Volatile state never reaches the profile.** Anything belonging to a single
attempt lives in a session registry; the profile holds only what survives a
disconnection. Deciding this once removes a class of exploit — there is no
"disconnect to keep it", because it was never anywhere but memory.

**State is replicated through attributes, not RemoteEvents.** The server writes
attributes on the player, the engine replicates them, the client listens. Less
traffic, no possible desync between a snapshot and an event, and the live state
is readable in the Studio explorer while playing.

**Comfort is client, authority is server.** Input, prediction and effects run on
the player's machine so control has no latency; the server revalidates whatever
matters. The split is decided per action, not once for the game: an action that
costs nothing may be predicted, an action that pays out may not.

**Movement speed is bounded, whatever the number on screen says.** A body moving
fast enough crosses a wall between two frames and the collision is never
evaluated. An inverse exponential lets a displayed counter grow without bound
while the real speed stays under a ceiling. Balance is a design problem;
tunnelling is a physics problem, and only one of the two can be fixed by tuning.

**A failed load never overwrites a save.** If reading persistence fails, the
session is marked unsaveable: the player can play, but existing progress is
protected. The reverse — defaulting to an empty profile and saving it — destroys
accounts, and does so silently.

**Every reward takes one path.** Purchases, daily rewards, chests and codes all
produce the same declarative grant and go through one applier that credits,
republishes, notifies and saves. Adding a revenue source then needs no new logic,
and no source can quietly forget to persist what it just handed out.

## Tests

- `Domain` and `Application` run **outside Studio** through a harness that
  rebuilds the Roblox tree from `default.project.json` and provides `script`,
  `require` and `game:GetService`;
- production code knows nothing about that harness;
- adapters are deliberately thin and are not covered: they hold no rules, and a
  test of them would only assert that the engine does what the engine does.

The harness reading `default.project.json` matters more than it looks: the test
tree and the real tree cannot drift, because they are generated from the same
file.

See `DEVELOPMENT.md` for the commands and the conventions.
