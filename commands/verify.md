---
description: Verify the current Strapi v5 plugin (official verify + anti-pattern grep)
allowed-tools: Bash, Read, Grep, Glob
model: claude-haiku-4-5
---

Verify the Strapi v5 plugin in the current directory. Follow the strapi-plugin-dev skill.

## Steps

1. **Run** `npx @strapi/sdk-plugin@latest verify` and capture output.

2. **Grep for anti-patterns** across `server/src/**/*.{ts,tsx}` and `admin/src/**/*.{ts,tsx}`:
   - `strapi.entityService` (should be `strapi.documents`)
   - `strapi.query` (deprecated; use `strapi.db.query(uid)` only as an escape hatch)
   - `from 'formik'` (should be `react-hook-form`)
   - `from 'yup'` (should be `zod`)
   - `from 'react-query'` (should be `@tanstack/react-query` v5)
   - Native `<button>`, `<input>`, `<select>` in `admin/src/**/*.tsx` (should be DS components)
   - `Select`/`Option` imported from `@strapi/design-system` (don't exist in DS v2 — use `SingleSelect`/`SingleSelectOption`)
   - `findMany(...)` destructured as `{ results, pagination }` (Document Service returns a plain array)
   - `alert(`, `window.confirm(` (should be `useNotification` / `Dialog`)
   - `useFetchClient` anywhere, or `getFetchClient` outside `admin/src/features/*/services/` (only services call the fetch client)
   - `useQuery(` / `useMutation(` outside `admin/src/features/*/hooks/`, and inline `queryKey: [` (keys come from `admin/src/lib/query-keys.ts`)
   - `new QueryClient(` outside `admin/src/lib/query-client.ts` (one shared client)
   - `renderHook(` in admin tests, or test files under `hooks/`
   - A provider SDK (`stripe`, `@getbrevo/brevo`, `nodemailer`, `@aws-sdk/`, `openai`, …) imported in `server/src` outside a `*.adapter.ts`

5. **If `.claude/fullstack-standards.json` exists** and the fullstack-standards plugin is installed, also run its audit and include the findings: `node <fullstack-standards plugin>/scripts/architecture/check-architecture.mjs --all .`

3. **Validate** every `server/src/content-types/*/schema.json` has `kind`, `info.singularName`, `info.pluralName`, `collectionName`.

4. **Check** `package.json`:
   - `strapi.kind: "plugin"` is set
   - `@strapi/design-system` is `^2.0.0` (not an `-rc` version)
   - `peerDependencies.react` does NOT include `^17`
   - `@tanstack/react-query` is v5
   - `@strapi/sdk-plugin` is `^6`
   - `engines.node` (if set) is within Strapi's supported range (`>=20 <=26`)

## Output

Structured report:
- ✅ Passes
- ⚠️  Warnings (anti-patterns, file references with line numbers)
- ❌ Errors (from `verify` or missing required fields)
- Suggested follow-up commands

Read-only — do NOT edit files.
