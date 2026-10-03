export default {
  default: { defaultStatusCode: 301, caseSensitive: false },
  validator(config: { defaultStatusCode: number }) {
    if (![301, 302, 307, 308].includes(config.defaultStatusCode)) {
      throw new Error('redirects: defaultStatusCode must be one of 301, 302, 307, 308');
    }
  },
};
