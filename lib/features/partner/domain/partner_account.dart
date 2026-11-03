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

const partnerDemoAccount = PartnerAccount(
  email: 'xv@scapematch.exemplo',
  houseId: SampleIds.houseCwbRuaXv,
  houseName: 'Mistério da Rua XV',
);

PartnerAccount? matchPartnerLogin(String email, String password) {
  if (email.trim().toLowerCase() != partnerDemoAccount.email) {
    return null;
  }
  if (password != partnerDemoPassword) {
    return null;
  }
  return partnerDemoAccount;
}
