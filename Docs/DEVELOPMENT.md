# Development

A Roblox project built with Rojo, tested outside Studio, linted and formatted on
every commit. See `ARCHITECTURE.md` for how the code is organised.

## Getting started

```powershell
./scripts/setup.ps1     # installs Rojo, Lune, Selene and StyLua into .tools/
./scripts/check.ps1     # format + lint + build + tests
```

`setup.ps1` downloads the tools locally (`.tools/`, git-ignored), generates the
standard Roblox definition the linter needs, and writes the `sourcemap.json` that
gives the editor autocompletion.

To manage the versions with [Rokit](https://github.com/rojo-rbx/rokit) instead,
`rokit.toml` is already there: `rokit install`.

## Commands

| Command | Effect |
| --- | --- |
| `./scripts/test.ps1` | Run the whole suite |
| `./scripts/test.ps1 <filter>` | Run only the specs whose path contains the filter |
| `./scripts/check.ps1` | Format + lint + Rojo build + tests — run before every commit |
| `./scripts/check.ps1 -Fix` | Format instead of checking |
| `./scripts/serve.ps1` | Serve the project to Roblox Studio |

The tests run **without Roblox Studio**, in tens of milliseconds. That number is
the point: a suite fast enough to run on every save is a suite that actually gets
run.

`check.ps1` also builds the place file outside Studio, so a broken
`default.project.json` is caught before Roblox is even opened. It fails as well if
a configuration file has gone missing — that has happened, and a missing config
otherwise surfaces as a puzzling runtime error much later.

## Opening the project in Studio

1. Install the **Rojo** plugin (Plugins → Manage Plugins).
2. Create an empty place and save it.
3. Run `./scripts/serve.ps1` from the project root.
4. In Studio: *Rojo → Connect*.
5. Start a **server + client** session (Play, or Test → Start with one player).

In Studio without API access, persistence falls back to memory automatically, so
the game still runs; nothing is written and nothing is lost.

## Writing code

### Test first

Every rule starts as a spec in `tests/specs/`, then the implementation.

Domain specs use **their own fixtures** rather than the real configuration:
rebalancing must never break a test. A separate spec checks the real
configuration for internal consistency — that ladders rise, that identifiers are
unique, that no required field is missing.

```lua
-- tests/specs/domain/my_rule.spec.luau
local MyRule = require(Domain.Subject.MyRule)

describe("MyRule", function()
	it("does what it says", function()
		expect(MyRule.compute(2)).toBe(4)
	end)
end)
```

Globals available in a spec: `describe`, `it`, `beforeEach`, `expect`, `Domain`,
`Application`, `Config`, `Shared`, `Server`, `Fakes`, `Tree`.

**Write the test that would have caught the bug, not the one that passes.** A
spec asserting that two regions do not overlap will happily validate a gap
between them. When a defect is found, the spec that reproduces it comes first.

**Pin the intent, not just the arithmetic.** A curve deserves a spec fixing three
reference points, so that retuning a constant surfaces as a failing test rather
than as a bad feeling three days later.

**Integration tests mount the real container with fake ports.** That is what
keeps the production wiring covered: a use case that exists but was never wired
fails a test instead of failing in Studio.

### Where things go

| What you are writing | Where it belongs |
| --- | --- |
| A rule, a computation, a validation | `src/Shared/Domain/` |
| A sequence of actions (load → decide → publish) | `src/Server/Application/UseCases/` |
| A call to a Roblox API | `src/Server/Adapters/` |
| A balancing number | `src/Shared/Config/` |
| Anything displayed | `src/Client/UI/` |

A new use case is declared in `Composition/Container.luau` and, if the player
triggers it, in `Composition/RemoteBindings.luau`.

If a rule needs a Roblox API, it is not a rule yet: the part that decides belongs
to the domain, the part that touches the engine belongs to an adapter, and the
port between them is what makes the decision testable.

### Conventions

- `PascalCase` modules, one per file, returning a single table.
- Comments in English, on the **why** — the *what* is already in the code.
- No magic number outside `Config/`.
- Business failures go through `Result.ok` / `Result.err`; `error()` is reserved
  for contract violations, that is, programming bugs.
- Anything arriving from the network is type-checked before use. A remote is a
  public API and its caller is not necessarily your client.

### User-facing text

No string a player can read is written in a view. Words live in a theme module
that also carries the icons and the palette, so the whole interface can be
renamed and repainted as a data change. Views hold the grammar — sizes, fonts,
layout — which no theme may break.

### Interface sizing

Everything is written in **design pixels** for one reference resolution, and a
single `UIScale` adapts it to the actual viewport. Nothing else in the client
reads the viewport. Sizing in raw pixels cannot serve a phone and a large monitor
at once, and discovering that after building twenty views is expensive.

Two engine details worth knowing before laying anything out:

- a `UICorner` radius is capped by the **smaller** side of what it rounds, so a
  narrow element never gets the radius its container has;
- `ClipsDescendants` clips to the **rectangle**, not to the rounded corners.

Together they rule out the two obvious ways of building a rounded progress bar.
Masking a full-size fill with a gradient works and is worth reaching for first.

## Development-only affordances

Walking a progression curve by playing it is a waste of an afternoon. The project
ships repeatable **development codes** that grant currency, progress or a boost,
redeemed through the normal in-game reward window.

They take exactly the same path as a real promotional code — redeem → grant →
save → snapshot — so what is exercised is the production pipeline, not a shortcut
around it. A cheat that bypasses the pipeline tests nothing and hides the bugs
that matter.

They do not exist on a published server: they live in a table of their own, and
the container only merges them in when it is built in development mode, which the
bootstrap derives from `RunService:IsStudio()`. There is nothing to remember to
strip before shipping — the safety is structural, not a habit.

Any development affordance should follow that shape: **real path, separate data,
enabled by the composition root.**

## Commits

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <imperative description>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`.
Scopes: `domain`, `application`, `server`, `client`, `monetization`, `ui`, `build`.

```
feat(domain): add an agility bonus to the speed curve
fix(application): stop crediting movement through a wall
```

The body says **why**, and what was rejected. A message explaining that a fix was
chosen over a cheaper one, and what the cheaper one broke, is worth reading in a
year; a message restating the diff is not.

`./scripts/check.ps1` must be green before every commit.

## Shipping

1. Create the passes and products on the Roblox site.
2. Copy the identifiers into the monetization configuration — an identifier left
   at `0` should hide the item cleanly rather than break the store.
3. Enable **Studio Access to API Services** in the game settings, for persistence.
4. Review the balancing configuration.
5. Publish from Studio.
