# Strapi v5 Real-World Examples

## Complete Plugin: Bookmarks System

A full example of a user bookmarks plugin with admin panel.

### Plugin Structure

```
bookmark-plugin/
├── package.json              # entries via exports (no root strapi-server.js / strapi-admin.js)
├── server/src/
│   ├── index.ts
│   ├── content-types/
│   │   └── bookmark/
│   │       └── schema.json
│   ├── controllers/
│   │   └── bookmark.ts
│   ├── routes/
│   │   └── index.ts
│   └── services/
│       └── bookmark.ts
└── admin/src/
    ├── index.ts
    └── pages/
        └── HomePage.tsx
```

### package.json

```json
{
  "name": "bookmark-plugin",
  "version": "1.0.0",
  "strapi": {
    "kind": "plugin",
    "name": "bookmark-plugin",
    "displayName": "Bookmarks"
  },
  "type": "commonjs",
  "files": ["dist"],
  "exports": {
    "./package.json": "./package.json",
    "./strapi-admin": {
      "types": "./dist/admin/src/index.d.ts",
      "source": "./admin/src/index.ts",
      "import": "./dist/admin/index.mjs",
      "require": "./dist/admin/index.js",
      "default": "./dist/admin/index.js"
    },
    "./strapi-server": {
      "types": "./dist/server/src/index.d.ts",
      "source": "./server/src/index.ts",
      "import": "./dist/server/index.mjs",
      "require": "./dist/server/index.js",
      "default": "./dist/server/index.js"
    }
  },
  "scripts": {
    "build": "strapi-plugin build",
    "watch": "strapi-plugin watch",
    "watch:link": "strapi-plugin watch:link",
    "verify": "strapi-plugin verify"
  },
  "devDependencies": {
    "@strapi/sdk-plugin": "^6.0.0",
    "@strapi/strapi": "^5.0.0"
  },
  "peerDependencies": {
    "@strapi/design-system": "^2.0.0",
    "@strapi/icons": "^2.0.0",
    "@strapi/sdk-plugin": "^6.0.0",
    "@strapi/strapi": "^5.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0",
    "react-intl": "^6.0.0",
    "react-router-dom": "^6.0.0",
    "styled-components": "^6.0.0"
  }
}
```

### Content-Type Schema

```json
// server/src/content-types/bookmark/schema.json
{
  "kind": "collectionType",
  "collectionName": "bookmarks",
  "info": {
    "singularName": "bookmark",
    "pluralName": "bookmarks",
    "displayName": "Bookmark"
  },
  "options": {
    "draftAndPublish": false
  },
  "attributes": {
    "user": {
      "type": "relation",
      "relation": "manyToOne",
      "target": "plugin::users-permissions.user",
      "required": true
    },
    "contentType": {
      "type": "string",
      "required": true
    },
    "contentId": {
      "type": "string",
      "required": true
    },
    "note": {
      "type": "text"
    }
  }
}
```

### Service

```typescript
// server/src/services/bookmark.ts
import type { Core } from '@strapi/strapi';

const BOOKMARK_UID = 'plugin::bookmark-plugin.bookmark';

const bookmarkService = ({ strapi }: { strapi: Core.Strapi }) => ({
  async getUserBookmarks(userDocumentId: string, contentType?: string) {
    const filters: any = { user: { documentId: userDocumentId } };
    if (contentType) {
      filters.contentType = contentType;
    }

    return strapi.documents(BOOKMARK_UID).findMany({
      filters,
      sort: { createdAt: 'desc' },
    });
  },

  async addBookmark(userDocumentId: string, contentType: string, contentId: string, note?: string) {
    // Check if already bookmarked
    const existing = await strapi.documents(BOOKMARK_UID).findFirst({
      filters: {
        user: { documentId: userDocumentId },
        contentType,
        contentId,
      },
    });

    if (existing) {
      return existing;
    }

    return strapi.documents(BOOKMARK_UID).create({
      data: {
        // v5 relations are set by documentId
        user: { connect: [{ documentId: userDocumentId }] },
        contentType,
        contentId,
        note,
      },
    });
  },

  async removeBookmark(userDocumentId: string, contentType: string, contentId: string) {
    const bookmark = await strapi.documents(BOOKMARK_UID).findFirst({
      filters: {
        user: { documentId: userDocumentId },
        contentType,
        contentId,
      },
    });

    if (!bookmark) {
      return null;
    }

    await strapi.documents(BOOKMARK_UID).delete({
      documentId: bookmark.documentId,
    });

    return bookmark;
  },

  async isBookmarked(userDocumentId: string, contentType: string, contentId: string) {
    const count = await strapi.documents(BOOKMARK_UID).count({
      filters: {
        user: { documentId: userDocumentId },
        contentType,
        contentId,
      },
    });

    return count > 0;
  },
});

export default bookmarkService;
```

