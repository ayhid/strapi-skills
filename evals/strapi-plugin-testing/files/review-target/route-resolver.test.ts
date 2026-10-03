// Tests written by an agent for the router plugin's resolver service (Strapi v5).
import fc from 'fast-check';
import resolverFactory from '../server/src/services/resolver';
import { normalizePath } from '../server/src/domain/normalize-path';

const makeStrapi = (rows: any[]) => {
  const findMany = jest.fn().mockResolvedValue(rows);
  return {
    findMany,
    strapi: {
      plugin: () => ({ config: () => 'prefix-except-default' }),
      documents: jest.fn(() => ({ findMany })),
      log: { warn: jest.fn() },
    } as any,
  };
};

describe('resolver service', () => {
  it('resolves a published page', async () => {
    const { strapi, findMany } = makeStrapi([{ documentId: 'p1', path: '/about', locale: 'en' }]);
    const res = await resolverFactory({ strapi }).resolve('/about', 'en');
    expect(strapi.documents).toHaveBeenCalledWith('plugin::router.route');
    expect(findMany).toHaveBeenCalledTimes(1);
    expect(findMany).toHaveBeenCalledWith({
      filters: { path: { $eq: '/about' } },
      locale: 'en',
      status: 'published',
    });
    expect(res).toEqual({ type: 'content', documentId: 'p1', locale: 'en' });
  });

  it('does not resolve drafts', async () => {
    // drafts are filtered out by status: 'published'
    const { strapi } = makeStrapi([]);
    const res = await resolverFactory({ strapi }).resolve('/draft-page', 'en');
    expect(res).toEqual({ type: 'notFound' });
  });

  it('resolves the french locale', async () => {
    const { strapi } = makeStrapi([{ documentId: 'p1', path: '/a-propos', locale: 'fr' }]);
    const res = await resolverFactory({ strapi }).resolve('/fr/a-propos', 'fr');
    expect(res).toEqual({ type: 'content', documentId: 'p1', locale: 'fr' });
  });

  it('logs a warning on not found', async () => {
    const { strapi } = makeStrapi([]);
    await resolverFactory({ strapi }).resolve('/nope', 'en');
    expect(strapi.log.warn).toHaveBeenCalledWith('router: no route for /nope (en)');
  });
});

describe('normalizePath', () => {
  it('lowercases', () => expect(normalizePath('/About')).toBe('/about'));
  it('strips trailing slash', () => expect(normalizePath('/about/')).toBe('/about'));
  it('collapses slashes', () => expect(normalizePath('//about')).toBe('/about'));

  it('normalizes any path (property)', () => {
    fc.assert(
      fc.property(fc.string(), (p) => {
        const expected = ('/' + p).toLowerCase().replace(/\/+/g, '/').replace(/(.)\/$/, '$1');
        expect(normalizePath(p)).toBe(expected);
      }),
    );
  });
});

// e2e/resolve.e2e.test.ts (excerpt, same PR)
// it('lowercases paths', async () => {
//   await request(app).get('/api/router/resolve?path=/About').expect(200);
// });
// it('strips trailing slash', async () => {
//   await request(app).get('/api/router/resolve?path=/about/').expect(200);
// });
