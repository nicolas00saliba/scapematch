import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PayoutFailure implements Exception {
  const PayoutFailure(this.code);

  final String code;
}

class VenueReceivable {
  const VenueReceivable({
    required this.cents,
    required this.creditDate,
    required this.description,
  });

  final int cents;
  final String creditDate;
  final String description;
}

class VenueBankSummary {
  const VenueBankSummary({
    required this.destination,
    required this.operationType,
    required this.ownerName,
    this.pixKeyType,
    this.pixKeyMasked,
    this.bankCode,
    this.agency,
    this.accountMasked,
  });

  final String destination;
  final String operationType;
  final String ownerName;
  final String? pixKeyType;
  final String? pixKeyMasked;
  final String? bankCode;
  final String? agency;
  final String? accountMasked;
}

class VenueBankDraft {
  const VenueBankDraft({
    required this.destination,
    required this.ownerName,
    required this.ownerDocument,
    required this.operationType,
    this.pixKey = '',
    this.pixKeyType = 'CNPJ',
    this.bankCode = '',
    this.agency = '',
    this.accountNumber = '',
    this.accountDigit = '',
  });

  final String destination;
  final String ownerName;
  final String ownerDocument;
  final String operationType;
  final String pixKey;
  final String pixKeyType;
  final String bankCode;
  final String agency;
  final String accountNumber;
  final String accountDigit;
}

class VenuePayoutSchedule {
  const VenuePayoutSchedule({
    required this.enabled,
    required this.frequency,
    required this.minAmountCents,
    this.weekday,
  });

  final bool enabled;
  final String frequency;
  final int minAmountCents;
  final int? weekday;

  VenuePayoutSchedule copyWith({
    bool? enabled,
    String? frequency,
    int? minAmountCents,
    int? weekday,
    bool clearWeekday = false,
  }) {
    return VenuePayoutSchedule(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      minAmountCents: minAmountCents ?? this.minAmountCents,
      weekday: clearWeekday ? null : weekday ?? this.weekday,
    );
  }
}

class VenueWithdrawal {
  const VenueWithdrawal({
    required this.id,
    required this.amountCents,
    required this.status,
    required this.source,
    required this.createdAt,
    this.receiptUrl,
    this.failureReason,
  });

  final String id;
  final int amountCents;
  final String status;
  final String source;
  final DateTime createdAt;
  final String? receiptUrl;
  final String? failureReason;
}

class VenuePayoutSnapshot {
  const VenuePayoutSnapshot({
    required this.enabled,
    required this.canWithdraw,
    required this.role,
    required this.availableCents,
    required this.pendingCents,
    required this.schedule,
    required this.receivables,
    required this.withdrawals,
    this.blockedUntil,
    this.bank,
  });

  final bool enabled;
  final bool canWithdraw;
  final String role;
  final int availableCents;
  final int pendingCents;
  final VenuePayoutSchedule schedule;
  final List<VenueReceivable> receivables;
  final List<VenueWithdrawal> withdrawals;
  final DateTime? blockedUntil;
  final VenueBankSummary? bank;

  static const hidden = VenuePayoutSnapshot(
    enabled: false,
    canWithdraw: false,
    role: 'none',
    availableCents: 0,
    pendingCents: 0,
    schedule: VenuePayoutSchedule(
      enabled: false,
      frequency: 'weekly',
      weekday: 1,
      minAmountCents: 0,
    ),
    receivables: [],
    withdrawals: [],
  );

  /// Dados de exemplo. Não movimenta dinheiro.
  factory VenuePayoutSnapshot.sample() {
    return VenuePayoutSnapshot(
      enabled: true,
      canWithdraw: true,
      role: 'owner',
      availableCents: 128050,
      pendingCents: 0,
      bank: const VenueBankSummary(
        destination: 'pix',
        pixKeyType: 'CNPJ',
        pixKeyMasked: '**********0199',
        operationType: 'PIX',
        ownerName: 'Casa do Saque',
      ),
      schedule: const VenuePayoutSchedule(
        enabled: false,
        frequency: 'weekly',
        weekday: 1,
        minAmountCents: 5000,
      ),
      receivables: const [
        VenueReceivable(
          cents: 32000,
          creditDate: '2026-11-18',
          description: 'Grupo da quinta',
        ),
      ],
      withdrawals: [
        VenueWithdrawal(
          id: 'saque-concluido',
          amountCents: 80000,
          status: 'done',
          source: 'manual',
          receiptUrl: 'https://example.com/comprovante',
          createdAt: DateTime.utc(2026, 11, 10),
        ),
        VenueWithdrawal(
          id: 'saque-pendente',
          amountCents: 15000,
          status: 'pending',
          source: 'automatic',
          createdAt: DateTime.utc(2026, 11, 12),
        ),
        VenueWithdrawal(
          id: 'saque-falhou',
          amountCents: 4000,
          status: 'failed',
          source: 'manual',
          failureReason: 'asaas_unavailable',
          createdAt: DateTime.utc(2026, 11, 8),
        ),
      ],
    );
  }

