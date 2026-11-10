/// Origens públicas do EscapeMatch na web.
///
/// O Pages aceita um domínio customizado por repositório, então cada app
/// mora num subdomínio próprio. O GitHub Pages antigo
/// (`nicolas00saliba.github.io/scapematch/…`) permanece válido na transição.
library;

/// Jogador real.
const playerAppOrigin = 'https://app.escapematch.com.br';

/// Parceiro real.
const partnerAppOrigin = 'https://parceiro.escapematch.com.br';

/// Admin real. Não há link a partir dos outros apps.
const adminAppOrigin = 'https://admin.scapematch.com.br';

/// Demonstração do jogador. O caminho `/parceiro/` neste host só redireciona.
const demoAppOrigin = 'https://demo.escapematch.com.br';

/// Demonstração do Parceiro. Host próprio: o escopo não cabe dentro
/// do PWA do jogador em [demoAppOrigin].
const partnerDemoOrigin = 'https://parceiro-demo.escapematch.com.br';

/// Landing institucional.
const landingOrigin = 'https://escapematch.com.br';

/// Host do GitHub Pages do monorepo (ainda servido na transição).
const legacyPagesHost = 'nicolas00saliba.github.io';

/// Caminho do jogador real no Pages antigo.
const legacyPlayerPath = '/scapematch/';

/// Caminho do Parceiro real no Pages antigo.
const legacyPartnerPath = '/scapematch/parceiro/';

/// Caminho do Admin no Pages antigo, até existir o host próprio.
const legacyAdminPath = '/scapematch/admin/';
