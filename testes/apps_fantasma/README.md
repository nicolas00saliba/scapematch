# Apps fantasma

Um app Android por conta de teste: **EM Jogador 1, 2, 3** (azul) e
**EM Casa 1, 2** (laranja). Cada um é uma casca WebView do app real
(`app.escapematch.com.br` ou `parceiro.escapematch.com.br`) com
`applicationId` próprio (`br.com.escapematch.teste.<slug>`). O Android guarda
sessão, cookies e localStorage de cada app separados, então dá para ficar
logado em cinco contas ao mesmo tempo no mesmo celular. Um selo
"TESTE · JOGADOR 1" fica no topo da tela.

Por que não PWA: várias PWAs do mesmo domínio dividem o mesmo
armazenamento no Chrome, então a sessão de uma derruba a outra.

## Gerar os APKs

```bash
bash testes/apps_fantasma/build.sh            # sai em testes/apps_fantasma/apks/
```

Precisa de JDK 17, Android SDK (platform 36), Gradle 9.4 e Pillow.
A keystore de teste e a senha dela ficam em `~/.secrets/` (chmod 600), fora
do repo. Use sempre a mesma keystore para o celular aceitar atualização.

Para mais contas, acrescente linhas em `contas.json` e rode de novo.

## Contas

`testes/contas_fantasma/criar_contas.py` cria os usuários no Auth, marca
`profiles.is_test` e aceita os termos. Sem `--executar --confirmo-producao`
só mostra o plano. Depende da migration `20261124190000_test_accounts.sql`.

A casa é cadastrada dentro do app "EM Casa N" e já nasce `is_test`.
Casa de teste aprovada só aparece para contas de teste e para o admin (aal2).
