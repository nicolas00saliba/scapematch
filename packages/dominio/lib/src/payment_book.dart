import 'package:dominio/src/closing.dart';
import 'package:dominio/src/commission.dart';
import 'package:dominio/src/ledger.dart';
import 'package:dominio/src/payment_exception.dart';
import 'package:dominio/src/payment_provider.dart';
import 'package:dominio/src/platform_settings.dart';
import 'package:dominio/src/reservation.dart';

/// Cobrança guardada pelo livro, ligada à resposta do provedor.
class StoredCharge {
  const StoredCharge({
    required this.id,
    required this.shareId,
    required this.idempotencyKey,
    required this.amountCents,
    required this.kind,
    required this.result,
  });

  final String id;
  final String shareId;
  final String idempotencyKey;
  final int amountCents;
  final PaymentMethodKind kind;
  final ChargeResult result;
}

/// Livro em memória: reserva a parte, captura quando o grupo fecha e estorna
/// com linhas novas só o que já foi capturado.
///
/// A tela da fase 3 chama estes métodos. O banco, na fase 4, troca o miolo
/// por funções com RLS sem mudar a conta.
class PaymentBook {
  PaymentBook({required this.provider, PlatformSettings? opening})
    : settings = PlatformSettingsBook(opening: opening);

  final PaymentProvider provider;
  final PlatformSettingsBook settings;

  final Map<String, Reservation> _reservations = {};
  final List<LedgerEntry> _entries = [];
  final Map<String, StoredCharge> _paymentsByKey = {};
  final Map<String, StoredCharge> _refundsByKey = {};
  final Map<String, StoredCharge> _paymentByShare = {};
  var _sequence = 0;

  List<LedgerEntry> get entries => List.unmodifiable(_entries);

  List<AuditEntry> get audit => List.unmodifiable(settings.audit);

  Reservation? lookup(String id) => _reservations[id];

  Reservation reservation(String id) {
    final found = lookup(id);
    if (found == null) {
      throw PaymentException('Reserva não encontrada.');
    }
    return found;
  }

  /// Acrescenta um jogador que entrou depois, pelo preço da parte dele.
  ///
  /// A taxa é a foto da reserva. Quem já está na reserva não muda.
  Reservation addShare({
    required String reservationId,
    required String playerId,
    required int amountCents,
  }) {
    final current = reservation(reservationId);
    if (playerId.trim().isEmpty) {
      throw PaymentException('O jogador da parte não pode ficar vazio.');
    }
    if (amountCents < 0) {
      throw PaymentException('O valor não pode ser negativo.');
    }
    final open = current.shares.any(
      (share) =>
          share.playerId == playerId &&
          share.status != ShareStatus.refunded &&
          share.status != ShareStatus.released,
    );
    if (open) {
      return current;
    }
    final commission = commissionCents(amountCents, current.commissionBps);
    final updated = Reservation(
      id: current.id,
      groupId: current.groupId,
      houseId: current.houseId,
      commissionBps: current.commissionBps,
      totalCents: current.totalCents,
      priceMode: current.priceMode,
      shares: [
        ...current.shares,
        ReservationShare(
          id: '$reservationId-share-$playerId-${current.shares.length}',
          playerId: playerId,
          amountCents: amountCents,
          commissionCents: commission,
          netCents: amountCents - commission,
          status: ShareStatus.pending,
        ),
      ],
    );
    _reservations[reservationId] = updated;
    return updated;
  }

  int houseBalance(String houseId) {
    return ledgerBalance(
      _entries,
      account: LedgerAccount.house,
      houseId: houseId,
    );
  }

  int get platformBalance {
    return ledgerBalance(_entries, account: LedgerAccount.platform);
  }

