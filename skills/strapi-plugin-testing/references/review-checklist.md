# Review checklist

For reviewing tests and plugin code, whether you wrote them or another agent did. These
are judgment rules; the deterministic ones are in the rules package, so run it first and
don't re-check what it already checks.

For each finding report: **file:line → what's wrong → which principle → the concrete fix**
(the move to make, not "consider improving"). Order by severity: false confidence first
(tests that pass while the behaviour is broken), then misplaced layers, then duplication
and noise.

## 1. Extraction — is logic where it can be tested?

- [ ] Controllers, services, middlewares, lifecycles and bootstrap contain no business
      decisions. Any `if`/`switch`/loop about the domain → extract into `domain/` and unit test.
- [ ] Domain modules don't import `@strapi/*`, don't touch `strapi`, don't read config
      themselves (config arrives as an argument).
- [ ] Data access goes through a port the plugin owns, not `strapi.documents` scattered
      through logic.
- [ ] Plugin code doesn't use `strapi.entityService` or `strapi.query` (both deprecated in
      v5): Document Service, or `strapi.db.query` for low-level row access.

## 2. Mocks — are they telling the truth?

- [ ] No unit test fakes `strapi.documents`, `strapi.db.query`, `entityService`, filters,
      populate, draft & publish, locales or permissions. (Highest-severity: these tests
      are green regardless of whether the real query works.)
- [ ] Every port fake passes the same contract suite as the real adapter. A fake with no
      contract suite behind it is an unverified assumption.
- [ ] Unit tests use the shared fake Strapi, not ad-hoc `jest.fn()` trees.
- [ ] No test asserts on a value the test itself just put into a mock (tautology).

## 3. Assertions — outcomes, not call sequences

- [ ] Tests assert results (returned value, HTTP response, stored state), not
      `toHaveBeenCalledWith` on internals. Call assertions are fine only at a boundary
      where the call *is* the outcome (e.g. "an email was sent" via the mail wrapper).
- [ ] Snapshot tests don't freeze mock output or volatile fields (`id`, timestamps).
- [ ] Error cases assert the error a caller sees (status, message), not that a `throw`
      happened somewhere.

## 4. Layering — is each case at the lowest layer that can see it?

- [ ] Pure-function edge cases are units, not integration loops or E2E steps.
- [ ] Integration tests exist for every Strapi-dependent claim the code makes: hook
      firing per action, hook scope, drafts not resolving, per-locale behaviour, route
      exposure, permission matrix, config merging, bootstrap idempotence.
- [ ] Integration tests go through what the plugin declares (routes, public services),
      not private modules.
- [ ] E2E is one or two journeys, not a regression suite.

## 5. Duplication — does every test earn its place?

- [ ] The same case isn't proven at several layers. Keep the lowest that can observe the
      failure, plus the higher one only if it proves wiring the lower can't.
- [ ] Several example tests that are instances of one invariant → one property plus a
      couple of named examples.
- [ ] No test re-proves Strapi itself (that `findMany` filters, that `publish` publishes).

## 6. Properties — are they real?

- [ ] No property reimplements the function under test.
- [ ] Arbitraries reach the edges (empty, separators, encodings, default locale).
- [ ] `fc.pre` doesn't discard most inputs.
- [ ] Failure output keeps the seed/path; shrunk counterexamples become named examples.

## 7. Fixture app and harness

- [ ] Fixture app is minimal and loads the plugin through its package entry.
- [ ] Integration tests reset state between tests and don't depend on run order.
- [ ] No unit test imports the harness or boots Strapi.

## 8. Admin data layer and third parties

Rules from `fullstack-standards` (see `strapi-plugin-dev/fullstack-standards.md`):

- [ ] Components call feature hooks only: no `getFetchClient`/`useFetchClient`,
      `useQuery`/`useMutation` or query keys in a component.
- [ ] Hooks call services only; only services call `getFetchClient()`; keys come from
      `lib/query-keys.ts`; every mutation invalidates its resource root.
- [ ] Every rendered tree uses the plugin's one shared `queryClient`.
- [ ] Every component has a render test with its service module mocked; no `renderHook`,
      no test file under `hooks/`. Asserting which service function ran is the
      boundary-call exception of §3, not a call-sequence smell.
- [ ] Every service has a test with `getFetchClient` mocked, asserting the exact request
      and the mapped result.
- [ ] A provider SDK is imported only by its adapter, and no spec `jest.mock`s it.

## 9. Governance

- [ ] For each bug fix: is there a test at the lowest layer that reproduces it? If the
      bug was only visible high, is the missing low-level test (or extraction) noted?
- [ ] Loosened assertions, `skip`, `only`, increased timeouts or new mocks added "to make
      it pass" are called out explicitly. They need a reason, or they need reverting.
