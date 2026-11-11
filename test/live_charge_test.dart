import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/pay_share_sheet.dart';
import 'package:scapematch/features/payments/domain/live_charge.dart';

void main() {
  test('o Pix da cobrança usa o copia-e-cola devolvido', () {
    const payload = '000201ASAAS.PIX.REAL';
    final charge = LiveCharge.fromBody({
      'charge_id': 'ch-1',
      'status': 'pending',
      'billing_type': 'PIX',
      'qr_code': payload,
      'qr_code_base64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      'provider_ref': 'pay_1',
    });

    expect(charge.rejectionMessage, isNull);
    expect(charge.hasPixCode, isTrue);
    expect(charge.confirmsSeat, isFalse);
    expect(charge.qrCode, payload);
    expect(charge.qrCode.contains('scapematch.'), isFalse);
    expect(decodePixQrImage(charge.qrImageBase64), isNotNull);

    final view = ShareChargeView.fromResult(
      PayShareSuccess(_group(), charge: charge),
    );
    expect(view.pixCode, payload);
    expect(view.confirms, isFalse);
    expect(view.hasError, isFalse);
  });

  test('Pix sem código não parece pagamento concluído', () {
    final charge = LiveCharge.fromBody({
      'status': 'pending',
      'billing_type': 'PIX',
      'qr_code': '',
      'qr_code_base64': null,
    });

    expect(charge.rejectionMessage, livePixMissing);
    final view = ShareChargeView.fromResult(
      PayShareFailure(
        PayShareFailureReason.unavailable,
        message: charge.rejectionMessage,
      ),
    );
    expect(view.pixCode, isNull);
    expect(view.confirms, isFalse);
    expect(view.message, livePixMissing);
  });

  test('vaga paga só com pontos confirma sem QR', () {
    final charge = LiveCharge.fromBody({
      'status': 'paid',
      'billing_type': 'PIX',
      'qr_code': '',
      'points_only': true,
      'amount_cents': 0,
    });

    expect(charge.pointsOnly, isTrue);
    expect(charge.rejectionMessage, isNull);
    expect(charge.settlesPaid, isTrue);
    final view = ShareChargeView.fromResult(
      PayShareSuccess(_group(), charge: charge),
    );
    expect(view.confirms, isTrue);
    expect(view.hasError, isFalse);
    expect(view.pixCode, isNull);
  });

  test('cartão autorizado reserva e cartão pago confirma', () {
    final reserved = ShareChargeView.fromResult(
      PayShareSuccess(
        _group(),
        charge: LiveCharge.fromBody({
          'status': 'authorized',
          'billing_type': 'CREDIT_CARD',
        }),
      ),
    );
    expect(reserved.outcome, PaySheetOutcome.reserved);
    expect(reserved.pixCode, isNull);

    final paid = ShareChargeView.fromResult(
      PayShareSuccess(
        _group(),
        charge: LiveCharge.fromBody({
          'status': 'PAID',
          'billing_type': 'CREDIT_CARD',
        }),
      ),
    );
    expect(paid.outcome, PaySheetOutcome.paid);
    expect(paid.confirms, isTrue);
  });

  test('a demonstração sem cobrança continua reservando', () {
    final view = ShareChargeView.fromResult(PayShareSuccess(_group()));
    expect(view.outcome, PaySheetOutcome.reserved);
    expect(view.pixCode, isNull);
    expect(view.hasError, isFalse);
  });

  test('erros de create-charge viram texto e segredo não volta', () {
    expect(
      liveChargeErrorMessage({'error': 'A casa ainda não tem subconta Asaas.'}),
      'A casa ainda não tem subconta Asaas.',
    );
    expect(
      liveChargeErrorMessage('{"error":"card_declined"}'),
      liveCardDeclined,
    );
    expect(
      liveChargeErrorMessage({'error': 'asaas_unavailable'}),
      contains('Asaas'),
    );
    expect(
      liveChargeErrorMessage({'error': 'aact_nao_mostrar'}),
      liveChargeFailed,
    );
    expect(
      liveChargeErrorMessage({'error': 'Bearer segredo'}),
      liveChargeFailed,
    );
    expect(decodePixQrImage('aW1n'), isNull);
    expect(decodePixQrImage(''), isNull);
    expect(
      decodePixQrImage(
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ\nAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
      isNotNull,
    );
  });
}

Group _group() {
  return Group(
    id: 'group-1',
    cityId: 'city',
    cityName: 'Cidade',
    houseId: 'house',
    houseName: 'Casa',
    neighborhood: 'Centro',
    roomId: 'room',
    roomName: 'Sala',
    roomTheme: 'Tema',
    roomCapacity: 6,
    durationMinutes: 60,
    difficulty: Difficulty.medium,
    slotId: 'slot',
    startsAt: DateTime.utc(2026, 11, 8, 18),
    filledSpots: 2,
    totalSpots: 6,
    participants: const [],
    priceCents: 9000,
  );
}
