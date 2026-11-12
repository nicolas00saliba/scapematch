import * as Sentry from '@sentry/astro';

import { redigirBreadcrumb, redigirEvento } from './src/scripts/redigir-pii';
import {
  taxaAmostragemErros,
  taxaAmostragemTraces,
} from './src/scripts/sentry-taxas';

const dsn = import.meta.env.PUBLIC_SENTRY_DSN;

if (typeof dsn === 'string' && dsn.startsWith('https://')) {
  const release = import.meta.env.PUBLIC_SENTRY_RELEASE;
  Sentry.init({
    dsn,
    environment: import.meta.env.PUBLIC_SENTRY_ENVIRONMENT || 'production',
    release: release || undefined,
    sendDefaultPii: false,
    sampleRate: taxaAmostragemErros,
    tracesSampleRate: taxaAmostragemTraces,
    beforeSend(evento) {
      return redigirEvento(evento);
    },
    beforeBreadcrumb(breadcrumb) {
      return redigirBreadcrumb(breadcrumb);
    },
  });
}
