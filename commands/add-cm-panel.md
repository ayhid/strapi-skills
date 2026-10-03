---
description: Add a Content Manager edit-view side panel to the current Strapi v5 plugin
argument-hint: <panel-name>
allowed-tools: Read, Edit, Write, Glob, Grep
model: claude-sonnet-4-5
---

Add a Content Manager edit-view side panel named `$1` to the current Strapi v5 plugin. Follow the strapi-plugin-dev skill.

## Steps

1. **Verify** this is a Strapi plugin and that `admin/src/` exists.

2. **Create** `admin/src/components/$1.tsx` exporting a `PanelComponent` (type-only import from `@strapi/content-manager/strapi-admin`; add `@strapi/content-manager` to devDependencies). It receives the edit-view context as props (`documentId`, `document`, `model`, `collectionType`, `activeTab`, `meta`) and returns `{ title, content }`. The `content` must:
   - Wrap itself in its own `QueryClientProvider` if it uses `@tanstack/react-query` (Strapi admin provides no TanStack v5 client, and side panels render inside the Content Manager, outside the plugin's pages).
   - Use `useFetchClient()` for API calls.
   - Use only `@strapi/design-system` v2 compound components.
   - Use `react-hook-form` + `zod` for any forms.

3. **Register** the panel in `admin/src/index.ts`, in `bootstrap(app)` (the content-manager plugin is only available after register):
   ```ts
   app.getPlugin('content-manager').apis.addEditViewSidePanel([$1]);
   ```
   `getPlugin()` types `apis` as `Record<string, unknown>`, so this line needs a `// @ts-expect-error` (with a comment) or a cast.

4. **Verify** the panel disables interactions while `documentId` is undefined (the entry hasn't been saved yet).

5. **Report** every file modified.

For small buttons or links rather than a full panel, the `editView` / `right-links` injection zone
(`app.getPlugin('content-manager').injectComponent('editView', 'right-links', { name, Component })`) is still valid.

The companion **strapi-ui-design** skill governs the visual design — load it for any non-trivial layout work.