  /// Abre a reserva com a taxa de agora gravada nas partes.
  Reservation createReservation({
    required String id,
    required String groupId,
    required String houseId,
    required int totalCents,
    required List<String> playerIds,
    PriceMode priceMode = PriceMode.perPerson,
  }) {
    if (_reservations.containsKey(id)) {
      throw PaymentException('Já existe uma reserva com esse id.');
    }
    if (groupId.trim().isEmpty || houseId.trim().isEmpty) {
      throw PaymentException('Grupo e casa são obrigatórios.');
    }
    if (playerIds.isEmpty) {
      throw PaymentException('A reserva precisa de pelo menos um jogador.');
    }
    if (playerIds.toSet().length != playerIds.length) {
      throw PaymentException('Cada jogador entra uma vez na reserva.');
    }
    if (playerIds.any((playerId) => playerId.trim().isEmpty)) {
      throw PaymentException('O jogador da parte não pode ficar vazio.');
    }
    final bps = settings.rateFor(houseId);
    final quotes = quoteShares(
      totalCents: totalCents,
      playerCount: playerIds.length,
      commissionBps: bps,
    );
    final reservation = Reservation(
      id: id,
      groupId: groupId,
      houseId: houseId,
      commissionBps: bps,
      totalCents: totalCents,
      priceMode: priceMode,
      shares: [
        for (var i = 0; i < playerIds.length; i++)
          ReservationShare(
            id: '$id-share-$i',
            playerId: playerIds[i],
            amountCents: quotes[i].amountCents,
            commissionCents: quotes[i].commissionCents,
            netCents: quotes[i].netCents,
            status: ShareStatus.pending,
          ),
      ],
    );
    _reservations[id] = reservation;
    return reservation;
  }

  /// Separa o valor (pré-autorização). O extrato da casa só muda na captura.
  Future<Reservation> payShare({
    required String reservationId,
    required String shareId,
    required PaymentMethodKind kind,
    required String idempotencyKey,
  }) async {
    _requireKey(idempotencyKey);
    final prior = _paymentsByKey[idempotencyKey];
    if (prior != null) {
      if (prior.shareId != shareId) {
        throw IdempotencyConflictException();
      }
      return reservation(reservationId);
    }
    final current = reservation(reservationId);
    final share = _share(current, shareId);
    if (share.status == ShareStatus.paid ||
        share.status == ShareStatus.reserved) {
      throw PaymentException('Essa parte já foi reservada.');
    }
    if (share.status != ShareStatus.pending &&
        share.status != ShareStatus.failed) {
      throw PaymentException('Essa parte não está aberta para pagamento.');
    }
    final result = await provider.chargeShare(
      shareId: share.id,
      amountCents: share.amountCents,
      kind: kind,
      idempotencyKey: idempotencyKey,
    );
    final charge = StoredCharge(
      id: _nextId('charge'),
      shareId: share.id,
      idempotencyKey: idempotencyKey,
      amountCents: share.amountCents,
      kind: kind,
      result: result,
    );
    _paymentsByKey[idempotencyKey] = charge;
    if (!result.succeeded) {
      _put(current.copyWithShare(share.copyWith(status: ShareStatus.failed)));
      return reservation(reservationId);
    }
    _paymentByShare[share.id] = charge;
    _put(current.copyWithShare(share.copyWith(status: ShareStatus.reserved)));
    return reservation(reservationId);
  }

  /// O grupo fechou. Cada parte reservada entra no extrato, com a comissão.
  Future<Reservation> captureReservation({
    required String reservationId,
    required String idempotencyKey,
    List<String>? onlyPlayerIds,
  }) async {
    _requireKey(idempotencyKey);
    final current = reservation(reservationId);
    final wanted = onlyPlayerIds?.toSet();
    final pending = current.shares.any(
      (share) =>
          share.status == ShareStatus.awaitingConfirmation &&
          (wanted == null || wanted.contains(share.playerId)),
    );
    if (pending) {
      throw PaymentException(
        'Quem já reservou precisa confirmar o novo valor.',
      );
    }
    var updated = current;
    for (final share in current.shares) {
      if (share.status != ShareStatus.reserved) {
        continue;
      }
      if (wanted != null && !wanted.contains(share.playerId)) {
        continue;
      }
      final key = '$idempotencyKey-${share.id}';
      if (_paymentsByKey.containsKey('capture-$key')) {
        continue;
      }
      final charge = _paymentByShare[share.id];
      if (charge == null) {
        throw PaymentException('A reserva dessa parte não está no livro.');
      }
      _paymentsByKey['capture-$key'] = charge;
      _credit(updated, share, charge.id);
      updated = updated.copyWithShare(share.copyWith(status: ShareStatus.paid));
      _put(updated);
    }
    return reservation(reservationId);
  }

