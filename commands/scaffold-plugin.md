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

4. **Run `npm install`** in the new plugin directory.

5. **Verify** with `npx @strapi/sdk-plugin@latest verify` and surface any errors.

## Output

Report:
- Path of the new plugin
- Files customized beyond the base scaffold
- Any verify errors
- Next-step commands (`npm run build`, `npm run watch:link`)

Defer to the **strapi-plugin-dev** skill for any architecture decisions during scaffolding. Do not invent file structures — use the canonical patterns from `patterns.md`.
