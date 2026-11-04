import 'package:scapematch/features/social/domain/social_models.dart';

/// Ids estáveis das pessoas de exemplo que também sentam em grupos.
///
/// O nome no grupo aponta para a conta. Sem esta linha, o cartão não
/// sabe que a pessoa é amiga de quem está olhando.
const samplePlayerUserIds = <String, String>{
  // Marina fica sem id no grupo do cofre: o teste de bloqueio usa a cadeira
  // p0 daquele cartão. Caio, no mesmo grupo, ainda acende o selo de amigo.
  'Caio': 'user-caio',
  'Helena': 'user-helena',
  'Vera': 'user-vera',
  'Lia': 'user-lia',
  'Rafa': 'user-rafa',
};

const sampleLocalUserId = 'user-local';

/// Luna e Enzo não sentam em grupo nenhum. A turma de exemplo entra com
/// eles sem esbarrar no horário de outra sessão.
const sampleCrewMateLuna = 'user-luna';
const sampleCrewMateEnzo = 'user-enzo';
const sampleCrewId = 'crew-sabado';

const sampleProfiles = <PublicProfile>[
  PublicProfile(
    id: sampleLocalUserId,
    displayName: 'Nícolas',
    username: 'nicolas',
  ),
  PublicProfile(id: 'user-marina', displayName: 'Marina', username: 'marina'),
  PublicProfile(id: 'user-caio', displayName: 'Caio', username: 'caio'),
  PublicProfile(id: 'user-helena', displayName: 'Helena', username: 'helena'),
  PublicProfile(id: 'user-vera', displayName: 'Vera', username: 'vera'),
  PublicProfile(id: 'user-lia', displayName: 'Lia', username: 'lia'),
  PublicProfile(id: 'user-rafa', displayName: 'Rafa', username: 'rafa'),
  PublicProfile(id: sampleCrewMateLuna, displayName: 'Luna', username: 'luna'),
  PublicProfile(id: sampleCrewMateEnzo, displayName: 'Enzo', username: 'enzo'),
];
