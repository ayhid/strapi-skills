import type { Core } from '@strapi/strapi';

export default ({ strapi }: { strapi: Core.Strapi }) => ({
  async match(ctx) {
    let path: string = ctx.query.path || '/';
    const locale: string = ctx.query.locale || 'en';
    const cfg = strapi.plugin('redirects').config as any;
    if (!cfg('caseSensitive')) path = path.toLowerCase();
    if (path.length > 1 && path.endsWith('/')) path = path.slice(0, -1);

    const rows = await strapi.documents('plugin::redirects.redirect').findMany({
      filters: { from: path },
      locale,
      status: 'published',
    });

    if (!rows.length) {
      ctx.status = 404;
      ctx.body = { type: 'notFound' };
      return;
    }
    const row = rows[0];
    ctx.body = {
      type: 'redirect',
      to: row.to,
      statusCode: row.statusCode || cfg('defaultStatusCode'),
    };
  },
});
