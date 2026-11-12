import * as Sentry from '@sentry/astro';

import { redigirBreadcrumb, redigirEvento } from './src/scripts/redigir-pii';

const dsn = import.meta.env.PUBLIC_SENTRY_DSN;

if (typeof dsn === 'string' && dsn.startsWith('https://')) {
  const release = import.meta.env.PUBLIC_SENTRY_RELEASE;
  Sentry.init({
    dsn,
    environment: import.meta.env.PUBLIC_SENTRY_ENVIRONMENT || 'production',
    release: release || undefined,
    sendDefaultPii: false,
    sampleRate: 0.25,
    tracesSampleRate: 0.05,
    beforeSend(evento) {
      return redigirEvento(evento);
    },
    beforeBreadcrumb(breadcrumb) {
      return redigirBreadcrumb(breadcrumb);
    },
  });
}
