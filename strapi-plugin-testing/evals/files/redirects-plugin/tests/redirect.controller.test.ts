import controllerFactory from '../server/src/controllers/redirect';

describe('redirect.match', () => {
  it('returns the redirect', async () => {
    const findMany = jest.fn().mockResolvedValue([{ to: '/new', statusCode: 302 }]);
    const strapi: any = {
      plugin: () => ({ config: (k: string) => ({ caseSensitive: false, defaultStatusCode: 301 } as any)[k] }),
      documents: () => ({ findMany }),
    };
    const ctx: any = { query: { path: '/Old/' } };
    await controllerFactory({ strapi }).match(ctx);
    expect(findMany).toHaveBeenCalledWith({ filters: { from: '/old' }, locale: 'en', status: 'published' });
    expect(ctx.body).toEqual({ type: 'redirect', to: '/new', statusCode: 302 });
  });
});
