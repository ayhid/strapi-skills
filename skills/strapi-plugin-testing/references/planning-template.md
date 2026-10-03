# Planning template

Use when planning a feature or phase in a Strapi plugin. The point: before any code
exists, every behaviour has a declared layer and a named test that will prove it. A plan
where most behaviours land in integration or E2E is telling you the logic needs
extracting; fix the design in the plan, not later.

## Step 1 — List behaviours, then tag them

Write every behaviour as a checkable sentence ("A draft never resolves"), not a task
("Implement resolver"). If a spec already lists behaviour checks, start from those.
Tag each one with the three questions:

| # | Behaviour | Whose? | Needs Strapi? | Outside depends? | Layer | Proving test |
|---|---|---|---|---|---|---|
| B1 | `/About/` and `/about` resolve to the same entry | mine | no | no | Unit (property: idempotence) | `normalize-path.test.ts` |
| B2 | A draft never resolves | mine (use of D&P) | yes | no | Integration | `resolve.int.test.ts › drafts` |
| B3 | Resolve response is `{type:'content', documentId, locale}` | mine | no | yes (Next.js) | Contract | `resolve-response.contract` asserted in `resolve.int.test.ts` |
| B4 | `findMany` filters by `$eq` | Strapi | — | — | **None** | — |

## Step 2 — Check the distribution

Count behaviours per layer. Healthy plans are bottom-heavy: most at unit, a focused set
at integration, a few contracts, one or two E2E. If integration + E2E outnumber unit,
for each such row ask: *which part of this is a decision?* Split it into a unit row
(the decision) and a thinner integration row (Strapi delivers the inputs and stores the
outputs).

Also check:
- Every row tagged "Strapi's" has **no test**.
- No behaviour appears in two layers.
- Each port named in the plan has a contract suite row (fake + real).

## Step 3 — Tasks

Each task declares the behaviours it delivers and the test level that proves it done:

```markdown
### Task 3: Resolution decision
- Delivers: B1, B5, B6, B9
- Layer: Unit (domain/resolve.ts), in-memory RouteIndex
- Done when: resolve.test.ts and the totality property pass; RouteIndex contract suite
  passes against the fake
- Test approach: test-first

### Task 4: Index on publish/unpublish
- Delivers: B2, B7, B8
- Layer: Integration (fixture app), adapter + document middleware
- Done when: index.int.test.ts passes; RouteIndex contract suite passes against Strapi;
  hook-scope test proves unrelated types are ignored
- Test approach: double-loop — outer test written first
```

## Step 4 — Plan output

Return the plan as: the behaviour table, the per-layer counts (with a sentence on
anything extracted to rebalance them), the ordered tasks, and open questions, especially
assumptions about Strapi behaviour that the first integration test should settle.
