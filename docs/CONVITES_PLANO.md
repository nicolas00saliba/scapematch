# Plano dos convites

O que o link do grupo já faz, e o que ainda não existe em produção.

## Já está no código

- O link é `/convite/:groupId`. Na web a URL não usa `#`. O deploy do GitHub Pages copia `index.html` para `404.html`, então um caminho que o servidor não conhece ainda abre o app.
- Sem sessão, a tela mostra o grupo inteiro e não deixa editar, sair nem excluir.
- Participar sem sessão grava `pending_group_id` e abre Entrar. Fazer cadastro abre o cadastro de exemplo. Na abertura o app lê essa chave de novo, então um reload no meio do caminho não apaga a intenção.
- `AuthRepository` entra e cria conta na memória. Depois disso a intenção é consumida e a pessoa entra com as regras de vaga que já existem. Se lotou, a mensagem deixa isso claro e a intenção é apagada.
- Convidar monta o texto com sala, casa, cidade, horário, vagas e o link. Dá para copiar o link, abrir o WhatsApp e pedir a folha do sistema. O cartão visual aparece na folha. Enviar o cartão como imagem ainda não acontece.

## O que falta

1. **Supabase Auth** no lugar do `FakeAuthRepository`. Sair já existe e zera a sessão de exemplo. A conta de verdade substitui Nícolas.
2. **Preview no WhatsApp (Open Graph).** O link hoje abre o app Flutter. O WhatsApp lê o HTML do servidor, que é a casca do app, sem o nome da sala. Um preview com foto e título precisa de uma página gerada no servidor para cada convite, ou de uma função que responde o HTML antes do app carregar.
3. **Expiração e revogação.** O link vale enquanto o grupo existe. Ainda não dá para o criador invalidar um convite, nem para o link morrer sozinho.
4. **Antiabuso.** Não há limite de convite, nem proteção contra muita gente entrando ao mesmo tempo além da regra de vaga que o repositório já aplica. Produção precisa de limite, e da entrada feita no banco numa transação só.
5. **Imagem do cartão.** O desenho está na folha. Compartilhar o arquivo (e o preview) fica para quando o servidor ou o aparelho puder gerar essa imagem com segurança.
