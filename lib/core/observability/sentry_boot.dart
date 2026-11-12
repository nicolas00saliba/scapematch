import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:scapematch/core/observability/pii.dart';

/// Todo erro é enviado. O traço de performance fica em 5%.
const double taxaAmostragemErros = 1;

/// Performance fica bem abaixo da captura de erros.
const double taxaAmostragemTraces = 0.05;

/// Inicia o Sentry só com um DSN https válido vindo de `--dart-define`.
/// Sem `SENTRY_DSN`, o app sobe igual e o SDK não é carregado.
Future<void> iniciarSentry(Future<void> Function() app) async {
  const dsn = String.fromEnvironment('SENTRY_DSN');
  if (!dsnValido(dsn)) {
    await app();
    return;
  }

  const release = String.fromEnvironment('SENTRY_RELEASE');
  const environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'local',
  );

  await SentryFlutter.init((options) {
    options.dsn = dsn;
    options.environment = environment;
    if (release.isNotEmpty) {
      options.release = release;
    }
    options.sendDefaultPii = false;
    options.sampleRate = taxaAmostragemErros;
    options.tracesSampleRate = taxaAmostragemTraces;
    options.maxRequestBodySize = MaxRequestBodySize.never;
    options.beforeSend = _antesDeEnviar;
    options.beforeBreadcrumb = _antesDoBreadcrumb;
  }, appRunner: app);
}

Future<SentryEvent?> _antesDeEnviar(SentryEvent event, Hint hint) async {
  try {
    _redigirEvento(event);
    return event;
  } on Object {
    return null;
  }
}

Breadcrumb? _antesDoBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) {
    return null;
  }
  try {
    final message = breadcrumb.message;
    if (message != null) {
      breadcrumb.message = redigirPii(message);
    }
    final data = breadcrumb.data;
    if (data != null) {
      breadcrumb.data = (redigirValor(data) as Map).cast<String, dynamic>();
    }
    return breadcrumb;
  } on Object {
    return null;
  }
}

void _redigirEvento(SentryEvent event) {
  final message = event.message;
  if (message != null) {
    event.message = SentryMessage(
      redigirPii(message.formatted),
      template: message.template == null ? null : redigirPii(message.template!),
    );
  }

  final user = event.user;
  if (user != null) {
    user.email = null;
    user.ipAddress = null;
    final username = user.username;
    if (username != null) {
      user.username = redigirPii(username);
    }
    final name = user.name;
    if (name != null) {
      user.name = redigirPii(name);
    }
    final data = user.data;
    if (data != null) {
      user.data = (redigirValor(data) as Map).cast<String, dynamic>();
    }
  }

  final request = event.request;
  if (request != null) {
    final url = request.url;
    if (url != null) {
      request.url = redigirPii(url);
    }
    final query = request.queryString;
    if (query != null) {
      request.queryString = redigirPii(query);
    }
    final fragment = request.fragment;
    if (fragment != null) {
      request.fragment = redigirPii(fragment);
    }
    request.cookies = null;
    if (request.headers.isNotEmpty) {
      request.headers = {
        for (final entry in request.headers.entries)
          entry.key: redigirPii(entry.value),
      };
    }
  }

  final exceptions = event.exceptions;
  if (exceptions != null) {
    for (final exception in exceptions) {
      final value = exception.value;
      if (value != null) {
        exception.value = redigirPii(value);
      }
    }
  }

  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null) {
    for (final breadcrumb in breadcrumbs) {
      _antesDoBreadcrumb(breadcrumb, Hint());
    }
  }
}