### Controller

```typescript
// server/src/controllers/bookmark.ts
import type { Core } from '@strapi/strapi';
import { errors } from '@strapi/utils';

const { UnauthorizedError, ValidationError } = errors;

const bookmarkController = ({ strapi }: { strapi: Core.Strapi }) => ({
  async list(ctx) {
    const user = ctx.state.user;
    if (!user) {
      throw new UnauthorizedError('You must be logged in');
    }

    const { contentType } = ctx.query;
    const bookmarks = await strapi
      .service('plugin::bookmark-plugin.bookmark')
      .getUserBookmarks(user.documentId, contentType);

    return { data: bookmarks };
  },

  async add(ctx) {
    const user = ctx.state.user;
    if (!user) {
      throw new UnauthorizedError('You must be logged in');
    }

    const { contentType, contentId, note } = ctx.request.body;

    if (!contentType || !contentId) {
      throw new ValidationError('contentType and contentId are required');
    }

    const bookmark = await strapi
      .service('plugin::bookmark-plugin.bookmark')
      .addBookmark(user.documentId, contentType, contentId, note);

    return { data: bookmark };
  },

  async remove(ctx) {
    const user = ctx.state.user;
    if (!user) {
      throw new UnauthorizedError('You must be logged in');
    }

    const { contentType, contentId } = ctx.request.body;

    if (!contentType || !contentId) {
      throw new ValidationError('contentType and contentId are required');
    }

    const bookmark = await strapi
      .service('plugin::bookmark-plugin.bookmark')
      .removeBookmark(user.documentId, contentType, contentId);

    return { data: bookmark };
  },

  async check(ctx) {
    const user = ctx.state.user;
    if (!user) {
      throw new UnauthorizedError('You must be logged in');
    }

    const { contentType, contentId } = ctx.query;

    if (!contentType || !contentId) {
      throw new ValidationError('contentType and contentId are required');
    }

    const isBookmarked = await strapi
      .service('plugin::bookmark-plugin.bookmark')
      .isBookmarked(user.documentId, contentType, contentId);

    return { data: { isBookmarked } };
  },
});

export default bookmarkController;
```

### Routes

```typescript
// server/src/routes/index.ts
export default {
  'content-api': {
    type: 'content-api',
    routes: [
      {
        method: 'GET',
        path: '/bookmarks',
        handler: 'bookmark.list',
        config: {
          policies: [],
        },
      },
      {
        method: 'POST',
        path: '/bookmarks',
        handler: 'bookmark.add',
        config: {
          policies: [],
        },
      },
      {
        method: 'DELETE',
        path: '/bookmarks',
        handler: 'bookmark.remove',
        config: {
          policies: [],
        },
      },
      {
        method: 'GET',
        path: '/bookmarks/check',
        handler: 'bookmark.check',
        config: {
          policies: [],
        },
      },
    ],
  },
};
```

---

## API Integration Plugin Example

A plugin that syncs content with an external API.

### Service with External API

