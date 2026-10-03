# Double-loop TDD

Read this when starting a feature. Two loops, one inside the other:

```
OUTER (integration, slow, few)          INNER (unit, fast, many)
1. Write one failing integration  ──►   2. Red: smallest failing unit test
   test for the feature, as the          3. Green: simplest code that passes
   host sees it.                         4. Refactor, tests green
                                         …repeat until the outer test can pass
5. Wire the adapter. Outer goes green. ◄──
6. Refactor across layers. Delete any test that now duplicates another.
```

## Outer loop

- Write **one** integration test that states the feature in host terms. "When an editor
  publishes a page with slug `about` in `fr`, `GET /api/router/resolve?path=/fr/about`
  returns that page." It fails because the feature doesn't exist yet. Watch it fail for
  the right reason (404 or missing service, not a harness crash).
- Don't write five outer tests up front. Add the next one only when the first is green,
  and only for behaviour that needs Strapi to be true.

## Inner loop

- Derive unit cases from the outer test: what does the domain have to *decide* for that
  to work? (Strip the locale prefix. Normalise the path. Choose the entry for a locale.)
- Each unit test fails first, for the right reason. If it passes immediately, either the
  behaviour already exists (fine, keep or delete) or the test asserts nothing.
- The domain grows behind ports. Use in-memory fakes that pass the shared port contract
  suite (see `layers-and-mocking.md` §5).
- Look for invariants while you're here. If you write the third example of "normalising
  twice equals once", replace them with a property (`property-based-testing.md`).

## Closing the loop

- Write the thin adapter (controller, middleware, real port implementation) last. Run
  the port contract suite against the real adapter.
- The outer test goes green. If it doesn't and every unit is green, something at the
  boundary is wrong — usually an assumption about Strapi. Capture that assumption as a
  contract-suite case or an integration test. Don't patch it with a mock.

## Test-first vs test-with

| Test-first (the test shapes the design) | Test-with (write together, keep honest) |
|---|---|
| Domain rules and decisions | Route definitions |
| Port interfaces and their contract suite | Controller one-liners |
| Config validator messages | `register`/`bootstrap` wiring calls |
| Response contracts consumers will parse | Fixture-app setup |
| Bug reproductions | |

Test-with still means a test exists in the same change; it just doesn't have to come
first. Wiring is proven by the outer integration test, not by unit tests of wiring.

## Bugs

A bug is an outer test you didn't have. Reproduce it at the **lowest** layer that can
see it. If only integration/E2E can see it, also ask which unit test was missing, and
whether logic needs extracting so a unit test could have caught it.