  /// Solta as reservas ainda abertas. Não escreve extrato: nada foi capturado.
  Future<Reservation> releaseReservation({
    required String reservationId,
    required String idempotencyKey,
  }) async {
    _requireKey(idempotencyKey);
    final current = reservation(reservationId);
    var updated = current;
    for (final share in current.shares) {
      if (share.status != ShareStatus.reserved &&
          share.status != ShareStatus.awaitingConfirmation) {
        continue;
      }
      updated = await _releaseOne(updated, share, '$idempotencyKey-${share.id}');
    }
    return updated;
  }

  Future<Reservation> releaseShare({
    required String reservationId,
    required String shareId,
    required String idempotencyKey,
  }) async {
    _requireKey(idempotencyKey);
    final current = reservation(reservationId);
    final share = _share(current, shareId);
    if (share.status == ShareStatus.released) {
      return current;
    }
    if (share.status != ShareStatus.reserved &&
        share.status != ShareStatus.awaitingConfirmation) {
      throw PaymentException('Só uma reserva em aberto pode ser liberada.');
    }
    return _releaseOne(current, share, idempotencyKey);
  }

  /// Preço fixo do grupo: divide o total original entre quem ficou.
  ///
  /// Quem já reservou outro valor fica aguardando confirmação. Preço por
  /// pessoa não muda as partes.
  Reservation repriceFixedClose({
    required String reservationId,
    required List<String> playerIds,
    required int roomMinimum,
    required int planned,
  }) {
    requireCloseWithFewer(
      seated: playerIds.length,
      roomMinimum: roomMinimum,
      planned: planned,
    );
    final current = reservation(reservationId);
    if (current.priceMode != PriceMode.fixedGroup) {
      return current;
    }
    if (playerIds.toSet().length != playerIds.length) {
      throw PaymentException('Cada jogador entra uma vez na reserva.');
    }
    final quotes = quoteShares(
      totalCents: current.totalCents,
      playerCount: playerIds.length,
      commissionBps: current.commissionBps,
    );
    final byPlayer = {
      for (var i = 0; i < playerIds.length; i++) playerIds[i]: quotes[i],
    };
    final next = <ReservationShare>[];
    for (final share in current.shares) {
      final quote = byPlayer[share.playerId];
      if (quote == null ||
          share.status == ShareStatus.paid ||
          share.status == ShareStatus.refunded ||
          share.status == ShareStatus.released) {
        next.add(share);
        continue;
      }
      if (quote.amountCents == share.amountCents) {
        next.add(share);
        continue;
      }
      next.add(
        share.copyWith(
          status: ShareStatus.awaitingConfirmation,
          proposedAmountCents: quote.amountCents,
          proposedCommissionCents: quote.commissionCents,
          proposedNetCents: quote.netCents,
        ),
      );
    }
    final updated = current.copyWithShares(next);
    _put(updated);
    return updated;
  }

  Reservation confirmAdjustedShare({
    required String reservationId,
    required String shareId,
  }) {
    final current = reservation(reservationId);
    final share = _share(current, shareId);
    if (share.status != ShareStatus.awaitingConfirmation) {
      throw PaymentException('Essa parte não está aguardando confirmação.');
    }
    final amount = share.proposedAmountCents;
    final commission = share.proposedCommissionCents;
    final net = share.proposedNetCents;
    if (amount == null || commission == null || net == null) {
      throw PaymentException('O novo valor dessa parte não foi calculado.');
    }
    final updated = current.copyWithShare(
      share.copyWith(
        status: ShareStatus.reserved,
        amountCents: amount,
        commissionCents: commission,
        netCents: net,
        clearProposal: true,
      ),
    );
    _put(updated);
    return updated;
  }