```typescript
// server/src/services/sync.ts
import type { Core } from '@strapi/strapi';

interface ExternalProduct {
  id: string;
  name: string;
  price: number;
  description: string;
}

const syncService = ({ strapi }: { strapi: Core.Strapi }) => ({
  async fetchExternalProducts(): Promise<ExternalProduct[]> {
    const settings = await this.getSettings();

    const response = await fetch(`${settings.apiUrl}/products`, {
      headers: {
        Authorization: `Bearer ${settings.apiKey}`,
      },
    });

    if (!response.ok) {
      throw new Error(`API request failed: ${response.status}`);
    }

    return response.json();
  },

  async syncProducts() {
    const externalProducts = await this.fetchExternalProducts();
    const results = { created: 0, updated: 0, errors: 0 };

    for (const extProduct of externalProducts) {
      try {
        const existing = await strapi
          .documents('plugin::sync-plugin.product')
          .findFirst({
            filters: { externalId: extProduct.id },
          });

        if (existing) {
          await strapi.documents('plugin::sync-plugin.product').update({
            documentId: existing.documentId,
            data: {
              name: extProduct.name,
              price: extProduct.price,
              description: extProduct.description,
              lastSyncedAt: new Date(),
            },
          });
          results.updated++;
        } else {
          await strapi.documents('plugin::sync-plugin.product').create({
            data: {
              externalId: extProduct.id,
              name: extProduct.name,
              price: extProduct.price,
              description: extProduct.description,
              lastSyncedAt: new Date(),
            },
          });
          results.created++;
        }
      } catch (error) {
        strapi.log.error(`Failed to sync product ${extProduct.id}:`, error);
        results.errors++;
      }
    }

    // Log sync results
    await strapi.documents('plugin::sync-plugin.sync-log').create({
      data: {
        type: 'products',
        ...results,
        completedAt: new Date(),
      },
    });

    return results;
  },

  async getSettings() {
    const settings = await strapi
      .documents('plugin::sync-plugin.settings')
      .findFirst();

    if (!settings?.apiUrl || !settings?.apiKey) {
      throw new Error('Sync plugin not configured. Please set API URL and key.');
    }

    return settings;
  },
});

export default syncService;
```

### Admin Settings Page

```ts
// admin/src/features/settings/services/settings.service.ts
import { getFetchClient } from '@strapi/strapi/admin';

export interface SyncSettings { apiUrl: string; apiKey: string }

export const settingsService = {
  get: async (): Promise<SyncSettings> => {
    const { get } = getFetchClient();
    const res = await get<SyncSettings>('/sync-plugin/settings');
    return res.data;
  },
  update: async (settings: SyncSettings): Promise<SyncSettings> => {
    const { put } = getFetchClient();
    const res = await put<SyncSettings>('/sync-plugin/settings', settings);
    return res.data;
  },
};

// admin/src/features/settings/hooks/use-settings.ts
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { queryKeys } from '../../../lib/query-keys'; // settings: { all: ['settings'] }
import { settingsService, type SyncSettings } from '../services/settings.service';

export const useSettings = () =>
  useQuery({ queryKey: queryKeys.settings.all, queryFn: settingsService.get });

export function useUpdateSettings(
  callbacks: { onSuccess?: (s: SyncSettings) => void; onError?: (e: Error) => void } = {}
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: settingsService.update,
    onSuccess: async (settings) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.settings.all });
      callbacks.onSuccess?.(settings);
    },
    onError: callbacks.onError,
  });
}
```

```tsx
// admin/src/pages/Settings.tsx
import { useState, useEffect } from 'react';
import { QueryClientProvider } from '@tanstack/react-query';
import {
  Main,
  Box,
  Typography,
  Field,
  TextInput,
  Button,
  Flex,
  Alert,
} from '@strapi/design-system';
import { useNotification } from '@strapi/strapi/admin';
import { queryClient } from '../lib/query-client';
import { useSettings, useUpdateSettings } from '../features/settings/hooks/use-settings';

const SettingsForm = () => {
  const [settings, setSettings] = useState({ apiUrl: '', apiKey: '' });
  const { toggleNotification } = useNotification();
  const { data, isLoading } = useSettings();

  // Seed the local form state once the settings arrive
  useEffect(() => {
    if (data) setSettings(data);
  }, [data]);

  const save = useUpdateSettings({
    onSuccess: () =>
      toggleNotification({ type: 'success', message: 'Settings saved successfully' }),
    onError: () =>
      toggleNotification({ type: 'danger', message: 'Failed to save settings' }),
  });

  if (isLoading) {
    return <Main><Box padding={8}>Loading...</Box></Main>;
  }

  return (
    <Main>
      <Box padding={8}>
        <Typography variant="alpha" marginBottom={6}>
          Sync Plugin Settings
        </Typography>

        <Box background="neutral0" padding={6} shadow="filterShadow" hasRadius>
          <Flex direction="column" gap={4}>
            <Field.Root name="apiUrl">
              <Field.Label>API URL</Field.Label>
              <TextInput
                value={settings.apiUrl}
                onChange={(e) => setSettings({ ...settings, apiUrl: e.target.value })}
                placeholder="https://api.example.com"
              />
            </Field.Root>

            <Field.Root name="apiKey">
              <Field.Label>API Key</Field.Label>
              <TextInput
                type="password"
                value={settings.apiKey}
                onChange={(e) => setSettings({ ...settings, apiKey: e.target.value })}
                placeholder="Your API key"
              />
            </Field.Root>

            <Button onClick={() => save.mutate(settings)} loading={save.isPending}>
              Save Settings
            </Button>
          </Flex>
        </Box>
      </Box>
    </Main>
  );
};

// Strapi doesn't provide a TanStack client — wrap the page in the plugin's shared one
const Settings = () => (
  <QueryClientProvider client={queryClient}>
    <SettingsForm />
  </QueryClientProvider>
);

export default Settings;
```

