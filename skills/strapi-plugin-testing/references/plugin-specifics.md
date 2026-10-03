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
again against existing data. Prove it with a real restart on the same database file, not
by importing `server/src` and calling `bootstrap` by hand (that runs source, not the built
entry, and Strapi refuses a second `strapi.plugin(x).bootstrap()` call anyway):

```ts
it('a restart changes nothing', async () => {
  const before = await snapshotPluginState(await getStrapi()); // settings rows, permissions, index size
  await stopStrapi();
  const strapi = await getStrapi();             // boots again against the same SQLite file
  expect(await snapshotPluginState(strapi)).toEqual(before);
});
```

This needs a file database, not `:memory:`.

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
token plus any `admin::hasPermissions` policy. Routes exported as a plain array default to
`type: 'admin'`; a router can override `prefix`, and the host can change `/api`
(`config/api` `rest.prefix`). Assert what is actually mounted with
`strapi.server.listRoutes()` rather than guessing.

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
  { route: 'GET /api/router/resolve', as: 'api-token',     expect: 200 },  // content-API token
  { route: 'POST /router/rebuild',    as: 'admin-token',   expect: 200 },  // admin API token
];
it.each(matrix)('$as → $route = $expect', async ({ route, as, expect: status }) => {
  const [method, path] = route.split(' ');
  const res = await request(server())[method.toLowerCase()](path).set(await authFor(as));
  expect(res.status).toBe(status);
});
```

`public → 200` only holds once the harness grants the Public role that action (update
the role's permissions through users-permissions' services at boot); the closed default
is itself a row worth keeping.

- **Request/response schemas** → routes can declare zod `request` (query, params, body)
and `response` schemas; when they exist, they are the contract — assert responses parse.
Run the fixture app with `rest.strictParams` and `documents.strictParams` on in
`config/api`, so you prove the plugin works for hosts that enable them (custom query
params must be registered with `strapi.contentAPI.addQueryParams` / `addInputParams`).
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
  `unpublish`, `delete`, `discardDraft`, `clone` — **check each**, don't assume which
  actions a host operation triggers. Known trap (5.x): `create`/`update` with
  `status: 'published'` publish internally, so the middleware sees only `create`/`update`
  with `params.status === 'published'`, never a `publish` action. And `publish`,
  `unpublish`, `discardDraft` don't exist on types without draft & publish.
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
- Components: only where they hold real logic. Render with Strapi's helpers from
  `@strapi/strapi/admin/test` (`render`, `renderHook`, `screen`, and an msw `server`),
  which supply the admin providers. Mock the API at the network level (`server.use(...)`),
  since plugins fetch through `useFetchClient`; never mock `@strapi/admin` internals.
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
  Configured via `config/env/test/database.ts` so dev data is never touched. `:memory:`
  (the official guide's default) is faster but can't prove restart behaviour. Delete a
  stale `dist/` from `strapi develop` before tests: its compiled `config` can override the
  test database config.
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
    // compileStrapi builds dist/, which is what lets TS config files load at all
    // (the runtime config loader only reads .js/.json). It process.exit(1)s on type
    // errors, killing the test worker silently: run `tsc` separately, or pass
    // { appDir, ignoreDiagnostics: true }.
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
- **Env**: boot needs `APP_KEYS`, `ADMIN_JWT_SECRET`, `API_TOKEN_SALT`,
  `TRANSFER_TOKEN_SALT`, `JWT_SECRET` and `ENCRYPTION_KEY` (any test values), plus
  `STRAPI_DISABLE_CRON=true`. Set them in the test runner's setup file, not the shell.
- **Boot once per file**, not per test, and stop it: every integration file has
  `afterAll(stopStrapi)`. Jest and Vitest (default `isolate: true`) give each file its
  own module registry, so the module-level `instance` above does *not* survive across
  files; without `stopStrapi` the old instance leaks its DB connection. Strapi is a
  process-wide singleton: run files serially (Jest `--runInBand`, Vitest
  `fileParallelism: false`) or give each worker its own DB file. To share one boot
  across files, use Vitest `isolate: false`, or the official guide's single entry
  (`tests/app.test.js` boots once and `require`s the other test files).
- **Reset** between tests: delete documents of the fixture types (and the plugin's own
  types) through `strapi.db.query(uid).deleteMany({})`. Resetting is not faking.
- **Factories**: `createPage({ slug, locale, status })` via `strapi.documents(uid).create`
  and `.publish`. Factories use the real API and return real documents.
- **Auth helpers**: `authFor('public' | 'authenticated' | 'editor' | 'super-admin' | …)`
  returning headers, created through Strapi itself:
  - content-API roles: `await strapi.plugin('users-permissions').service('jwt').issue({ id })`
    (always `await`: it is async when `jwtManagement: 'refresh'`);
  - admin roles: admin auth is session-based, so log in for real (`POST /admin/login`,
    read `body.data.token`) or use `strapi.sessionManager('admin')`. There is no
    `createJwtToken` any more;
  - API tokens: `strapi.service('admin::api-token-content-api')` / `'admin::api-token-admin'`
    (the plain `'api-token'` service is deprecated).
- **Speed**: the integration loop must stay fast enough that agents actually run it. If a
  boot takes too long, fix the harness (smaller fixture app, SQLite, single boot), don't
  skip the layer.

## 11. Package and compatibility

- `peerDependencies` declares the supported `@strapi/strapi` range; the fixture app pins
  one version inside it. A compatibility matrix across versions is out of V1. CI runs on
  a Node version Strapi supports (5.56: `>=20 <=26`; docs recommend even LTS releases).
- What you ship is what you test: the fixture app should consume the plugin's built
  package entries. Full packed-tarball tests are a later step; don't let the fixture app
  import private source paths in the meantime.
- Because the fixture app loads `dist`, run `strapi-plugin build` before the integration
  suite (or `strapi-plugin watch` while developing), or you are testing a stale build.
  `strapi-plugin verify` checks the package output before publishing; `watch:link`
  (yalc) is for linking into a separate host app, not needed for an in-repo fixture app.
