/// Disables Riverpod's automatic provider retry.
///
/// Riverpod 3 retries failed providers in the background. This app shows an
/// error message and a button instead, so the user stays in control.
Duration? noAutomaticRetry(int retryCount, Object error) => null;
