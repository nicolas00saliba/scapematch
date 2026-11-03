import 'package:dominio/src/commission.dart';
import 'package:dominio/src/payment_exception.dart';

/// Papel de quem chama uma função da plataforma.
enum PlatformRole { player, houseStaff, platformAdmin }

/// Taxa guardada fora da fórmula. O valor inicial é a primeira linha, não
/// um número cravado na cobrança.
class PlatformSettings {
  const PlatformSettings({
    this.commissionBps = openingCommissionBps,
    this.houseOverrides = const {},
  });

  /// 10% na primeira configuração. Quem cobra lê [rateFor], não esta constante.
  static const openingCommissionBps = 1000;

  final int commissionBps;

  /// Override futuro por casa. Vazio até alguém da equipe gravar um.
  final Map<String, int> houseOverrides;

  /// Taxa vigente para a casa: o override, se existir, senão a da plataforma.
  int rateFor(String houseId) => houseOverrides[houseId] ?? commissionBps;

  PlatformSettings copyWith({
    int? commissionBps,
    Map<String, int>? houseOverrides,
  }) {
    return PlatformSettings(
      commissionBps: commissionBps ?? this.commissionBps,
      houseOverrides: houseOverrides ?? this.houseOverrides,
    );
  }
}

/// Registro de uma mudança de taxa. A linha antiga não é editada.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actorId,
    required this.action,
    required this.at,
    required this.beforeBps,
    required this.afterBps,
    this.houseId,
  });

  final String id;
  final String actorId;
  final String action;
  final DateTime at;

  /// Nulo quando a mudança é a taxa da plataforma inteira.
  final String? houseId;
  final int beforeBps;
  final int afterBps;
}

/// Configuração em memória. No Supabase isto vira `platform_settings` e a
/// função auditada que só `platform_admin` executa.
class PlatformSettingsBook {
  PlatformSettingsBook({PlatformSettings? opening})
    : _settings = opening ?? const PlatformSettings();

  PlatformSettings _settings;
  final List<AuditEntry> audit = [];
  var _sequence = 0;

  PlatformSettings get settings => _settings;

  int rateFor(String houseId) => _settings.rateFor(houseId);

  /// Muda a taxa da plataforma. Reservas já abertas não são relidas.
  AuditEntry setPlatformCommission({
    required String actorId,
    required PlatformRole role,
    required int commissionBps,
    required DateTime at,
  }) {
    _requireAdmin(role);
    _requireBps(commissionBps);
    return _record(
      actorId: actorId,
      action: 'set_platform_commission',
      at: at,
      beforeBps: _settings.commissionBps,
      afterBps: commissionBps,
      apply: () {
        _settings = _settings.copyWith(commissionBps: commissionBps);
      },
    );
  }

  /// Reserva a taxa de uma casa. A tela de manutenção usa a mesma trava.
  AuditEntry setHouseCommission({
    required String actorId,
    required PlatformRole role,
    required String houseId,
    required int commissionBps,
    required DateTime at,
  }) {
    _requireAdmin(role);
    _requireBps(commissionBps);
    if (houseId.trim().isEmpty) {
      throw PaymentException('A casa da taxa não pode ficar vazia.');
    }
    final before = _settings.rateFor(houseId);
    return _record(
      actorId: actorId,
      action: 'set_house_commission',
      at: at,
      houseId: houseId,
      beforeBps: before,
      afterBps: commissionBps,
      apply: () {
        final overrides = Map<String, int>.of(_settings.houseOverrides);
        overrides[houseId] = commissionBps;
        _settings = _settings.copyWith(houseOverrides: overrides);
      },
    );
  }

  AuditEntry _record({
    required String actorId,
    required String action,
    required DateTime at,
    required int beforeBps,
    required int afterBps,
    required void Function() apply,
    String? houseId,
  }) {
    apply();
    _sequence += 1;
    final entry = AuditEntry(
      id: 'audit-$_sequence',
      actorId: actorId,
      action: action,
      at: at,
      houseId: houseId,
      beforeBps: beforeBps,
      afterBps: afterBps,
    );
    audit.add(entry);
    return entry;
  }

  void _requireAdmin(PlatformRole role) {
    if (role != PlatformRole.platformAdmin) {
      throw PlatformPermissionException();
    }
  }

  void _requireBps(int basisPoints) {
    if (basisPoints < 0 || basisPoints > maxCommissionBps) {
      throw PaymentException(
        'A comissão fica entre 0 e $maxCommissionBps basis points.',
      );
    }
  }
}
