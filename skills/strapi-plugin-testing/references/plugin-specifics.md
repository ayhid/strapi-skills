# Plugin specifics (Strapi v5)

Read this when working on plugin server code or admin code. For each part of a plugin:
what to keep thin, what to extract, and what to prove where. Then the fixture app and
integration harness.

Strapi APIs move between minor versions. Where this file shows an API, check it against
the Strapi version in the fixture app's `package.json`. If something behaves differently
from what you expect, that's a finding for an integration test, not a reason to mock.

## Contents
1. Server entry and registration
2. register and bootstrap
3. Config
4. Routes, controllers, policies, permissions
5. Services, public and private
6. Document service middlewares and lifecycles (hooks)
7. Content types and host requirements
8. Admin side
9. The fixture app
10. The integration harness
11. Package and compatibility

## 1. Server entry and registration

`server/src/index.ts` exports `{ register, bootstrap, destroy, config, contentTypes,
routes, controllers, services, policies, middlewares }`. Registration is wiring, so
test it *with* the code, at integration level, in one boot smoke test:

```ts
it('registers what the plugin declares', async () => {
  const strapi = await getStrapi();
  expect(strapi.plugin('router')).toBeDefined();
  expect(strapi.contentType('plugin::router.route')).toBeDefined();
  expect(strapi.plugin('router').service('resolver')).toBeDefined();
});
```

One test for the lot; don't write a test per key.

## 2. register and bootstrap

Keep both thin: they call named functions (`registerDocumentMiddleware(strapi)`,
`seedDefaultSettings(strapi)`). Any decision inside them (what to seed, which UIDs to
watch based on config) is a pure function with unit tests.

**Bootstrap idempotence** is an integration test, because Strapi restarts run bootstrap
again against existing data:

```ts
import server from '../../server/src';

it('bootstrap twice changes nothing', async () => {
  const strapi = await getStrapi();             // already bootstrapped once by boot
  const before = await snapshotPluginState(strapi);  // settings rows, permissions, index size
  await server.bootstrap({ strapi });
  expect(await snapshotPluginState(strapi)).toEqual(before);
});
```

## 3. Config

```ts
// server/src/config/index.ts
export default {
  default: { strategy: 'prefix-except-default', trailingSlash: false },
  validator: (config) => validateRouterConfig(config), // throws with a clear message
};
```

- **Validation** → unit. `validateRouterConfig` is a pure function; test valid and invalid
  inputs, including the message text a host developer will see.
- **Merging** → one integration test: the fixture app sets a host value in
  `config/plugins.ts`; assert `strapi.plugin('router').config('strategy')` returns it
  and an unset key keeps the default.
- **Domain code takes config as an argument**, never reads `strapi.plugin().config()`
  itself. Adapters read config and pass it in.

## 4. Routes, controllers, policies, permissions

Controllers are three lines: parse input, call a service/use-case, shape the response.
If a controller has an `if` about business rules, extract it.

Content-API routes are mounted under `/api/<plugin-name>/…` and are closed by default
(users-permissions decides); admin routes are under `/<plugin-name>/…` and need an admin
JWT plus any `admin::hasPermissions` policy. Check the actual prefix in your fixture app.

Prove at integration, over HTTP:
- **Route exposure** — each declared route answers at its path with the right method.
- **Permission matrix** — table-driven, so the matrix is visible in one place:

```ts
const matrix = [
  { route: 'GET /api/router/resolve', as: 'public',        expect: 200 },
  { route: 'GET /api/router/resolve', as: 'authenticated', expect: 200 },
  { route: 'POST /router/rebuild',    as: 'public',        expect: 401 },
  { route: 'POST /router/rebuild',    as: 'editor',        expect: 403 },
  { route: 'POST /router/rebuild',    as: 'super-admin',   expect: 200 },
];
it.each(matrix)('$as → $route = $expect', async ({ route, as, expect: status }) => {
  const [method, path] = route.split(' ');
  const res = await request(server())[method.toLowerCase()](path).set(await authFor(as));
  expect(res.status).toBe(status);
});
```

- **Custom policy logic** → if it decides something, extract the decision as a pure
  function (unit); prove the policy is attached and enforced via the matrix.

## 5. Services, public and private

- A **public service** is anything another plugin or the host may call via
  `strapi.plugin('x').service('y')`. It's a contract: test it at integration through
  that exact lookup, with real data.
- A **private service** that only orchestrates domain logic over ports is tested as a
  use-case in unit tests with in-memory ports.
- Services built with `({ strapi }) => ({ … })` get Strapi injected. Don't use the
  global `strapi` inside domain code.

## 6. Document service middlewares and lifecycles (hooks)