---

## GraphQL Custom Resolver

```typescript
// server/src/graphql/index.ts
export default {
  register({ strapi }) {
    const extensionService = strapi.plugin('graphql').service('extension');

    extensionService.use(({ nexus }) => ({
      types: [
        nexus.extendType({
          type: 'Query',
          definition(t) {
            t.field('articlesByAuthor', {
              type: nexus.nonNull(nexus.list('Article')),
              args: {
                authorId: nexus.nonNull(nexus.stringArg()),
                limit: nexus.intArg({ default: 10 }),
              },
              async resolve(parent, args, ctx) {
                const { authorId, limit } = args;

                const articles = await strapi
                  .documents('api::article.article')
                  .findMany({
                    filters: { author: { id: authorId } },
                    limit,
                    status: 'published',
                    populate: ['author', 'cover'],
                  });

                return articles;
              },
            });
          },
        }),

        nexus.extendType({
          type: 'Mutation',
          definition(t) {
            t.field('toggleBookmark', {
              type: 'Boolean',
              args: {
                contentType: nexus.nonNull(nexus.stringArg()),
                contentId: nexus.nonNull(nexus.stringArg()),
              },
              async resolve(parent, args, ctx) {
                const { contentType, contentId } = args;
                const user = ctx.state.user;

                if (!user) {
                  throw new Error('Authentication required');
                }

                const isBookmarked = await strapi
                  .service('plugin::bookmark-plugin.bookmark')
                  .isBookmarked(user.documentId, contentType, contentId);

                if (isBookmarked) {
                  await strapi
                    .service('plugin::bookmark-plugin.bookmark')
                    .removeBookmark(user.documentId, contentType, contentId);
                  return false;
                } else {
                  await strapi
                    .service('plugin::bookmark-plugin.bookmark')
                    .addBookmark(user.documentId, contentType, contentId);
                  return true;
                }
              },
            });
          },
        }),
      ],
    }));
  },
};
```

---

## Custom Middleware: Request Validation

```typescript
// server/src/middlewares/validate-api-key.ts
import type { Core } from '@strapi/strapi';

export default (config: { header?: string }, { strapi }: { strapi: Core.Strapi }) => {
  const headerName = config.header || 'X-API-Key';

  return async (ctx, next) => {
    const apiKey = ctx.request.headers[headerName.toLowerCase()];

    if (!apiKey) {
      return ctx.unauthorized(`Missing ${headerName} header`);
    }

    // Validate against stored API keys
    const validKey = await strapi
      .documents('plugin::my-plugin.api-key')
      .findFirst({
        filters: {
          key: apiKey,
          active: true,
          $or: [
            { expiresAt: { $null: true } },
            { expiresAt: { $gt: new Date() } },
          ],
        },
      });

    if (!validKey) {
      return ctx.unauthorized('Invalid or expired API key');
    }

    // Attach key info to context for later use
    ctx.state.apiKey = validKey;

    // Update last used timestamp
    await strapi.documents('plugin::my-plugin.api-key').update({
      documentId: validKey.documentId,
      data: { lastUsedAt: new Date() },
    });

    await next();
  };
};
```