  bool get withdrawalsBlocked {
    final until = blockedUntil;
    return until != null && until.isAfter(DateTime.now());
  }
}

/// Lê um valor em reais. "1.280,50" e "1280.50" viram centavos.
int? parseWithdrawalAmount(String raw) {
  var text = raw.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (text.isEmpty) return null;
  if (text.contains(',')) {
    text = text.replaceAll('.', '').replaceAll(',', '.');
  }
  final value = double.tryParse(text);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

String payoutErrorMessage(String code) {
  return switch (code) {
    'titularidade' => 'A conta precisa estar no mesmo CPF ou CNPJ da casa.',
    'saldo' => 'O valor passa do saldo disponível.',
    'bloqueado' =>
      'Os saques ficam bloqueados por 24 horas depois da troca da conta.',
    'saques desligados' => 'Os saques ainda não estão liberados.',
    'not owner' => 'Só o dono ou um admin da casa pode sacar.',
    'reauth' => 'Confirme a senha de novo para sacar.',
    'mfa' => 'Informe o código do autenticador.',
    'sem conta' => 'Cadastre a conta de saque antes.',
    'sem pix' =>
      'Este banco ou esta chave não aceita Pix. Cadastre uma chave Pix ou uma conta que receba Pix.',
    'sem subconta' => 'A subconta da casa ainda não está pronta.',
    'reserva' => 'Essa conta não pode sacar.',
    'valor' => 'Confira os dados da conta e o valor.',
    _ => 'Não foi possível concluir agora.',
  };
}

abstract class VenueWithdrawalRepository {
  Future<VenuePayoutSnapshot> load(String venueId);

  Future<bool> needsTotp();

  /// Nulo quando a senha, ou o código, conferiu.
  Future<String?> reauthenticate({
    required String email,
    required String password,
    String? totp,
  });

  Future<VenuePayoutSnapshot> saveBank(String venueId, VenueBankDraft draft);

  Future<VenuePayoutSnapshot> saveSchedule(
    String venueId,
    VenuePayoutSchedule schedule,
  );

  Future<VenuePayoutSnapshot> withdraw(String venueId, int amountCents);
}

class MemoryVenueWithdrawalRepository implements VenueWithdrawalRepository {
  MemoryVenueWithdrawalRepository(
    VenuePayoutSnapshot snapshot, {
    this.houseDocument = '55667788000199',
    this.totpRequired = false,
  }) : _snapshot = snapshot;

  VenuePayoutSnapshot _snapshot;
  final String houseDocument;
  final bool totpRequired;
  var confirmed = false;
  final List<String> actions = [];

  @override
  Future<VenuePayoutSnapshot> load(String venueId) async => _snapshot;

  @override
  Future<bool> needsTotp() async => totpRequired;

  @override
  Future<String?> reauthenticate({
    required String email,
    required String password,
    String? totp,
  }) async {
    if (password.trim().length < 4) return 'Informe a senha de novo.';
    if (totpRequired && (totp == null || totp.trim().length != 6)) {
      return 'Informe o código do autenticador.';
    }
    confirmed = true;
    return null;
  }

  @override
  Future<VenuePayoutSnapshot> saveBank(
    String venueId,
    VenueBankDraft draft,
  ) async {
    _requireConfirmed();
    final document = draft.ownerDocument.replaceAll(RegExp(r'\D'), '');
    if (document != houseDocument) throw const PayoutFailure('titularidade');
    if (draft.operationType.toUpperCase() == 'TED') {
      throw const PayoutFailure('sem pix');
    }
    if (draft.destination == 'pix' &&
        (draft.pixKeyType == 'CPF' || draft.pixKeyType == 'CNPJ')) {
      final key = draft.pixKey.replaceAll(RegExp(r'\D'), '');
      if (key != houseDocument) throw const PayoutFailure('titularidade');
    }
    actions.add('bank');
    final masked = draft.destination == 'pix'
        ? draft.pixKey
        : draft.accountNumber;
    final tail = masked.length <= 4
        ? masked
        : masked.substring(masked.length - 4);
    _snapshot = VenuePayoutSnapshot(
      enabled: _snapshot.enabled,
      canWithdraw: _snapshot.canWithdraw,
      role: _snapshot.role,
      availableCents: _snapshot.availableCents,
      pendingCents: _snapshot.pendingCents,
      schedule: _snapshot.schedule,
      receivables: _snapshot.receivables,
      withdrawals: _snapshot.withdrawals,
      blockedUntil: DateTime.now().add(const Duration(hours: 24)),
      bank: VenueBankSummary(
        destination: draft.destination,
        operationType: 'PIX',
        ownerName: draft.ownerName,
        pixKeyType: draft.pixKeyType,
        pixKeyMasked: '****$tail',
        bankCode: draft.bankCode,
        agency: draft.agency,
        accountMasked: '****$tail',
      ),
    );
    confirmed = false;
    return _snapshot;
  }

  @override
  Future<VenuePayoutSnapshot> saveSchedule(
    String venueId,
    VenuePayoutSchedule schedule,
  ) async {
    _requireConfirmed();
    if (schedule.frequency != 'weekly' || schedule.weekday == null) {
      throw const PayoutFailure('valor');
    }
    actions.add('schedule');
    _snapshot = VenuePayoutSnapshot(
      enabled: _snapshot.enabled,
      canWithdraw: _snapshot.canWithdraw,
      role: _snapshot.role,
      availableCents: _snapshot.availableCents,
      pendingCents: _snapshot.pendingCents,
      schedule: schedule,
      receivables: _snapshot.receivables,
      withdrawals: _snapshot.withdrawals,
      blockedUntil: _snapshot.blockedUntil,
      bank: _snapshot.bank,
    );
    confirmed = false;
    return _snapshot;
  }

  @override
  Future<VenuePayoutSnapshot> withdraw(String venueId, int amountCents) async {
    _requireConfirmed();
    if (_snapshot.withdrawalsBlocked) throw const PayoutFailure('bloqueado');
    if (!_snapshot.canWithdraw) throw const PayoutFailure('not owner');
    if (amountCents <= 0 || amountCents > _snapshot.availableCents) {
      throw const PayoutFailure('saldo');
    }
    actions.add('withdraw:$amountCents');
    _snapshot = VenuePayoutSnapshot(
      enabled: _snapshot.enabled,
      canWithdraw: _snapshot.canWithdraw,
      role: _snapshot.role,
      availableCents: _snapshot.availableCents - amountCents,
      pendingCents: _snapshot.pendingCents + amountCents,
      schedule: _snapshot.schedule,
      receivables: _snapshot.receivables,
      blockedUntil: _snapshot.blockedUntil,
      bank: _snapshot.bank,
      withdrawals: [
        VenueWithdrawal(
          id: 'novo',
          amountCents: amountCents,
          status: 'pending',
          source: 'manual',
          createdAt: DateTime.utc(2026, 11, 12),
        ),
        ..._snapshot.withdrawals,
      ],
    );
    confirmed = false;
    return _snapshot;
  }

  void _requireConfirmed() {
    if (!confirmed) throw const PayoutFailure('reauth');
  }
}

class SupabaseVenueWithdrawalRepository implements VenueWithdrawalRepository {
  @override
  Future<VenuePayoutSnapshot> load(String venueId) async {
    try {
      return _snapshot(
        await _invoke({'action': 'snapshot', 'venue_id': venueId}),
      );
    } on Object {
      return VenuePayoutSnapshot.hidden;
    }
  }

  @override
  Future<bool> needsTotp() async {
    try {
      final factors = await scapeSupabase.auth.mfa.listFactors();
      return factors.totp.any(
        (factor) => factor.status == FactorStatus.verified,
      );
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> reauthenticate({
    required String email,
    required String password,
    String? totp,
  }) async {
    try {
      await scapeSupabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final factors = await scapeSupabase.auth.mfa.listFactors();
      final verified = factors.totp
          .where((factor) => factor.status == FactorStatus.verified)
          .toList();
      if (verified.isEmpty) return null;
      final code = totp?.trim() ?? '';
      if (code.length != 6) return 'Informe o código do autenticador.';
      final challenge = await scapeSupabase.auth.mfa.challenge(
        factorId: verified.first.id,
      );
      await scapeSupabase.auth.mfa.verify(
        factorId: verified.first.id,
        challengeId: challenge.id,
        code: code,
      );
      return null;
    } on Object {
      return 'Não foi possível confirmar que é você.';
    }
  }

  @override
  Future<VenuePayoutSnapshot> saveBank(
    String venueId,
    VenueBankDraft draft,
  ) async {
    return _snapshot(
      await _invoke({
        'action': 'save_bank',
        'venue_id': venueId,
        'destination': draft.destination,
        'pix_key': draft.pixKey,
        'pix_key_type': draft.pixKeyType,
        'bank_code': draft.bankCode,
        'agency': draft.agency,
        'account_number': draft.accountNumber,
        'account_digit': draft.accountDigit,
        'owner_name': draft.ownerName,
        'owner_document': draft.ownerDocument,
        'operation_type': draft.operationType,
      }),
    );
  }

  @override
  Future<VenuePayoutSnapshot> saveSchedule(
    String venueId,
    VenuePayoutSchedule schedule,
  ) async {
    return _snapshot(
      await _invoke({
        'action': 'save_schedule',
        'venue_id': venueId,
        'enabled': schedule.enabled,
        'frequency': schedule.frequency,
        'weekday': schedule.weekday,
        'min_amount_cents': schedule.minAmountCents,
      }),
    );
  }

  @override
  Future<VenuePayoutSnapshot> withdraw(String venueId, int amountCents) async {
    return _snapshot(
      await _invoke({
        'action': 'withdraw',
        'venue_id': venueId,
        'amount_cents': amountCents,
      }),
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'venue-payouts',
        body: body,
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw PayoutFailure(data['error'].toString());
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const PayoutFailure('erro');
    } on PayoutFailure {
      rethrow;
    } on Object catch (error) {
      throw PayoutFailure(_code(error));
    }
  }

  String _code(Object error) {
    try {
      final details = (error as dynamic).details;
      if (details is Map && details['error'] != null) {
        return details['error'].toString();
      }
    } on Object {
      // O texto abaixo ainda pode trazer o código estável.
    }
    final text = error.toString();
    for (final code in const [
      'titularidade',
      'saldo',
      'bloqueado',
      'saques desligados',
      'not owner',
      'reauth',
      'mfa',
    'sem conta',
    'sem pix',
    'sem subconta',
      'reserva',
      'valor',
    ]) {
      if (text.contains(code)) return code;
    }
    return 'erro';
  }

  VenuePayoutSnapshot _snapshot(Map<String, dynamic> json) {
    final bank = json['bank'];
    final schedule = json['schedule'];
    final scheduleMap = schedule is Map ? schedule : const {};
    return VenuePayoutSnapshot(
      enabled: json['enabled'] == true,
      canWithdraw: json['can_withdraw'] == true,
      role: json['role']?.toString() ?? 'none',
      availableCents: _int(json['available_cents']),
      pendingCents: _int(json['pending_cents']),
      blockedUntil: DateTime.tryParse(json['blocked_until']?.toString() ?? ''),
      bank: bank is Map
          ? VenueBankSummary(
              destination: bank['destination']?.toString() ?? 'pix',
              operationType: bank['operation_type']?.toString() ?? 'PIX',
              ownerName: bank['owner_name']?.toString() ?? '',
              pixKeyType: bank['pix_key_type']?.toString(),
              pixKeyMasked: bank['pix_key_masked']?.toString(),
              bankCode: bank['bank_code']?.toString(),
              agency: bank['agency']?.toString(),
              accountMasked: bank['account_masked']?.toString(),
            )
          : null,
      schedule: VenuePayoutSchedule(
        enabled: scheduleMap['enabled'] == true,
        frequency: 'weekly',
        weekday: scheduleMap['weekday'] is int
            ? scheduleMap['weekday'] as int
            : null,
        minAmountCents: _int(scheduleMap['min_amount_cents']),
      ),
      receivables: [
        for (final row in _rows(json['receivables']))
          VenueReceivable(
            cents: _int(row['cents']),
            creditDate:
                row['creditDate']?.toString() ??
                row['credit_date']?.toString() ??
                '',
            description: row['description']?.toString() ?? 'A receber',
          ),
      ],
      withdrawals: [
        for (final row in _rows(json['withdrawals']))
          VenueWithdrawal(
            id: row['id']?.toString() ?? '',
            amountCents: _int(row['amount_cents']),
            status: row['status']?.toString() ?? 'pending',
            source: row['source']?.toString() ?? 'manual',
            receiptUrl: row['receipt_url']?.toString(),
            failureReason: row['failure_reason']?.toString(),
            createdAt:
                DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.utc(2026),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return [
      for (final row in value)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

final venueWithdrawalRepositoryProvider = Provider<VenueWithdrawalRepository>((
  ref,
) {
  if (ref.watch(backendPlanProvider).connectsSupabase) {
    return SupabaseVenueWithdrawalRepository();
  }
  return MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample());
});
