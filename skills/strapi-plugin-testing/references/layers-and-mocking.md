# Layers and mocking

Read this before writing or placing any test. It answers two questions: *which layer
owns this case?* and *may I fake this here?*

## Contents
1. What each layer owns
2. Placing a case — the decision
3. Where mocks are trusted and where they lie
4. The shared fake Strapi
5. Ports: faking a boundary you own, honestly
6. Smells that mean the case is at the wrong layer

## 1. What each layer owns

**Unit** — fast (ms), many, no Strapi, no DB, no network.
- Domain decisions: normalising, matching, choosing, building, merging, ordering.
- Config validation: the plugin's `config.validator` logic, extracted as a pure function.
- Admin helpers: formatting, form-state reducers, mapping API data to view models.
- Use-cases that orchestrate domain logic over ports, run against in-memory fakes.
- Properties for invariants (see `property-based-testing.md`).

**Integration** — real Strapi booted from the plugin's fixture app, real database
(SQLite file or the project's test DB), real HTTP via supertest where routes matter.
- Registration: content types, components, routes, policies, middlewares exist after boot.
- Bootstrap: runs cleanly, and running it twice changes nothing (idempotence).
- Route exposure: each declared route answers at its path; undeclared ones don't.
- Config merging: host config overrides defaults; invalid config fails boot clearly.
- Hook scope: document middlewares / lifecycles fire for the intended UIDs and actions
  only, and ignore everything else.
- Public services: what `strapi.plugin('x').service('y')` promises to other code.
- Permission matrix: role × route → expected status.
- Anything whose truth depends on Strapi's data behaviour: filters, populate, sorting,
  pagination, draft & publish, locales, relations, unique constraints.
- The real adapter behind each port, via the shared port contract suite.

**Contract** — shapes others rely on, checked against real responses.
- Outbound: the JSON your routes return that a consumer (e.g. a Next.js frontend) parses.
  Keep the schema in `tests/contracts/` and assert real integration responses against it.
- Inbound: what the plugin requires of host content types (a `slug` field, i18n enabled,
  draft & publish on). Prove the plugin fails fast with a clear message when a host type
  doesn't meet it.

**E2E** — one or two journeys through the fixture app over HTTP, the way a real client
would do it (e.g. "publish a page, then resolve its path"). E2E proves the pieces are
connected. It does not re-prove rules already covered below it.

## 2. Placing a case — the decision

Walk it in order; stop at the first match.

1. Is this Strapi's behaviour, not mine? (Does `$contains` work? Does `populate` populate?)
   → **No test.** You test your *use* of Strapi, not Strapi.
2. Can it be decided by a pure function given plain inputs? → **Unit.** If it currently
   can't because the logic lives in a controller/service, **extract it first**.
3. Does it depend on what Strapi actually stores, returns, filters, publishes, localises
   or authorises? → **Integration.**
4. Is it a shape another system parses, or a requirement on the host? → **Contract**
   (asserted inside an integration test).
5. Is it only meaningful as a sequence across several surfaces? → **E2E**, and only if no
   integration test already covers the same chain.

A case that fits several layers belongs to the lowest. One test per case.

## 3. Where mocks are trusted and where they lie

| You want to fake… | Verdict | Why |
|---|---|---|
| Plugin config (`strapi.plugin('x').config(k)`) | ✅ fake | Plumbing. Merging itself gets one integration test. |
| Logger (`strapi.log`) | ✅ fake | Plumbing. Don't assert log calls unless logging *is* the feature. |
| Your own service, from another unit | ✅ fake — but prefer a port | You own it; its real behaviour has its own tests. |
| A port you defined (`RouteIndex`) | ✅ fake, in-memory | Only if the same contract suite runs against the real adapter. |
| Third-party HTTP API (mail, search, CDN) | ✅ fake at your client wrapper | It's not yours and not Strapi's. Wrap it; fake the wrapper. |
| `strapi.documents(uid).findMany/findOne/…` | ❌ never | Filters, status, locale, populate are Strapi's semantics. A fake returns whatever you wrote, so the test proves your mock. |
| `strapi.db.query(uid)` | ❌ never | Same reason, plus relations and constraints. |
| Draft & publish, `status`, `publishedAt` | ❌ never | The classic lie: fakes can't model draft/published pairs per locale. |
| Locales / i18n | ❌ never | Per-locale documents and fallbacks are framework behaviour. |
| Permissions, policies, auth | ❌ never | Only real Strapi knows if the route is actually protected. |
| Lifecycle / middleware firing | ❌ never | *Whether* Strapi calls your hook is the thing to prove. The hook's *logic* is a unit test on the extracted function. |

A unit test that needs one of the ❌ rows is telling you the logic isn't separated from
data access yet. Separate it, or move the case to integration.

## 4. The shared fake Strapi

One file, `tests/support/fake-strapi.ts`, shared by every unit test that needs plumbing.
It fakes only the ✅ rows, and throws a teaching error on data access so drift is loud:

```ts
// tests/support/fake-strapi.ts
type FakeOptions = { config?: Record<string, unknown>; services?: Record<string, unknown> };

const forbidden = (what: string) => () => {
  throw new Error(
    `fake-strapi: ${what} is Strapi data behaviour and must not be faked. ` +
      `Extract the logic behind a port and fake the port, or move this case to an integration test.`,
  );
};

export function createFakeStrapi({ config = {}, services = {} }: FakeOptions = {}) {
  const log = { debug() {}, info() {}, warn() {}, error() {} };
  const plugin = () => ({
    config: (key: string, fallback?: unknown) => (key in config ? config[key] : fallback),
    service: (name: string) => {
      if (!(name in services)) throw new Error(`fake-strapi: no fake for service "${name}"`);
      return services[name];
    },
  });
  return {
    log,
    plugin,
    documents: forbidden('strapi.documents()'),
    db: { query: forbidden('strapi.db.query()') },
    entityService: forbidden('strapi.entityService'),
  };
}
```

Keep it minimal. When a test needs more, ask whether it's plumbing (extend the fake) or
data (it doesn't belong in a unit test). Don't build a per-file `jest.fn()` Strapi.

## 5. Ports: faking a boundary you own, honestly

A port is a tiny interface in `domain/` that says what the domain needs, in domain terms:

```ts
// server/src/domain/route-index.ts
export interface RouteIndex {
  put(entry: RouteEntry): Promise<void>;
  remove(documentId: string, locale: string): Promise<void>;
  findByPath(path: string, locale: string): Promise<RouteEntry | null>;
}
```

Two implementations: `adapters/strapi-route-index.ts` (real, over `strapi.documents`)
and `tests/support/in-memory-route-index.ts` (fake). The fake is only trustworthy if both
pass **the same contract suite**:

```ts
// tests/contracts/route-index.contract.ts
export function routeIndexContract(name: string, make: () => Promise<RouteIndex>) {
  describe(`RouteIndex contract — ${name}`, () => {
    it('finds what was put, per locale', async () => {
      const index = await make();
      await index.put(entry({ path: '/about', locale: 'en' }));
      expect(await index.findByPath('/about', 'en')).toMatchObject({ path: '/about' });
      expect(await index.findByPath('/about', 'fr')).toBeNull();
    });
    it('forgets what was removed', async () => { /* … */ });
    it('put is an upsert, not a duplicate', async () => { /* … */ });
  });
}

// tests/unit/route-index.fake.test.ts
routeIndexContract('in-memory', async () => createInMemoryRouteIndex());

// tests/integration/route-index.int.test.ts
routeIndexContract('strapi', async () => createStrapiRouteIndex({ strapi: await getStrapi() }));
```

When the real adapter's behaviour surprises you (case sensitivity, trailing slashes,
locale fallbacks), add the case to the contract suite. The fake then has to match it, and
every unit test using the fake inherits the correction.

## 6. Smells that mean the case is at the wrong layer

- `jest.fn()`/`vi.fn()` standing in for `findMany` with a `filters` object → data behaviour faked.
- `expect(mock).toHaveBeenCalledWith({ filters: … })` → asserting implementation; assert the result.
- A unit test with 30 lines of mock setup and 2 lines of assertion → logic not extracted.
- An integration test that loops over 40 string inputs → that's a unit test (or a property) for a pure function.
- An E2E test checking an edge case of normalisation → push it down to unit.
- The same "draft doesn't resolve" assertion in unit, integration *and* E2E → keep the integration one.
- A unit test importing from `tests/support/harness` or calling `createStrapi` → rule "units stay units".
