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

1. Na home, escolher uma cidade. O app não assume Curitiba: a cidade começa vazia e é o filtro principal, no mesmo espírito do campo de origem de um app de passagem.
2. **Encontrar grupo**: lista os grupos da cidade, com o filtro **Quase cheios** (ainda dá para entrar e faltam 1 ou 2 vagas).
3. Abrir um grupo e tocar em **Entrar no grupo**. A vaga muda na hora, só nesta sessão. Grupo cheio não aceita mais ninguém.
4. **Criar grupo**: cidade, casa, sala, horário e quantas vagas você procura além de você. Você + vagas não podem passar da capacidade da sala. O tamanho do grupo é independente da lotação máxima da sala. Não nascem dois grupos na mesma sala no mesmo horário.

Não existe conta. A pessoa que usa o app é um usuário fictício (`currentUserProvider`), e o nome de exemplo continua “Você”. O repositório não tem esse nome escrito: ele recebe quem o provider entregar, para o login substituir o provider depois.

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
    groups/                 # achar, ver e criar grupo
    home/
  providers/                # liga as interfaces aos dados fictícios
test/                       # regras, repositório e fluxos de tela
docs/ARQUITETURA.md         # explicação curta das camadas
docs/DECISOES.md            # decisões provisórias do produto
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
- **Regras puras** em `GroupRules`: não entrar em grupo cheio, o que é “quase cheio”, e o limite de vagas na criação. Dá para testar sem subir a interface.
- **Um `Group` já vem com os nomes da casa e da sala.** A tela não junta tabelas. Quando o repositório for o Supabase, ele faz essa junção e devolve o mesmo objeto.
- As mudanças de “entrar” e “criar” duram enquanto o app está aberto. Fechar o app volta aos dados de exemplo.

O mapa completo, com o caminho de uma tela, está em [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## O que é fictício

Tudo que aparece sobre casas e grupos. Os nomes (Escape Augusta, O Cofre do Café, e os outros) foram inventados. Não vêm de site de casa nenhuma. As datas de exemplo estão em novembro de 2026 para a demonstração não depender do dia de hoje.

As cidades de exemplo são Curitiba, São Paulo, Rio de Janeiro, Belo Horizonte e Porto Alegre, cada uma com casas, salas e grupos diferentes.

## Próximos passos

1. **Supabase / PostgreSQL** por trás das mesmas interfaces (`CityRepository`, `CatalogRepository`, `GroupRepository`), sem reescrever as telas. Entrar no grupo tem de ser a função atômica descrita em [docs/SUPABASE_ESQUEMA.md](docs/SUPABASE_ESQUEMA.md).
2. Conta de usuário no lugar de `currentUserProvider`. O nome “Você” sai quando o provider passar a ler a sessão.
3. Trocar o catálogo fictício por salas e agendas que cada casa entregar (arquivo, API ou parceria). O encaixe é o `ExperienceSource`. O que pode e o que não pode ser coletado está em [docs/DADOS_REAIS.md](docs/DADOS_REAIS.md).
4. Publicar nas lojas quando o fluxo estiver estável com dados reais.

O CI (`.github/workflows/ci.yml`) roda `flutter pub get`, `flutter analyze`, `flutter test` e `flutter build web` com o Flutter 3.47.8, que é o stable que traz o Dart 3.13.7 pedido no `pubspec.yaml`.
