export default {
  'content-api': {
    type: 'content-api',
    routes: [{ method: 'GET', path: '/match', handler: 'redirect.match', config: { auth: false } }],
  },
};
