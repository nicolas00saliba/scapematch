import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/mode/app_mode.dart';

/// Casa que entrou no Parceiro.
class PartnerAccount {
  const PartnerAccount({
    required this.email,
    required this.houseId,
    required this.houseName,
    this.userId = '',
    this.venueStatus = 'approved',
    this.isAdmin = false,
  });

  final String email;
  final String houseId;
  final String houseName;
  final String userId;

  /// `loading`, nulo (sem casa), `pending`, `approved` ou `rejected`.
  final String? venueStatus;
  final bool isAdmin;

  bool get hasApprovedHouse => houseId.isNotEmpty && venueStatus == 'approved';
}

const partnerDemoPassword = 'demo';

/// Atalho da mesma casa de exemplo. Não entra no build de produção.
const partnerQuickUser = 'a';
const partnerQuickPassword = 'b';

const partnerDemoAccount = PartnerAccount(
  email: 'xv@scapematch.exemplo',
  houseId: SampleIds.houseCwbRuaXv,
  houseName: 'Mistério da Rua XV',
);

/// Senhas fixas só existem fora do release. O compilador de produção corta o resto.
const partnerAdminAccount = PartnerAccount(
  email: 'admin@scapematch.exemplo',
  houseId: 'admin',
  houseName: 'Admin',
  isAdmin: true,
);

PartnerAccount? matchPartnerLogin(String email, String password) {
  if (!kAllowSampleLogin) return null;
  final id = email.trim().toLowerCase();
  final quick = id == partnerQuickUser && password == partnerQuickPassword;
  final full =
      id == partnerDemoAccount.email && password == partnerDemoPassword;
  if (quick || full) return partnerDemoAccount;
  if (id == partnerAdminAccount.email && password == partnerDemoPassword) {
    return partnerAdminAccount;
  }
  return null;
}

String partnerDemoEmailHint() {
  if (!kAllowSampleLogin) return '';
  return 'Casa de exemplo: xv@scapematch.exemplo. Senha: demo.';
}

String partnerDemoQuickLabel() {
  if (!kAllowSampleLogin) return '';
  return 'Demo: a / b';
}
