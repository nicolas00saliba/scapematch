import 'package:scapematch/core/data/sample_ids.dart';

/// Casa que entra no Parceiro desta versão. A senha não sai daqui.
class PartnerAccount {
  const PartnerAccount({
    required this.email,
    required this.houseId,
    required this.houseName,
    this.isAdmin = false,
  });

  final String email;
  final String houseId;
  final String houseName;
  final bool isAdmin;
}

const partnerDemoPassword = 'demo';

/// Atalho da mesma casa de exemplo. Não é uma conta separada.
const partnerQuickUser = 'a';
const partnerQuickPassword = 'b';

const partnerDemoAccount = PartnerAccount(
  email: 'xv@scapematch.exemplo',
  houseId: SampleIds.houseCwbRuaXv,
  houseName: 'Mistério da Rua XV',
);

const partnerAdminAccount = PartnerAccount(
  email: 'admin@scapematch.exemplo',
  houseId: 'admin',
  houseName: 'Admin',
  isAdmin: true,
);

PartnerAccount? matchPartnerLogin(String email, String password) {
  final id = email.trim().toLowerCase();
  final quick = id == partnerQuickUser && password == partnerQuickPassword;
  final full =
      id == partnerDemoAccount.email && password == partnerDemoPassword;
  if (quick || full) {
    return partnerDemoAccount;
  }
  if (id == partnerAdminAccount.email && password == partnerDemoPassword) {
    return partnerAdminAccount;
  }
  return null;
}
