/// Retorno do OAuth do Mercado Pago no Parceiro real.
const mpOauthRedirectUri = 'https://parceiro.escapematch.com.br/mp-retorno';

const mpOauthReturnPath = '/mp-retorno';

enum MpOauthReturnOutcome { connect, denied, missing }

class MpOauthReturnRequest {
  const MpOauthReturnRequest({
    required this.outcome,
    this.venueId,
    this.code,
    this.state,
  });

  final MpOauthReturnOutcome outcome;
  final String? venueId;
  final String? code;
  final String? state;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isMpOauthReturnPath(Uri uri) {
  return _stripSlash(uri.path).endsWith(mpOauthReturnPath);
}

/// Caminho do app depois do retorno. No Parceiro real é `/`.
String mpReturnHomePath(Uri uri) {
  final path = _stripSlash(uri.path);
  final index = path.lastIndexOf(mpOauthReturnPath);
  if (index <= 0) return '/';
  final prefix = path.substring(0, index);
  return prefix.endsWith('/') ? prefix : '$prefix/';
}

/// O `state` é `v1.<casa>.<expira>.<nonce>.<hmac>`. A casa é o segundo trecho.
String? venueIdFromOauthState(String state) {
  final parts = state.split('.');
  if (parts.length != 5 || parts[0] != 'v1') return null;
  final venueId = parts[1];
  if (!_uuid.hasMatch(venueId)) return null;
  return venueId;
}

MpOauthReturnRequest readMpOauthReturn(Uri uri, {String? sessionHouseId}) {
  if ((uri.queryParameters['error'] ?? '') == 'access_denied') {
    return const MpOauthReturnRequest(outcome: MpOauthReturnOutcome.denied);
  }
  final code = uri.queryParameters['code'] ?? '';
  final state = uri.queryParameters['state'] ?? '';
  if (code.isEmpty || state.isEmpty) {
    return const MpOauthReturnRequest(outcome: MpOauthReturnOutcome.missing);
  }
  final fromState = venueIdFromOauthState(state);
  final fromSession = sessionHouseId != null && _uuid.hasMatch(sessionHouseId)
      ? sessionHouseId
      : null;
  final venueId = fromState ?? fromSession;
  if (venueId == null) {
    return MpOauthReturnRequest(
      outcome: MpOauthReturnOutcome.missing,
      code: code,
      state: state,
    );
  }
  return MpOauthReturnRequest(
    outcome: MpOauthReturnOutcome.connect,
    venueId: venueId,
    code: code,
    state: state,
  );
}

String _stripSlash(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}
