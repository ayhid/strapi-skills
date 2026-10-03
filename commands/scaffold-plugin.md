---
description: Scaffold a new Strapi v5 plugin with opinionated structure (factory pattern, RHF+Zod, TanStack v5)
argument-hint: <plugin-name>
allowed-tools: Bash, Read, Edit, Write, Glob
model: claude-sonnet-4-5
---

Scaffold a new Strapi v5 plugin named `$1`. Follow the strapi-plugin-dev skill.

## Steps

1. **Run the official scaffolder** as the base:

   ```bash
   npx @strapi/sdk-plugin@latest init $1
   ```

2. **Verify the generated structure** matches the canonical layout (see strapi-plugin-dev SKILL.md). It should contain `server/src/index.ts`, `admin/src/index.ts`, and a `package.json` with `strapi.kind: "plugin"` whose `exports` map `./strapi-server` and `./strapi-admin` to `dist/` (no root `strapi-server.js`/`strapi-admin.js` files in current `@strapi/sdk-plugin`).

3. **Layer the opinionated defaults** on top:
   - Add dependencies to `package.json`: `@hookform/resolvers: ^5`, `@tanstack/react-query: ^5`, `react-hook-form: ^7`, `zod: ^4`. Keep `@strapi/design-system`/`@strapi/icons` at `^2.0.0` and `react-intl` as the template's `^6` peer (Strapi admin ships react-intl 6; a separate v7 copy won't share its `IntlProvider`).
   - Keep `react`/`react-dom` peers at `^18.0.0` (Strapi 5 admin runs React 18).
   - Create `admin/src/pluginId.ts` exporting the plugin id constant.
   - Create `admin/src/components/Initializer.tsx` (standard `setPlugin` pattern).
   - Split `server/src/routes/` into `admin/` and `content-api/` subdirectories.
   - Use `factories.createCoreService`, `factories.createCoreController`, `factories.createCoreRouter` for any generated CRUD scaffolding (see patterns.md).
   - Lay out the admin data layer per the skill's `fullstack-standards.md`: `admin/src/lib/query-client.ts` (production defaults + the one shared `queryClient`), `admin/src/lib/query-keys.ts` (empty factory), and an `admin/src/features/` folder for `services/` (the only callers of `getFetchClient()`), `hooks/` and `components/`.
   - Copy fullstack-standards' `skills/fullstack-testing/templates/frontend/test-utils/strapi-admin.tsx` to `admin/src/test/data-layer-test-utils.tsx` (component tests render through its `renderWithDataLayer`).
   - Write `.claude/fullstack-standards.json` at the repo root so the fullstack-standards hooks run. With that plugin installed, prefer `node <fullstack-standards>/skills/project-profile/scripts/detect-profile.mjs . --write-config`, which detects the plugin and never overwrites existing values; otherwise write:
     ```json
     {
       "frontends": [{ "root": "admin/src", "preset": "strapi-admin" }],
       "apis": [{ "root": ".", "preset": "strapi-plugin" }]
     }
     ```
     Prefix both roots with the plugin's path if it doesn't sit at the repo root (e.g. `packages/<name>`, `src/plugins/<name>`).
   - Add `"test:rules": "fullstack-standards --all ."` to `scripts` and `"fullstack-standards": "github:ayhid/fullstack-standards#v1.0.0-beta.2"` to `devDependencies` (pin the latest release tag), so CI runs the same checks. Keep `typescript` ^5 in `devDependencies`: the checker loads it from the plugin.
   - Offer to write the project profile into `AGENTS.md` with the `fullstack-standards:project-profile` skill.

4. **Run `npm install`** in the new plugin directory.

5. **Verify** with `npx @strapi/sdk-plugin@latest verify` and surface any errors.

## Output

Report:
- Path of the new plugin
- Files customized beyond the base scaffold
- Any verify errors
- Next-step commands (`npm run build`, `npm run watch:link`)
- Whether the fullstack-standards plugin is installed; if not, suggest `/plugin marketplace add ayhid/fullstack-standards` and `/plugin install fullstack-standards@fullstack-standards`

Defer to the **strapi-plugin-dev** skill for any architecture decisions during scaffolding. Do not invent file structures — use the canonical patterns from `patterns.md`.
