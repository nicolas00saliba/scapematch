# ScapeMatch

App para juntar pessoas em grupos de experiências presenciais, começando por escape rooms. A dor é simples: querer jogar e não ter gente suficiente.

Esta é a primeira versão. Ela roda em Android, iOS e web, mas **não tem backend**. Cidades, casas, salas, horários, grupos e participantes são fictícios e ficam só na memória do app. A interface deixa isso explícito com o aviso “Dados de exemplo”.

O código está em inglês. Os textos da tela estão em português do Brasil.

## Como rodar

É preciso o [Flutter](https://docs.flutter.dev/get-started/install) stable (esta versão foi criada com Flutter 3.47 / Dart 3.13).

```bash
flutter pub get
flutter run -d chrome
```

Com um aparelho ou emulador conectado:

```bash
flutter run
```

Verificação:

```bash
flutter analyze
flutter test
flutter build web
```

O build web gera a pasta `build/web`. Para olhar no navegador:

```bash
cd build/web && python3 -m http.server 8080
```

## O que dá para fazer agora

1. O app abre na **Home**. A barra de baixo é **Home**, **Meus grupos** e **Conta**. Sem cidade salva, Curitiba já entra selecionada. Uma escolha salva prevalece e fica no aparelho (`shared_preferences`). A cidade é o filtro dos grupos, das salas e das notícias. O seletor continua na tela para trocar.
2. **Topo curto:** cidade e tipo de jogo lado a lado, aviso de exemplo num chip pequeno, busca com o hint inteiro (em tela estreita, **Criar grupo** fica só o +) e o filtro **Quase cheios**. Os grupos ficam numa janela com rolagem, e a lista segue a busca, o filtro, a cidade e o tipo de jogo.
3. Abaixo dos grupos, a ordem é **Promoções**, **Novidades** e **Salas**. Cada carrossel tem setas que andam um quadro inteiro e param com o cartão alinhado, no toque e no arrasto. No celular cabe um quadro; na coluna larga, dois. Novidades tem **Ver tudo**.
4. **Salas** é um carrossel só, filtrado pela cidade e pelo tipo de jogo. O cartão tem foto, sala, casa, cidade e os botões **Achar grupo** e **Criar grupo**. Achar grupo abre os grupos daquela sala. Criar grupo abre o formulário com a sala já escolhida.
5. **Conta**, na aba da direita: “Olá, Nícolas”, a carteira fictícia com **Adicionar saldo**, e os atalhos Perfil, Meus parceiros de jogo, Indique e ganhe, Cartões cadastrados e Ajuda, mais a engrenagem de configurações. Adicionar saldo e Adicionar cartão ainda não cobram nem pedem número de cartão. As telas dizem que o dado é de exemplo.
6. Abrir um grupo e tocar em **Entrar no grupo**. A vaga muda na hora, só nesta sessão. Grupo cheio não aceita mais ninguém. Não entra quem já está em outro grupo no mesmo horário, nem em sessão que já começou.
7. **Criar grupo**: cidade, casa, sala, horário e quantas vagas você procura além de você. Você + vagas não podem passar da capacidade da sala. O tamanho do grupo é independente da lotação máxima da sala. O horário é uma das opções da sala, não uma data livre. Não nascem dois grupos na mesma sala no mesmo horário. Um horário que já passou é recusado. Pelo cartão da sala, a casa e a sala já vêm preenchidas.
8. **Confirmar presença** na lista de quem já está. O criador confirma a própria. O detalhe mostra quantas presenças estão confirmadas.
9. **Sair do grupo**, se você não é o criador. Com 2 horas ou mais de antecedência o pagamento simulado é reembolsado. Com menos de 2 horas, a tela avisa antes de confirmar que não há reembolso. A vaga volta a ficar livre. Exatamente 2 horas ainda reembolsa. Sair é definitivo naquele grupo.
10. **Excluir grupo**, só para quem criou. Isso cancela o evento para todo mundo e reembolsa integralmente, mesmo em cima da hora. Quem não criou não vê o botão. O criador não sai: ele exclui.
11. **Editar** o tamanho desejado e uma observação, dentro de quem já entrou e da capacidade da sala. Dá para remover outra pessoa, com reembolso integral, e copiar o link do grupo.
12. **Meus grupos**, na aba do meio, com as abas Próximos, Passados e Cancelados. Mostra presença, pagamento simulado e reembolso. O preço por pessoa é fictício. Nada é cobrado.

A aba Conta existe, mas ainda não há login. A pessoa que usa o app é um usuário fictício (`currentUserProvider`), e o nome de exemplo é “Nícolas”. O repositório não tem esse nome escrito: ele recebe quem o provider entregar, para o login substituir o provider depois. A carteira lê `WalletRepository` (saldo de exemplo) e os cartões leem `PaymentMethodsRepository` (lista vazia). O plano do pagamento real está em [docs/PAGAMENTOS_PLANO.md](docs/PAGAMENTOS_PLANO.md).

## Estrutura de pastas

```text
lib/
  main.dart                 # sobe o app
  app/                      # tema, rotas, retry do Riverpod
  core/                     # peças usadas por mais de uma feature
    data/                   # banco fictício em memória
    ui/                     # banner, estados vazio/erro/carregando
  features/
    cities/                 # cidade escolhida e o seletor
    catalog/                # casas, salas e horários
    groups/                 # achar, ver, criar e acompanhar grupo
    news/                   # feed de novidades, hoje fictício
    home/
  providers/                # liga as interfaces aos dados fictícios
test/                       # regras, repositório e fluxos de tela
docs/ARQUITETURA.md         # explicação curta das camadas
docs/DECISOES.md            # decisões provisórias do produto
docs/CONVITES_PLANO.md      # o que o link de convite ainda não faz
docs/DADOS_REAIS.md         # como uma casa entra sem coleta escondida
docs/SUPABASE_ESQUEMA.md    # rascunho de tabelas, RLS e join atômico
```

Cada feature segue o mesmo desenho:

- `domain/` — modelos e regras, sem Flutter
- `data/` — interface do repositório e, hoje, a implementação fictícia
- `presentation/` — tela e view model

## Decisões de arquitetura

- **Flutter + Riverpod + go_router.** Sem Firebase e sem Supabase nesta fase.
- **MVVM leve.** A tela observa um view model. O view model chama um repositório. A tela não conhece a lista fictícia.
- **Regras puras** em `GroupRules`: não entrar em grupo cheio, o que é “quase cheio”, o limite de vagas, a janela de reembolso de 2 horas, a sobreposição de horários e o grupo que já começou. O relógio entra por um `Clock`. Dá para testar sem subir a interface.
- **Um `Group` já vem com os nomes da casa e da sala.** A tela não junta tabelas. Quando o repositório for o Supabase, ele faz essa junção e devolve o mesmo objeto.
- As mudanças de “entrar” e “criar” duram enquanto o app está aberto. Fechar o app volta aos dados de exemplo.

O mapa completo, com o caminho de uma tela, está em [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## O que é fictício

Tudo que aparece sobre casas e grupos. Os nomes (Escape Augusta, O Cofre do Café, e os outros) foram inventados. Não vêm de site de casa nenhuma. Os preços também são fictícios. O pagamento marcado como pago, e o reembolso, não movimentam dinheiro.

As cidades de exemplo são Curitiba, São Paulo, Rio de Janeiro, Belo Horizonte e Porto Alegre, cada uma com casas e salas diferentes. Cada cidade começa com dois grupos: um quase cheio (falta 1 ou 2 vagas) que começa daqui a cerca de 90 minutos, e outro com mais vagas abertas que começa daqui a 3 dias. O de 90 minutos serve para testar a saída sem reembolso. O de 3 dias serve para testar a saída com reembolso. Em Curitiba, o de 90 minutos é O Cofre do Café e o de 3 dias é Enigma no Ópera. Os dois não se sobrepõem e ficam em salas diferentes. O resto dos horários futuros fica livre.

A tela de criar grupo não abre um calendário. Ela lista os horários cadastrados da sala, calculados a partir do relógio do app. Cada sala tem pelo menos quatro horários futuros e um horário que já passou.

As notícias também são inventadas. Curitiba tem dez. As outras cidades de exemplo têm algumas. As figuras em `assets/images/news/` são ilustrações fictícias, não fotos de casas, em JPEG de cerca de 800 px. A grade de sexta não tem figura e o app desenha um degradê. O combo de café usa um degradê com xícara, não a foto da biblioteca. Os links usam o domínio `.invalid` e a tela não abre o navegador. Um link direto de notícia, sem pilha, mostra voltar para a Home.

As salas dos carrosséis usam essas mesmas figuras, por tema. Aventura tem um arquivo novo em `assets/images/rooms/aventura.jpg`, também fictício e abaixo de 150 KB. Cada tema que aparece numa cidade tem pelo menos duas salas, para o carrossel rolar. Várias dessas salas não têm grupo marcado.

## Próximos passos

1. **Supabase / PostgreSQL** por trás das mesmas interfaces (`CityRepository`, `CatalogRepository`, `GroupRepository`), sem reescrever as telas. Entrar no grupo tem de ser a função atômica descrita em [docs/SUPABASE_ESQUEMA.md](docs/SUPABASE_ESQUEMA.md).
2. Conta de usuário no lugar de `currentUserProvider`. O nome “Nícolas” sai quando o provider passar a ler a sessão. A carteira e os cartões passam a ser de verdade pelo caminho em [docs/PAGAMENTOS_PLANO.md](docs/PAGAMENTOS_PLANO.md).
3. Trocar o catálogo fictício por salas e agendas que cada casa entregar (arquivo, API ou parceria). O encaixe é o `ExperienceSource`. O feed troca o `NewsRepository` pelo mesmo tipo de cuidado: site só com permissão, Instagram pela API oficial ou curadoria manual, cache e atribuição da fonte. O que pode e o que não pode ser coletado está em [docs/DADOS_REAIS.md](docs/DADOS_REAIS.md).
4. Publicar nas lojas quando o fluxo estiver estável com dados reais.

O CI (`.github/workflows/ci.yml`) roda `flutter pub get`, `flutter analyze`, `flutter test` e `flutter build web` com o Flutter 3.47.8, que é o stable que traz o Dart 3.13.7 pedido no `pubspec.yaml`.