---

## Frontend Integration Example (Next.js)

```typescript
// lib/strapi.ts
const STRAPI_URL = process.env.NEXT_PUBLIC_STRAPI_URL || 'http://localhost:1337';

interface StrapiResponse<T> {
  data: T;
  meta?: {
    pagination?: {
      page: number;
      pageSize: number;
      pageCount: number;
      total: number;
    };
  };
}

export async function fetchFromStrapi<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<StrapiResponse<T>> {
  const url = `${STRAPI_URL}/api${endpoint}`;

  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`Strapi request failed: ${response.status}`);
  }

  return response.json();
}

// Usage examples
export async function getArticles(page = 1, pageSize = 10) {
  return fetchFromStrapi<Article[]>(
    `/articles?pagination[page]=${page}&pagination[pageSize]=${pageSize}&populate=*`
  );
}

export async function getArticleBySlug(slug: string) {
  const response = await fetchFromStrapi<Article[]>(
    `/articles?filters[slug][$eq]=${slug}&populate=*`
  );
  return response.data[0] || null;
}

export async function toggleBookmark(
  token: string,
  contentType: string,
  contentId: string
) {
  const checkResponse = await fetchFromStrapi<{ isBookmarked: boolean }>(
    `/bookmark-plugin/bookmarks/check?contentType=${contentType}&contentId=${contentId}`,
    {
      headers: { Authorization: `Bearer ${token}` },
    }
  );

  if (checkResponse.data.isBookmarked) {
    return fetchFromStrapi(
      '/bookmark-plugin/bookmarks',
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
        body: JSON.stringify({ contentType, contentId }),
      }
    );
  } else {
    return fetchFromStrapi(
      '/bookmark-plugin/bookmarks',
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: JSON.stringify({ contentType, contentId }),
      }
    );
  }
}
```

---

## Complete Plugin Example: @strapi-community/plugin-todo

