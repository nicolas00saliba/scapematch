import 'package:scapematch/core/data/sample_ids.dart';

/// Casa que entra no Parceiro desta versão. A senha não sai daqui.
class PartnerAccount {
  const PartnerAccount({
    required this.email,
    required this.houseId,
    required this.houseName,
  });

  final String email;
  final String houseId;
  final String houseName;
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

PartnerAccount? matchPartnerLogin(String email, String password) {
  final id = email.trim().toLowerCase();
  final quick = id == partnerQuickUser && password == partnerQuickPassword;
  final full =
      id == partnerDemoAccount.email && password == partnerDemoPassword;
  if (quick || full) {
    return partnerDemoAccount;
  }
  return null;
}
