# Admin data layer: fullstack-standards in a Strapi plugin

A plugin's admin panel is a React SPA on TanStack Query v5 talking to a REST backend, so it
follows the **fullstack-standards** rules
([ayhid/fullstack-standards](https://github.com/ayhid/fullstack-standards)):

- `fullstack-standards:data-layer` — component → feature hook → frontend service → the
  single entry point; the key factory; mutations and invalidation. Read its
  `references/adapters/tanstack-query.md` too.
- `fullstack-standards:fullstack-testing` — every component rendered with its service
  mocked, no hook tests, every service tested against the entry point, third-party
  services behind a port.

Load those skills before writing admin data code. This page only maps them onto a Strapi
plugin; where they speak of `apiClient.request`, read **`getFetchClient()`**.

## The mapping

| fullstack-standards | In a Strapi v5 plugin |
|---|---|
| The single entry point (`apiClient.request`) | **`getFetchClient()`** from `@strapi/strapi/admin`. It already owns the base URL, the admin token and refresh, serialisation and the error shape (`FetchError`), so there is no wrapper file. Called **only in services** |
| Frontend service | `admin/src/features/<feature>/services/<resource>.service.ts`, one exported object of plain async functions |
| Feature hook | `admin/src/features/<feature>/hooks/use-<resource>.ts` |
| Key factory | `admin/src/lib/query-keys.ts` |
| The one cache | `admin/src/lib/query-client.ts`: the production defaults **and one shared `queryClient` instance** |
| Components | `admin/src/components/**`, `admin/src/pages/**`, `admin/src/features/*/components/**` — import hooks only |

Strapi specifics:

- **`getFetchClient`, not `useFetchClient`.** The hook form can only run inside a
  component or hook, so it would drag React into the service. Call `getFetchClient()`
  inside each service function (it reads the current token at call time).
- **Services unwrap and map.** The fetch client resolves `{ data, status }`; a plugin
  route that answers `ctx.body = { data, meta }` gives `res.data.data`. The service
  returns domain types, so `res.data`, `{ data: input }` request bodies,
  `meta.pagination` and `documentId` never reach hooks or components.
- **Errors propagate unchanged.** `FetchError` carries `status` and the server's
  `response.data.error`. The hook turns it into a user-facing message (with
  `useAPIErrorHandler().formatAPIError` if you like); the service never catches it.
- **One `queryClient` for the whole plugin.** Strapi does not provide a TanStack client
  (its admin uses react-query v3), so every tree you render — each page *and* each
  component injected into the Content Manager — needs a `QueryClientProvider`. Give
  them all the **same** instance from `lib/query-client.ts`; a `new QueryClient()` per
  tree splits the cache, and a mutation in a side panel then cannot invalidate the list
  on a plugin page.
- **Content Manager context is read in the component.** `unstable_useContentManagerContext()`
  (or the panel's props) gives `model` and `documentId`; pass them to the hook as
  parameters, and they become part of the key.
- **Paths are the plugin's admin routes**: `/<plugin-id>/...` for `type: 'admin'` routes.

## Example: the Todo side panel

```ts
// admin/src/lib/query-client.ts
import { QueryClient, type QueryClientConfig } from '@tanstack/react-query';

export const queryClientConfig: QueryClientConfig = {
  defaultOptions: {
    queries: { staleTime: 5 * 60 * 1000, refetchOnWindowFocus: false, retry: 2 },
    mutations: { retry: 0 },
  },
};

// Shared by every provider the plugin renders: pages and CM-injected components.
export const queryClient = new QueryClient(queryClientConfig);
```

```ts
// admin/src/lib/query-keys.ts
export const queryKeys = {
  tasks: {
    all: ['task'] as const,
    // Without `documentId`: the prefix for invalidating every document's tasks.
    related: (model: string, documentId?: string) =>
      documentId
        ? ([...queryKeys.tasks.all, 'related', model, documentId] as const)
        : ([...queryKeys.tasks.all, 'related', model] as const),
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
    // A custom controller answering `ctx.body = tasks`: no `{ data }` envelope.
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

export type { CreateTaskInput, Task };

interface Callbacks<T> { onSuccess?: (result: T) => void; onError?: (error: Error) => void }

export function useRelatedTasks(model: string, documentId: string | undefined) {
  return useQuery({
    queryKey: queryKeys.tasks.related(model, documentId),
    queryFn: () => tasksService.listRelated(model, documentId!),
    enabled: Boolean(documentId),
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

```tsx
// admin/src/components/TodoPanel.tsx — registered with addEditViewSidePanel
import { QueryClientProvider } from '@tanstack/react-query';
import type { PanelComponent } from '@strapi/content-manager/strapi-admin';
import { queryClient } from '../lib/query-client';
import { TaskList } from '../features/todo/components/TaskList';

export const TodoPanel: PanelComponent = ({ model, documentId }) => ({
  title: 'Todo list',
  content: documentId ? (
    <QueryClientProvider client={queryClient}>
      <TaskList model={model} documentId={documentId} />
    </QueryClientProvider>
  ) : null,
});
```

## Testing it

Per `fullstack-standards:fullstack-testing` (`references/frontend-vitest.md`), with the
plugin's runner (Jest or Vitest; `vi.*` below):

- **Component test** for `TaskList`: render it inside a fresh `QueryClientProvider`
  (fullstack's `test-utils/tanstack-query.tsx`, importing `queryClientConfig` from
  `lib/query-client.ts`) and the Design System's `DesignSystemProvider` — or Strapi's
  `render` from `@strapi/strapi/admin/test` when the component needs admin providers
  such as `useNotification`. `vi.mock` the **service module**; for each branch assert
  what the user sees and which `tasksService` function ran, with which arguments, how
  often. No `renderHook`, no test file under `hooks/`.
- **Service test** for `tasks.service.ts`: mock `getFetchClient` and assert the exact
  path, body and options each function sends, and the mapped result.

```ts
// admin/src/features/todo/services/tasks.service.test.ts
import { getFetchClient } from '@strapi/strapi/admin';
import { tasksService } from './tasks.service';

vi.mock('@strapi/strapi/admin', () => ({ getFetchClient: vi.fn() }));
const fetchClient = { get: vi.fn(), post: vi.fn(), put: vi.fn(), del: vi.fn() };
vi.mocked(getFetchClient).mockReturnValue(fetchClient as never);

it('creates a task related to the document', async () => {
  const task = { documentId: 't1', name: 'Proofread', done: false };
  fetchClient.post.mockResolvedValue({ data: { data: task } });

  const created = await tasksService.create({ name: 'Proofread', model: 'api::article.article', documentId: 'a1' });

  expect(fetchClient.post).toHaveBeenCalledTimes(1);
  expect(fetchClient.post).toHaveBeenCalledWith('/todo/tasks', {
    data: { name: 'Proofread', related: [{ __type: 'api::article.article', documentId: 'a1' }] },
  });
  expect(created).toEqual(task);
});
```

The admin routes these services call are proven on the server side, against the
fixture app — see the `strapi-plugin-testing` skill.

## Third-party services (server side)

A provider SDK (Brevo, Stripe, S3, an LLM API) lives behind a **port** the plugin owns
(`server/src/domain/mailer.port.ts`) and **one adapter** (`server/src/adapters/brevo-mailer.adapter.ts`),
the only file that imports the SDK. Inject the adapter through the plugin's services
(`({ strapi }) => …`) or config. Consumer specs fake the port; the adapter spec passes a
fake SDK client; no spec `jest.mock`s the SDK. Details:
`fullstack-standards:fullstack-testing`, `references/third-party-services.md`.

## What does not apply

- `lib/api/client.ts`, `apiClient.request` and the client's own tests — `getFetchClient`
  is the entry point.
- `bulk-delete.ts`, `list-params.ts`: use them when the plugin has those operations;
  route `bulkDelete` through the service's own `remove`.
- NestJS backend services, the ORM adapters and the Postgres integration harness — the
  plugin server follows `strapi-plugin-dev` and is tested against the fixture app
  (`strapi-plugin-testing`).
- Playwright rules apply only if the plugin has a browser E2E suite.

## Enforcement hooks

With the fullstack-standards plugin installed, `/strapi-skills:scaffold-plugin` writes
`.claude/fullstack-standards.json` for `admin/src` and `server/src`, which turns on its
hooks (component and service tests required, no `renderHook`, no `fetch`/`axios`, SDKs
only in adapters). Its checker recognises the entry point by file path, so it cannot see
`getFetchClient`; strapi-skills' own edit hook warns when a component or hook calls
`getFetchClient`/`useFetchClient` or a component calls `useQuery`/`useMutation`.
