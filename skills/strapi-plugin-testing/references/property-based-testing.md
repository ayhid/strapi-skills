# Property-based testing

Read this when logic has invariants, or when the plugin maintains index-style state
(a route index, a cache, a lookup table) that must stay consistent with content.
Examples use `fast-check`; adapt if the project uses another library.

## When a property beats examples

You're writing the third example of the same rule with different data, or the input
space has edges you can't enumerate (unicode, empty segments, repeated slashes, every
locale × strategy combination). Keep a few named examples next to the property for
readability; they document intent, the property hunts edges.

## Good invariants — the shapes that pay off

| Shape | Statement | Example |
|---|---|---|
| Idempotence | `f(f(x)) == f(x)` | `normalizePath(normalizePath(p)) === normalizePath(p)` |
| Round-trip | `parse(build(x)) == x` | per locale strategy: `parseUrl(buildUrl(path, locale, cfg), cfg)` gives back `{path, locale}` |
| Totality | `f` returns a valid result for every input; never throws | `resolve(anyPath, anyIndex)` returns `content` / `redirect` / `notFound` |
| Termination | an iterative process ends | following redirects from any start ends within N hops or reports a loop |
| Invariance | an operation doesn't change what it shouldn't | adding an entry for locale `fr` never changes any `en` resolution |
| Oracle / model | a simple model agrees with the real thing | see stateful pattern below |

```ts
import fc from 'fast-check';

it('normalisation is idempotent', () => {
  fc.assert(fc.property(pathArb, (p) => {
    const once = normalizePath(p);
    expect(normalizePath(once)).toBe(once);
  }));
});

it.each(strategies)('build then parse round-trips — %s', (strategy) => {
  fc.assert(fc.property(normalizedPathArb, localeArb, (path, locale) => {
    const cfg = { strategy, defaultLocale: 'en', locales: ['en', 'fr', 'de'] };
    expect(parseUrl(buildUrl(path, locale, cfg), cfg)).toEqual({ path, locale });
  }));
});
```

Build arbitraries that reach the edges: empty strings, `//`, trailing slashes, `%`
encodings, unicode, the default locale, a locale that looks like a path segment (`/de`).

## The stateful pattern (index-style state)

For a plugin that keeps an index in step with content, a stateful property runs random
sequences of commands against both the real system and a deliberately simple model, and
checks they agree after every step.

```ts
// Model: a plain Map keyed by `${locale}:${path}` — obviously correct, no cleverness.
class Publish implements fc.AsyncCommand<Model, System> {
  constructor(readonly doc: Doc) {}
  check = () => true;
  async run(model: Model, sys: System) {
    await sys.publish(this.doc);
    model.set(key(this.doc), this.doc.documentId);
    await expectAgreement(model, sys);   // every model key resolves the same in the system
  }
  toString = () => `publish(${this.doc.slug}, ${this.doc.locale})`;
}
// …Unpublish, Update (slug change), AddLocale, Delete

fc.assert(
  fc.asyncProperty(fc.commands(allCommandArbs, { maxCommands: 30 }), (cmds) =>
    fc.asyncModelRun(() => ({ model: new Map(), real: freshSystem() }), cmds),
  ),
  { numRuns: 50 },
);
```

- At **unit level**, `System` is the use-case over in-memory ports: fast, many runs.
- At **integration level** (stretch), `System` drives real Strapi via factories. Fewer
  runs (`numRuns: 10–25`), reset the DB in `freshSystem`. This is the strongest proof
  that hooks + index stay consistent under any order of publish/unpublish/update/locale
  changes.

## Traps

- **Reimplementing the function.** `expect(normalizePath(p)).toBe(p.replace(/\/+/g, '/')…)`
  copies the implementation into the test; both are wrong together. Assert a *relation*
  (idempotence, round-trip, invariance) or compare to a model that is simpler by
  construction, not a rewrite.
- **Filtering instead of generating.** `fc.pre(isValid(x))` that rejects most inputs makes
  a slow, weak test. Build an arbitrary that only produces valid inputs.
- **Arbitraries too narrow.** `fc.string()` of ASCII letters never hits `//`, `%2F` or
  empty segments. Make the generator reach the edges your examples miss.
- **Unreproducible failures.** fast-check prints the seed and path on failure; keep that
  output in the failure report and replay with `{ seed, path }` while fixing. When a
  failure is found, also add the shrunk counterexample as a named example test.
- **Properties at the wrong layer.** Hundreds of runs against real Strapi for a pure
  function: that's a unit property. Integration properties are only for state that
  genuinely depends on Strapi.
