/// Origens públicas do ScapeMatch na web.
///
/// O Pages aceita um domínio customizado por repositório, então cada app
/// mora num subdomínio próprio. O GitHub Pages antigo
/// (`nicolas00saliba.github.io/scapematch/…`) permanece válido na transição.
library;

/// Jogador real.
const playerAppOrigin = 'https://app.scapematch.com.br';

/// Parceiro real.
const partnerAppOrigin = 'https://parceiro.scapematch.com.br';

/// Demonstrações (jogador em `/`, Parceiro em `/parceiro/`).
const demoAppOrigin = 'https://demo.scapematch.com.br';

/// Landing institucional.
const landingOrigin = 'https://scapematch.com.br';

/// Host do GitHub Pages do monorepo (ainda servido na transição).
const legacyPagesHost = 'nicolas00saliba.github.io';

/// Caminho do jogador real no Pages antigo.
const legacyPlayerPath = '/scapematch/';

/// Caminho do Parceiro real no Pages antigo.
const legacyPartnerPath = '/scapematch/parceiro/';
