/// [AuthRepository.signUp] devolve isto quando a conta nasceu e o
/// Supabase ainda espera o clique no e-mail. Não é mensagem de erro:
/// a tela de cadastro troca para o sucesso.
const signupAwaitingEmailConfirmation = 'signup-awaiting-email-confirmation';

/// Pausa entre o e-mail que acabou de sair e o próximo reenvio.
const signupResendCooldown = Duration(seconds: 60);

/// Frase única do reenvio. Não diz se o endereço tem conta.
const signupResendNeutralMessage =
    'Se houver um cadastro pendente para este e-mail, enviamos um novo link.';