In v5, prefer document service middlewares (`strapi.documents.use(...)`, registered in
`register`) for reacting to content changes; DB lifecycles fire per row and miss the
document-level view (draft/published pairs, locales).

Split each hook into:
- **Scope guard** — "does this hook care about this uid + action?" → pure function, unit.
- **Reaction** — "given this document, what changes?" → pure function, unit.
- **Adapter** — the middleware itself, three lines: guard, call, persist. → integration.

What integration must prove, against real Strapi:
- The hook fires for the actions you depend on: `create`, `update`, `publish`,
  `unpublish`, `delete`, `discardDraft` — **check each**, don't assume which actions a
  host operation triggers (e.g. whether `create` with `status: 'published'` also fires
  `publish` in your version).
- **Hook scope**: it does nothing for UIDs and actions outside its scope. Create and
  publish a document of an unrelated fixture type and assert the plugin's state is untouched.
- Drafts never leak into published-only state; each locale is handled separately.

## 7. Content types and host requirements

- The plugin's **own content types** are covered by the registration smoke test and by
  whatever behaviour uses them. Don't test the schema JSON itself.
- **What the plugin expects of host content types** (e.g. an enabled `slug` field,
  i18n on, draft & publish on) is an inbound contract. Validate it at bootstrap with a
  pure function (`checkHostContentType(schema)` → list of problems; unit tested), and
  prove at integration that a non-conforming fixture type produces a clear error or
  warning rather than a crash later.

## 8. Admin side (kept light in V1)

- Pure helpers (formatters, view-model mappers, reducers) → unit tests.
- Components: only where they hold real logic; render with the API mocked at the
  plugin's own fetch wrapper, never `@strapi/admin` internals.
- Admin API endpoints are server routes — covered by the permission matrix, not by
  admin-side tests.

## 9. The fixture app

A minimal Strapi v5 app that exists only to host the plugin under test. It's part of the
plugin, versioned with it, and reviewed like code. In plugin monorepos it is often called
`playground` (e.g. `apps/playground`); that app is the fixture app — don't create a second one.

- **Minimal**: only the content types the plugin needs to be exercised (e.g. one fake
  `page` type with `title`, `slug`, i18n and draft & publish), plus one unrelated type to
  prove hook scope. No production schemas copied in.
- **Locales** the tests need (default plus at least one other) are created in the
  harness, not by hand.
- **Plugin loaded as a host would**: `config/plugins.ts` enables the plugin and resolves
  it through its package entry (built output / `exports`), not by importing `src/`.
- **Test database**: a disposable SQLite file per run (or the project's test DB).
  Configured via `config/env/test/database.ts` so dev data is never touched.
- **When the plugin lives inside a host backend** (`src/plugins/<name>`), the fixture app
  still sits next to the plugin and points at it; don't run plugin integration tests
  against the host app, which drags its schemas, data and other plugins in.

## 10. The integration harness

Lives in `tests/support/harness.ts`. Integration tests import it; unit tests never do.

```ts
// tests/support/harness.ts — check the API against your Strapi version
import { compileStrapi, createStrapi } from '@strapi/strapi';
import path from 'node:path';

let instance: any;
const appDir = path.resolve(__dirname, '../../fixture-app');

export async function getStrapi() {
  if (!instance) {
    const ctx = await compileStrapi({ appDir });
    instance = await createStrapi(ctx).load();
    instance.server.mount();
  }
  return instance;
}

export async function stopStrapi() {
  if (!instance) return;
  await instance.destroy();
  instance = undefined;
}

export const server = () => instance.server.httpServer;
```

What the harness must provide:
- **Boot once per worker**, not per test. Strapi is a process-wide singleton: run
  integration files in a single worker (`--runInBand` / `poolOptions.forks.singleFork`)
  or give each worker its own DB file.
- **Reset** between tests: delete documents of the fixture types (and the plugin's own
  types) through `strapi.db.query(uid).deleteMany({})`. Resetting is not faking.
- **Factories**: `createPage({ slug, locale, status })` via `strapi.documents(uid).create`
  and `.publish`. Factories use the real API and return real documents.
- **Auth helpers**: `authFor('public' | 'authenticated' | 'editor' | 'super-admin')`
  returning headers — users-permissions JWTs for content-API roles, admin JWTs for admin
  roles, created through Strapi's own services.
- **Speed**: the integration loop must stay fast enough that agents actually run it. If a
  boot takes too long, fix the harness (smaller fixture app, SQLite, single boot), don't
  skip the layer.

## 11. Package and compatibility

- `peerDependencies` declares the supported `@strapi/strapi` range; the fixture app pins
  one version inside it. A compatibility matrix across versions is out of V1.
- What you ship is what you test: the fixture app should consume the plugin's built
  package entries. Full packed-tarball tests are a later step; don't let the fixture app
  import private source paths in the meantime.