Based on [strapi-community/plugin-todo](https://github.com/strapi-community/plugin-todo) - a production Strapi v5 plugin.

### Plugin Purpose

Adds a todo list panel next to content in Strapi's Content Manager, allowing administrators to track tasks while editing content entries.

### Complete File Structure

```
plugin-todo/
├── package.json
├── admin/
│   └── src/
│       ├── index.ts              # Plugin registration
│       ├── pluginId.ts           # Plugin ID constant
│       ├── components/
│       │   ├── Initializer.tsx   # Plugin initialization
│       │   ├── TodoPanel.tsx     # Main panel component
│       │   ├── TodoList.tsx      # Task list with checkboxes
│       │   └── TodoModal.tsx     # Create task modal
│       ├── utils/
│       └── translations/
│           └── en.json
└── server/
    └── src/
        ├── index.ts              # Server exports
        ├── content-types/
        │   ├── index.ts
        │   └── task/
        │       ├── index.ts
        │       └── schema.json
        ├── controllers/
        │   ├── index.ts
        │   └── task.ts
        ├── services/
        │   ├── index.ts
        │   └── task.ts
        └── routes/
            ├── index.ts
            ├── admin/
            │   ├── index.ts
            │   └── task.ts
            └── content-api/
                └── index.ts
```

### package.json

```json
{
  "name": "@strapi-community/plugin-todo",
  "version": "1.0.0",
  "description": "Keep track of your content management with todo lists",
  "strapi": {
    "kind": "plugin",
    "name": "todo",
    "displayName": "Todo"
  },
  "type": "commonjs",
  "exports": {
    "./package.json": "./package.json",
    "./strapi-admin": {
      "types": "./dist/admin/src/index.d.ts",
      "source": "./admin/src/index.ts",
      "import": "./dist/admin/index.mjs",
      "require": "./dist/admin/index.js",
      "default": "./dist/admin/index.js"
    },
    "./strapi-server": {
      "types": "./dist/server/src/index.d.ts",
      "source": "./server/src/index.ts",
      "import": "./dist/server/index.mjs",
      "require": "./dist/server/index.js",
      "default": "./dist/server/index.js"
    }
  },
  "dependencies": {
    "@tanstack/react-query": "^5.90.16"
  },
  "devDependencies": {
    "@strapi/sdk-plugin": "^6.0.0",
    "@strapi/strapi": "^5.0.0"
  },
  "peerDependencies": {
    "@strapi/design-system": "^2.0.0",
    "@strapi/icons": "^2.0.0",
    "@strapi/sdk-plugin": "^6.0.0",
    "@strapi/strapi": "^5.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0",
    "react-intl": "^6.0.0",
    "react-router-dom": "^6.0.0",
    "styled-components": "^6.0.0"
  }
}
```

### Content-Type Schema (Hidden from UI)

```json
// server/src/content-types/task/schema.json
{
  "kind": "collectionType",
  "collectionName": "tasks",
  "info": {
    "singularName": "task",
    "pluralName": "tasks",
    "displayName": "Task"
  },
  "options": {
    "draftAndPublish": false
  },
  "pluginOptions": {
    "content-manager": { "visible": false },
    "content-type-builder": { "visible": false }
  },
  "attributes": {
    "name": {
      "type": "text"
    },
    "done": {
      "type": "boolean"
    },
    "related": {
      "type": "relation",
      "relation": "morphToMany"
    }
  }
}
```

### Server Index

```typescript
// server/src/index.ts
import controllers from './controllers';
import routes from './routes';
import services from './services';
import contentTypes from './content-types';

export default {
  controllers,
  routes,
  services,
  contentTypes,
};
```

### Service with Custom Method

```typescript
// server/src/services/task.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreService('plugin::todo.task', ({ strapi }) => ({
  async findRelatedTasks(relatedId: string, relatedType: string) {
    // Query the polymorphic junction table via knex — `strapi.db.query()`
    // takes a model UID, not a table name
    const relatedTasks = await strapi.db
      .connection('tasks_related_mph')
      .select('task_id')
      .where({
        related_id: relatedId,
        related_type: relatedType,
      });

    const taskIds = relatedTasks.map((t) => t.task_id);

    // Fetch full task documents
    return strapi.documents('plugin::todo.task').findMany({
      filters: { id: { $in: taskIds } },
    });
  },
}));
```

### Controller with Custom Endpoint

```typescript
// server/src/controllers/task.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreController('plugin::todo.task', ({ strapi }) => ({
  async findRelatedTasks(ctx) {
    const { relatedId, relatedType } = ctx.params;

    const tasks = await strapi
      .service('plugin::todo.task')
      .findRelatedTasks(relatedId, relatedType);

    ctx.body = tasks;
  },
}));
```

### Routes with Core Router + Custom Endpoints

```typescript
// server/src/routes/index.ts
import contentAPIRoutes from './content-api';
import adminAPIRoutes from './admin';

const routes = {
  'content-api': contentAPIRoutes,
  admin: adminAPIRoutes,
};

export default routes;
```

```typescript
// server/src/routes/admin/task.ts
import { factories } from '@strapi/strapi';

export default factories.createCoreRouter('plugin::todo.task');
```

```typescript
// server/src/routes/admin/index.ts
import task from './task';

export default () => ({
  type: 'admin',
  routes: [
    // Spread core CRUD routes from factory
    // @ts-ignore
    ...task.routes,
    // Add custom endpoint
    {
      method: 'GET',
      path: '/tasks/related/:relatedType/:relatedId',
      handler: 'task.findRelatedTasks',
    },
  ],
});
```

### Admin Entry Point

```typescript
// admin/src/index.ts
import { PLUGIN_ID } from './pluginId';
import { Initializer } from './components/Initializer';
import { TodoPanel } from './components/TodoPanel';

export default {
  register(app: any) {
    app.registerPlugin({
      id: PLUGIN_ID,
      initializer: Initializer,
      isReady: false,
      name: PLUGIN_ID,
    });
  },

  bootstrap(app: any) {
    // Register a panel in the Content Manager edit view sidebar
    app.getPlugin('content-manager').apis.addEditViewSidePanel([TodoPanel]);
  },

  async registerTrads({ locales }: { locales: string[] }) {
    return Promise.all(
      locales.map(async (locale) => {
        try {
          const { default: data } = await import(`./translations/${locale}.json`);
          return { data, locale };
        } catch {
          return { data: {}, locale };
        }
      })
    );
  },
};
```

### Plugin ID Constant

```typescript
// admin/src/pluginId.ts
export const PLUGIN_ID = 'todo';
```

### Initializer Component

```tsx
// admin/src/components/Initializer.tsx
import { useEffect, useRef } from 'react';
import { PLUGIN_ID } from '../pluginId';

interface Props {
  setPlugin: (id: string) => void;
}

export const Initializer = ({ setPlugin }: Props) => {
  const ref = useRef(setPlugin);

  useEffect(() => {
    ref.current(PLUGIN_ID);
  }, []);

  return null;
};
```

### Data Layer: Keys, Service, Hooks

The admin follows [fullstack-standards.md](fullstack-standards.md): components call feature
hooks, hooks call the service, only the service calls `getFetchClient()`.

```ts
// admin/src/lib/query-client.ts
import { QueryClient, type QueryClientConfig } from '@tanstack/react-query';

// Production defaults, exported so component tests can reproduce cache bugs.
export const queryClientConfig: QueryClientConfig = {
  defaultOptions: {
    queries: { staleTime: 5 * 60 * 1000, refetchOnWindowFocus: false, retry: 2 },
    mutations: { retry: 0 },
  },
};

// Shared by every provider the plugin renders: pages and CM-injected components.
export const queryClient = new QueryClient(queryClientConfig);

// admin/src/lib/query-keys.ts
export const queryKeys = {
  tasks: {
    all: ['task'] as const,
    related: (model: string, documentId: string) =>
      [...queryKeys.tasks.all, 'related', model, documentId] as const,
  },
} as const;
```

```ts
// admin/src/features/todo/services/tasks.service.ts
import { getFetchClient } from '@strapi/strapi/admin';

export interface Task { documentId: string; name: string; done: boolean }
export interface CreateTaskInput { name: string; model: string; documentId: string }

export const tasksService = {
  listRelated: async (model: string, documentId: string): Promise<Task[]> => {
    const { get } = getFetchClient();
    // The custom controller answers `ctx.body = tasks` (no { data } envelope)
    const res = await get<Task[]>(`/todo/tasks/related/${model}/${documentId}`);
    return res.data;
  },
  create: async ({ name, model, documentId }: CreateTaskInput): Promise<Task> => {
    const { post } = getFetchClient();
    const res = await post<{ data: Task }>('/todo/tasks', {
      data: { name, related: [{ __type: model, documentId }] },
    });
    return res.data.data;
  },
  setDone: async (documentId: string, done: boolean): Promise<Task> => {
    const { put } = getFetchClient();
    const res = await put<{ data: Task }>(`/todo/tasks/${documentId}`, { data: { done } });
    return res.data.data;
  },
};
```

```ts
// admin/src/features/todo/hooks/use-tasks.ts
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { queryKeys } from '../../../lib/query-keys';
import { tasksService, type CreateTaskInput, type Task } from '../services/tasks.service';

interface Callbacks<T> { onSuccess?: (result: T) => void; onError?: (error: Error) => void }

export function useRelatedTasks(model: string, documentId: string) {
  return useQuery({
    queryKey: queryKeys.tasks.related(model, documentId),
    queryFn: () => tasksService.listRelated(model, documentId),
  });
}

export function useCreateTask(callbacks: Callbacks<Task> = {}) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateTaskInput) => tasksService.create(input),
    onSuccess: async (task) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.tasks.all });
      callbacks.onSuccess?.(task);
    },
    onError: callbacks.onError,
  });
}

export function useSetTaskDone(callbacks: Callbacks<Task> = {}) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ documentId, done }: { documentId: string; done: boolean }) =>
      tasksService.setDone(documentId, done),
    onSuccess: async (task) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.tasks.all });
      callbacks.onSuccess?.(task);
    },
    onError: callbacks.onError,
  });
}
```

### Main Panel Component

```tsx
// admin/src/components/TodoPanel.tsx
import { useState } from 'react';
import { QueryClientProvider } from '@tanstack/react-query';
import type { PanelComponent } from '@strapi/content-manager/strapi-admin';
import { TextButton } from '@strapi/design-system';
import { Plus } from '@strapi/icons';
import { queryClient } from '../lib/query-client';
import { TaskList } from '../features/todo/components/TaskList';
import { TodoModal } from '../features/todo/components/TodoModal';

// Panels receive the edit-view context ({ documentId, model, document, ... })
// as props and return { title, content } (or null to hide)
export const TodoPanel: PanelComponent = ({ model, documentId }) => {
  const [modalOpen, setModalOpen] = useState(false);

  return {
    title: 'Todo List',
    content: (
      // Strapi doesn't provide a TanStack client — use the plugin's shared one
      <QueryClientProvider client={queryClient}>
        <TextButton
          startIcon={<Plus />}
          onClick={() => setModalOpen(true)}
          disabled={!documentId}
        >
          Add todo
        </TextButton>

        {documentId && (
          <>
            <TodoModal open={modalOpen} setOpen={setModalOpen} model={model} documentId={documentId} />
            <TaskList model={model} documentId={documentId} />
          </>
        )}
      </QueryClientProvider>
    ),
  };
};
```

### Task List

```tsx
// admin/src/features/todo/components/TaskList.tsx
import { Checkbox, Loader } from '@strapi/design-system';
import { useRelatedTasks, useSetTaskDone } from '../hooks/use-tasks';

export const TaskList = ({ model, documentId }: { model: string; documentId: string }) => {
  const { data: tasks, isLoading } = useRelatedTasks(model, documentId);
  const setDone = useSetTaskDone();

  if (isLoading) return <Loader small>Loading tasks</Loader>;

  return (
    <ul>
      {tasks?.map((task) => (
        <li key={task.documentId}>
          <Checkbox
            checked={task.done}
            onCheckedChange={(checked) =>
              setDone.mutate({ documentId: task.documentId, done: checked === true })
            }
          >
            {task.name}
          </Checkbox>
        </li>
      ))}
    </ul>
  );
};
```

### Create Task Modal

```tsx
// admin/src/features/todo/components/TodoModal.tsx
import { useState } from 'react';
import { Dialog, Field, TextInput, Button } from '@strapi/design-system';
import { useCreateTask } from '../hooks/use-tasks';

interface Props {
  open: boolean;
  setOpen: (open: boolean) => void;
  model: string;
  documentId: string;
}

export const TodoModal = ({ open, setOpen, model, documentId }: Props) => {
  const [taskName, setTaskName] = useState('');

  const createTask = useCreateTask({
    onSuccess: () => {
      setTaskName('');
      setOpen(false);
    },
  });

  return (
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Content>
        <Dialog.Header>Add task</Dialog.Header>
        <Dialog.Body>
          <Field.Root name="task">
            <Field.Label>Task</Field.Label>
            <TextInput
              value={taskName}
              onChange={(e: React.ChangeEvent<HTMLInputElement>) => setTaskName(e.target.value)}
            />
          </Field.Root>
        </Dialog.Body>
        <Dialog.Footer>
          <Dialog.Cancel>
            <Button variant="tertiary">Cancel</Button>
          </Dialog.Cancel>
          <Dialog.Action>
            <Button
              onClick={() => createTask.mutate({ name: taskName, model, documentId })}
              disabled={!taskName || createTask.isPending}
            >
              Confirm
            </Button>
          </Dialog.Action>
        </Dialog.Footer>
      </Dialog.Content>
    </Dialog.Root>
  );
};
```

### Key Patterns Demonstrated

| Pattern | Implementation |
|---------|----------------|
| **Factory Pattern** | `factories.createCoreService()`, `createCoreController()`, `createCoreRouter()` |
| **Hidden Content Type** | `pluginOptions.content-manager.visible: false` |
| **Polymorphic Relations** | `morphToMany` for relating tasks to any content type |
| **Content Manager Integration** | `apis.addEditViewSidePanel([TodoPanel])` returning `{ title, content }` |
| **Layered data access** | Components → feature hooks (`use-tasks.ts`) → service (`tasks.service.ts`); keys from `lib/query-keys.ts`, mutations invalidate `queryKeys.tasks.all` |
| **TanStack Query v5** | Panel wrapped in a `QueryClientProvider` with the shared `queryClient` from `lib/query-client.ts` |
| **Strapi fetch client** | `getFetchClient()` inside service functions only; panel props supply `model` and `documentId` |
| **Route Composition** | Spreading core router routes + custom endpoints |
