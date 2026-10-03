---
name: strapi-plugin-testing
description: How to plan, build, test and review Strapi v5 plugins so each behaviour is proven at the right level — pure logic in fast unit tests, Strapi data behaviour (filters, populate, draft & publish, locales, permissions) against a real Strapi fixture app, consumer-facing shapes as contracts, one or two E2E journeys. Use whenever you plan a feature or phase in a Strapi plugin; write or change plugin server code (services, controllers, routes, policies, lifecycles, document service middlewares, register, bootstrap, config); write, fix, debug or review tests in a plugin; or chase a failing test or bug report in one — even if the user never says "testing". Not for Strapi content modelling or admin-panel usage questions, or frontend-only work in the app that consumes Strapi.
---

# Strapi plugin testing

Agents drift toward green tests rather than true ones: mocking `strapi.documents` so a
filter "works", asserting the calls a function makes, burying logic in controllers,
skipping the integration layer because it is slow, proving the same case three times.
This skill exists to stop that. One sentence carries it:

> **Put logic where it can be tested without Strapi, test your use of Strapi against a
> real Strapi, and treat everything others depend on as a promise.**

## The three questions — ask them of every piece of code

1. **Whose behaviour is this?** Mine → I test it. Strapi's → I don't (I test *my use* of it).
2. **Does it need Strapi to be true?** No → unit test. Yes → integration test in the
   plugin's real fixture app. Never a mock of Strapi standing in for "yes".
3. **Does someone outside depend on it?** Yes → it is a contract; pin its shape.

If the honest answer to question 2 is "yes" for most of the behaviour you are adding,
the logic is in the wrong place. Extract it before writing tests.

## Design rules that make the questions answerable

- **Framework at the edges, logic in the centre.** Controllers, services, lifecycles and
  document middlewares are thin adapters: read input, call a pure function, persist or
  respond. Decisions (normalising, matching, choosing, validating, building) live in
  framework-free domain modules that never import `@strapi/*` or touch `strapi`.
- **Mock a boundary you own, never the raw framework.** When domain code needs data,
  give it a small port you define (`RouteIndex.findByPath`), fake that port in unit
  tests, and verify the real adapter against real Strapi with the *same* contract suite.
- **Fake Strapi for plumbing only** — config, logging, looking up your own services.
  Never fake data behaviour: filters, populate, draft & publish, locales, permissions,
  relations. A fake that returns what you told it to proves nothing about Strapi.
- **Inject Strapi, don't reach for the global.** Use the `({ strapi }) => ({...})`
  factory shape and pass dependencies into domain functions. Keep one minimal shared
  fake rather than a bespoke mock per file.
- **Assert outcomes, not call sequences.** "The route resolves to page 42" survives a
  refactor; "`findMany` was called once with `{ filters: … }`" mirrors the code.

## Layers at a glance

| Layer | Proves | Where |
|---|---|---|
| Unit (many, fast) | Business rules, config validation, admin helpers, domain decisions; properties for invariants | Domain modules, no Strapi |
| Admin components and services | Each component rendered with its feature service mocked (hooks covered that way); each service against a mocked `getFetchClient` | `admin/src`, per `fullstack-standards:fullstack-testing` |
| Integration | Registration, bootstrap idempotence, route exposure, config merging, hook scope, public services, permission matrix, everything data-shaped | Real Strapi booted from the plugin's fixture app, real DB |
| Contract | Response shapes consumers rely on; what the plugin requires of host content types | Schema checked at integration level |
| E2E (1–2) | A whole journey works end to end | Fixture app over HTTP |

Each case is proven **once**, at the lowest layer that can observe the failure. A bug
caught high means a test missing low.

## Workflow

1. **Locate yourself.** Read the project profile first: the
   `<!-- project-profile:start -->` block in `AGENTS.md`, written by
   `fullstack-standards:project-profile`, names the plugin root, fixture app, test runner
   and the unit, integration and rules commands. No profile? Suggest creating one, and
   meanwhile find them in `package.json` scripts, `TESTING.md` and `CLAUDE.md`. Project
   conventions win over the defaults in this skill.
2. **Planning a feature or phase?** Use `references/planning-template.md`: every task
   declares its layer and the test that proves it, before code exists.
3. **Starting a feature?** Work double-loop (`references/double-loop-tdd.md`): one failing
   integration test outside, red-green-refactor units inside, outer test goes green last.
