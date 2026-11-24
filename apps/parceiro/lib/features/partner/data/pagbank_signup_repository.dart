import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PagbankSignupException implements Exception {
  const PagbankSignupException(this.code);

  final String code;
}

class PagbankSignupCreated {
  const PagbankSignupCreated({
    required this.accountStatus,
    this.accountId,
  });

  final String accountStatus;
  final String? accountId;
}

abstract class PagbankSignupRepository {
  Future<PagbankSignupView> load(String venueId);

  /// Modo A. Não recebe documento, endereço nem contato.
  Future<void> guide({
    required String venueId,
    required String documentKind,
    required String businessCategory,
  });

  Future<PagbankSignupCreated> create(String venueId, PagbankSignupDraft draft);

  Future<Uri> connect(String venueId);
}

class MemoryPagbankSignupRepository implements PagbankSignupRepository {
  MemoryPagbankSignupRepository({this.apiEnabled = false, this.signup});

  bool apiEnabled;
  PagbankSignupRow? signup;
  final List<String> guides = [];
  final List<PagbankSignupDraft> created = [];
  Uri connectUri = Uri.parse('https://connect.pagbank.com.br/oauth2/authorize');

  @override
  Future<PagbankSignupView> load(String venueId) async {
    return PagbankSignupView(apiEnabled: apiEnabled, signup: signup);
  }

  @override
  Future<void> guide({
    required String venueId,
    required String documentKind,
    required String businessCategory,
  }) async {
    if (apiEnabled) throw const PagbankSignupException('modo_api');
    guides.add('$venueId:$documentKind:$businessCategory');
    signup = PagbankSignupRow(
      mode: 'manual',
      documentKind: documentKind,
      businessCategory: businessCategory,
      accountStatus: 'guided',
    );
  }

  @override
  Future<PagbankSignupCreated> create(
    String venueId,
    PagbankSignupDraft draft,
  ) async {
    if (!apiEnabled) throw const PagbankSignupException('api_indisponivel');
    created.add(draft);
    return const PagbankSignupCreated(
      accountId: 'ACCO_F74B8490-77C0-4F9C-88EA-E98735B4CB36',
      accountStatus: 'pending_activation',
    );
  }

  @override
  Future<Uri> connect(String venueId) async => connectUri;
}

class SupabasePagbankSignupRepository implements PagbankSignupRepository {
  @override
  Future<PagbankSignupView> load(String venueId) async {
    try {
      final raw = await scapeSupabase.rpc(
        'pagbank_signup_for_venue',
        params: {'p_venue_id': venueId},
      );
      return PagbankSignupView.fromJson(raw);
    } on PostgrestException catch (error) {
      throw PagbankSignupException(signupErrorCode(error.message));
    }
  }

  @override
  Future<void> guide({
    required String venueId,
    required String documentKind,
    required String businessCategory,
  }) async {
    try {
      await scapeSupabase.rpc(
        'record_pagbank_signup_guide',
        params: {
          'p_venue_id': venueId,
          'p_document_kind': documentKind,
          'p_business_category': businessCategory,
        },
      );
    } on PostgrestException catch (error) {
      throw PagbankSignupException(signupErrorCode(error.message));
    }
  }

  @override
  Future<PagbankSignupCreated> create(
    String venueId,
    PagbankSignupDraft draft,
  ) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'pagbank-signup',
        body: draft.toCreateJson(venueId),
      );
      return _created(response.data);
    } on FunctionException catch (error) {
      throw PagbankSignupException(signupErrorCode('${error.details ?? ''}'));
    }
  }

  @override
  Future<Uri> connect(String venueId) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'provision-venue-wallet',
        body: {'venue_id': venueId},
      );
      final data = response.data;
      final url = data is Map ? data['connect_url'] : null;
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri != null && uri.scheme == 'https') return uri;
      throw const PagbankSignupException('connect');
    } on FunctionException catch (error) {
      throw PagbankSignupException(signupErrorCode('${error.details ?? ''}'));
    }
  }
}

PagbankSignupCreated _created(Object? data) {
  if (data is! Map) throw const PagbankSignupException('erro');
  final error = data['error']?.toString();
  if (error != null && error.isNotEmpty) {
    throw PagbankSignupException(signupErrorCode(error));
  }
  final account = data['account_id']?.toString();
  final status = data['account_status']?.toString() ?? '';
  if (status == 'pending_activation' && account != null && account.startsWith('ACCO_')) {
    return PagbankSignupCreated(accountId: account, accountStatus: status);
  }
  throw const PagbankSignupException('erro');
}

String signupErrorCode(String message) {
  for (final code in const [
    'api_indisponivel',
    'modo_api',
    'conta_existente',
    'conta_criada',
    'conta_email',
    'pagbank_resposta',
    'pagbank_unavailable',
    'pagbank_connect',
    'cpf_responsavel',
    'documento',
    'razao',
    'endereco',
    'responsavel',
    'nascimento',
    'celular',
    'email',
    'categoria',
    'termos',
    'ip',
    'not owner',
    'casa',
  ]) {
    if (message.contains(code)) return code;
  }
  return 'erro';
}

final pagbankSignupRepositoryProvider = Provider<PagbankSignupRepository>((ref) {
  if (ref.watch(backendPlanProvider).connectsSupabase) {
    return SupabasePagbankSignupRepository();
  }
  return MemoryPagbankSignupRepository();
});