  /// Devolve a parte. As linhas do pagamento ficam. O estorno entra por cima.
  Future<Reservation> refundShare({
    required String reservationId,
    required String shareId,
    required String idempotencyKey,
  }) async {
    _requireKey(idempotencyKey);
    final prior = _refundsByKey[idempotencyKey];
    if (prior != null) {
      if (prior.shareId != shareId) {
        throw IdempotencyConflictException();
      }
      return reservation(reservationId);
    }
    final current = reservation(reservationId);
    final share = _share(current, shareId);
    if (share.status != ShareStatus.paid) {
      throw PaymentException('Só uma parte paga pode ser estornada.');
    }
    final payment = _paymentByShare[share.id];
    if (payment == null) {
      throw PaymentException('A cobrança dessa parte não está no livro.');
    }
    final result = await provider.refund(
      chargeId: payment.id,
      amountCents: share.amountCents,
      idempotencyKey: idempotencyKey,
    );
    final refund = StoredCharge(
      id: _nextId('refund'),
      shareId: share.id,
      idempotencyKey: idempotencyKey,
      amountCents: share.amountCents,
      kind: payment.kind,
      result: result,
    );
    _refundsByKey[idempotencyKey] = refund;
    if (!result.succeeded) {
      return current;
    }
    _debit(current, share, refund.id);
    _put(current.copyWithShare(share.copyWith(status: ShareStatus.refunded)));
    return reservation(reservationId);
  }

  Future<Reservation> _releaseOne(
    Reservation current,
    ReservationShare share,
    String idempotencyKey,
  ) async {
    final prior = _refundsByKey[idempotencyKey];
    if (prior != null) {
      return reservation(current.id);
    }
    final payment = _paymentByShare[share.id];
    if (payment != null) {
      final result = await provider.refund(
        chargeId: payment.id,
        amountCents: share.amountCents,
        idempotencyKey: idempotencyKey,
      );
      _refundsByKey[idempotencyKey] = StoredCharge(
        id: _nextId('release'),
        shareId: share.id,
        idempotencyKey: idempotencyKey,
        amountCents: share.amountCents,
        kind: payment.kind,
        result: result,
      );
      if (!result.succeeded) {
        return current;
      }
    }
    final updated = current.copyWithShare(
      share.copyWith(status: ShareStatus.released, clearProposal: true),
    );
    _put(updated);
    return updated;
  }

  void _credit(
    Reservation reservation,
    ReservationShare share,
    String chargeId,
  ) {
    _addEntry(
      reservation: reservation,
      share: share,
      chargeId: chargeId,
      account: LedgerAccount.house,
      direction: LedgerDirection.credit,
      kind: LedgerKind.houseNet,
      amountCents: share.netCents,
    );
    _addEntry(
      reservation: reservation,
      share: share,
      chargeId: chargeId,
      account: LedgerAccount.platform,
      direction: LedgerDirection.credit,
      kind: LedgerKind.commission,
      amountCents: share.commissionCents,
    );
  }

  void _debit(
    Reservation reservation,
    ReservationShare share,
    String chargeId,
  ) {
    _addEntry(
      reservation: reservation,
      share: share,
      chargeId: chargeId,
      account: LedgerAccount.house,
      direction: LedgerDirection.debit,
      kind: LedgerKind.houseRefund,
      amountCents: share.netCents,
    );
    _addEntry(
      reservation: reservation,
      share: share,
      chargeId: chargeId,
      account: LedgerAccount.platform,
      direction: LedgerDirection.debit,
      kind: LedgerKind.commissionRefund,
      amountCents: share.commissionCents,
    );
  }

  void _addEntry({
    required Reservation reservation,
    required ReservationShare share,
    required String chargeId,
    required LedgerAccount account,
    required LedgerDirection direction,
    required LedgerKind kind,
    required int amountCents,
  }) {
    if (amountCents == 0) {
      return;
    }
    _entries.add(
      LedgerEntry(
        id: _nextId('ledger'),
        houseId: reservation.houseId,
        reservationId: reservation.id,
        shareId: share.id,
        chargeId: chargeId,
        account: account,
        direction: direction,
        kind: kind,
        amountCents: amountCents,
      ),
    );
  }

  ReservationShare _share(Reservation reservation, String shareId) {
    for (final share in reservation.shares) {
      if (share.id == shareId) {
        return share;
      }
    }
    throw PaymentException('Parte não encontrada.');
  }

  void _put(Reservation reservation) {
    _reservations[reservation.id] = reservation;
  }

  void _requireKey(String idempotencyKey) {
    if (idempotencyKey.trim().isEmpty) {
      throw PaymentException(
        'A cobrança precisa de uma chave de idempotência.',
      );
    }
  }

  String _nextId(String prefix) {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