4. **Writing or placing any test?** Read `references/layers-and-mocking.md` — what each
   layer owns and exactly where mocks are trusted and where they lie.
5. **Touching register/bootstrap/routes/config/policies/middlewares/lifecycles/content
   types or admin code?** Read `references/plugin-specifics.md` for what to prove and how
   the fixture-app harness works. For admin code also load
   `fullstack-standards:fullstack-testing`, and for a third-party service its
   `references/third-party-services.md`.
6. **Logic with invariants** (idempotence, round-trips, totality, termination) or
   index-style state? Read `references/property-based-testing.md`.
7. **Fixing a bug or a failing test?** First write the lowest-level test that reproduces
   it. If the bug was only visible at integration/E2E, ask why no unit test could see it —
   usually logic that should be extracted. Never "fix" a test by loosening its assertion
   or adding a mock until it passes; find out which side is wrong.
8. **Reviewing tests or agent output?** Use `references/review-checklist.md`.
9. **Before you say you're done:** run the unit tests, the integration tests that cover
   what you touched, and the rules package (below). Report what ran and what didn't.

## The rules package

Deterministic checks are not in this skill. They are the fullstack-standards
architecture checker with its `strapi-plugin` and `strapi-admin` presets, configured in
`.claude/fullstack-standards.json`. With the fullstack-standards plugin installed they
run as hooks while you work (an edit that breaks a rule is denied); the plugin's
`test:rules` script runs the same checks in CI
(`npx --yes github:ayhid/fullstack-standards#<tag> --all .`). Run it before finishing.
It enforces:

- **Domain is framework-free** (`domain-framework-free`) — `server/src/domain/**` never
  imports `@strapi/*` or touches `strapi`.
- **Units stay units** (`unit-stays-unit`) — `tests/unit/**` never imports the
  integration harness or `@strapi/strapi`, never calls `createStrapi`.
- **No faked data access** (`no-fake-data-access`) — no unit test assigns a double to
  `documents`, `db` or `entityService`.
- **Third-party SDKs only in adapters** (`sdk-importers`, `no-sdk-in-specs`).
- **Admin layering and tests** (`component-imports`, `hook-imports`,
  `component-data-hooks`, `component-test`, `service-test`, `no-render-hook`).

Not automated: "server changes come with tests" — check it yourself before finishing.

Its messages say what is wrong, which principle, and how to fix — follow them rather than
working around them. If a rule fires and you believe it is a false positive, say so to
the user instead of restructuring code to dodge the check. If the project has no config
or `test:rules` script yet, say that plainly and suggest adding them; don't invent one.

## Default file layout

Use the project's layout if it declares one. Otherwise (and the rules package assumes this):

```
<plugin>/
  server/src/
    domain/            # pure logic + port interfaces. No @strapi imports, no `strapi`.
    adapters/          # port implementations over strapi.documents / strapi.db
    services/ controllers/ routes/ policies/ middlewares/  # thin adapters
    register.ts bootstrap.ts config/ index.ts
  admin/src/
    lib/               # query-client.ts (one shared client), query-keys.ts
    features/<f>/      # services/ (getFetchClient) → hooks/ → components/, tests beside them
  tests/
    unit/              # *.test.ts — domain + admin helpers + config validator
    integration/       # *.int.test.ts — boots the fixture app
    contracts/         # shared port contract suites + response schemas
    e2e/               # one or two journeys
    support/           # fake-strapi.ts, in-memory port fakes, factories, harness
  fixture-app/         # minimal Strapi v5 app, versioned with the plugin
```

## Plugin as a product

Test it the way a host sees it: only through what the plugin declares — its routes, its
public services, its config keys, its content types. Never reach into private module
state from an integration test. The fixture app is part of the plugin: minimal (only the
content types the plugin needs to be exercised), versioned with it, and booted the same
way every time. What you ship is what you test — the fixture app should load the plugin
through its package entry points, not by importing `src/` directly.

## Governance

- Every test earns its place. If two tests at different layers fail for the same reason,
  delete the higher one unless it proves wiring the lower one can't.
- Test-first where the test shapes the design (domain rules, ports, contracts);
  test-with is fine for pure wiring (a route definition, a controller one-liner) as long
  as an integration test exercises it.
- A test that cannot fail is not a test: no properties that reimplement the function, no
  snapshot of a mock's return value, no assertion on something you just set.
