# Dados reais das casas

O app ainda mostra só dados inventados. Este texto diz como uma casa de escape entra de verdade, sem começar a copiar site nenhum agora.

## O que existe hoje

Cada casa, no futuro, é uma implementação de `ExperienceSource` (`lib/features/catalog/domain/experience_source.dart`). A interface devolve salas e sessões daquela casa. A sessão carrega um tipo de disponibilidade:

| Valor no código | Nome no produto | O que significa |
| --- | --- | --- |
| `integrated` | Horário integrado | A casa publicou aquele início. |
| `partnerGrid` | Grade do parceiro | Um parceiro mandou a grade de horários. |
| `proposed` | Horário proposto | Alguém sugeriu um horário. A casa não confirmou. |
| `toBeArranged` | A combinar | Não há horário fechado. `startsAt` fica vazio. |

As telas de grupo não leem essa interface ainda. Elas continuam no catálogo fictício. O ponto de encaixe é `exampleExperienceSourceProvider`: troca-se a fonte, não a tela.

## O adaptador de exemplo

`AssetExperienceSource` lê `assets/experience/example_house.json`. O arquivo é fictício. O nome da casa é Casa Exemplo. O campo `origin` é `local-json`, para ficar claro que não veio de um site.

O fluxo do adaptador é o mesmo que uma integração permitida usaria:

1. Obter o texto (hoje, um asset; amanhã, um arquivo que a casa enviou ou uma resposta de API combinada).
2. `JsonExperienceSource` valida o JSON e devolve `ExperienceOffering`.
3. Um repositório de catálogo, quando for a hora, transforma isso em `EscapeRoom` e `TimeSlot` para as telas que já existem.

Não há cliente HTTP, fila de coleta, nem URL de casa nenhuma neste repositório.

## Como uma integração entra depois

Uma casa nova ganha uma classe que implementa `ExperienceSource`, construída com o id daquela casa. Exemplos do que essa classe pode ser, quando o dono autorizar o caminho:

- um cliente da API que a casa ou um parceiro entregar;
- um leitor de arquivo (JSON, CSV, planilha) que a casa manda;
- um coletor, só se a seção abaixo disser que a coleta é permitida.

O registro é um mapa `houseId → ExperienceSource`. O `CatalogRepository` pergunta a esse mapa em vez de ler só o `FakeDatabase`. Grupo, cidade e tela ficam como estão. Sessão “a combinar” não vira um horário confirmado: a tela de criar grupo só oferece um horário quando ele existe.

O catálogo e os grupos continuam separados de propósito. A casa preenche salas e horários. As pessoas preenchem os grupos.

## Ética

- Pedir antes. O caminho preferido é a casa (ou um parceiro dela) entregar os dados, por API ou arquivo.
- Levar só o que serve para marcar o jogo: nome da casa, bairro, sala, duração, capacidade, dificuldade e horários públicos. Não levar cadastro de clientes da casa, avaliações com nome de pessoa, nem qualquer dado que não esteja público para quem vai jogar.
- Não contornar login, paywall, captcha ou bloqueio técnico. Se o site exige conta para ver a agenda, isso não é dado público.
- Identificar o cliente quando houver rede de verdade (um User-Agent com nome do app e um contato). Não se passar pelo navegador de uma pessoa.
- Guardar de onde veio cada sessão (`origin`) e quando foi lida, para alguém poder conferir e para a casa poder pedir a retirada.
- Se a casa pedir para sair, parar e apagar o que era dela.
- O JSON de exemplo não deve ser substituído por uma página copiada. Página copiada não entra neste repositório.

## Termos de uso

Antes de qualquer coleta automática, ler os termos do site e o `robots.txt`.

- Se os termos autorizam o uso dos dados de agenda, ou existe um contrato com a casa, a integração pode seguir, dentro do que o texto permitir (atribuição, frequência, o que pode ser reexibido).
- Se os termos proíbem acesso automatizado, scraping, ou o reuso da agenda, não coletar. A alternativa é pedir uma parceria, uma API ou um arquivo.
- Texto de marketing, fotos e descrição longa da sala não são “o horário”. Reexibir isso pede permissão mesmo quando o horário em si for público.
- Na dúvida, não coletar. Um buraco na grade é melhor do que um dado que a casa não autorizou.

## Quando o site não permite coleta

Não implementar um coletor “só desta vez”. O app mostra a casa sem a grade automática, ou só com o que ela mandar por um canal permitido (arquivo, API, cadastro manual). O tipo `proposed` e o tipo `toBeArranged` existem para o grupo existir antes de a casa confirmar o horário. Eles não são desculpa para ir buscar o horário num site que proibiu a coleta.

Sinais de que a coleta está fora:

- `robots.txt` barra o caminho da agenda para o user-agent do app;
- os termos vetam scraping, cópia da programação ou uso comercial do conteúdo;
- a página só abre logada, com captcha, ou responde com bloqueio;
- a casa já disse que não quer.

Nesses casos a fonte daquela casa não é criada. O restante do catálogo segue.

## Cache

O exemplo em asset não precisa de cache: o arquivo já está no app.

Quando uma fonte passar a usar rede:

- guardar a resposta por casa, com o horário em que foi lida;
- respeitar `Cache-Control` quando a resposta for HTTP;
- sem esse cabeçalho, usar um prazo curto e explícito (algumas horas para uma agenda que muda no dia), e não bater no servidor a cada abertura de tela;
- não atender a pessoa com dado mais velho do que o prazo sem marcar que está desatualizado;
- não guardar “a combinar” como se fosse horário confirmado;
- uma atualização empurrada pela casa (API ou arquivo novo) invalida o cache daquela casa na hora;
- o cache é da agenda pública, não de dado pessoal.

Nada disso está implementado. Não há cliente HTTP no projeto.
