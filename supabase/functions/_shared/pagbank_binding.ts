/// Uma conta PagBank por casa. A troca é desconectar e conectar de novo.
/// O repasse confere a ligação entre a conta da casa e o token guardado e,
/// se achar ambiguidade, para e alerta. Não escolhe conta.

/// Quem pode desconectar. true: dono (com confirmação na tela) e Admin.
/// false: só o Admin. A função pagbank-disconnect lê esta constante.
export const ownerMayDisconnect = true;

export const accountExistsMessage =
  "Esta casa já tem uma conta PagBank conectada. Para trocar, desconecte a atual e conecte de novo.";

export const inFlightMessage =
  "Há dinheiro a caminho para a conta atual. Espere cair e tente trocar de novo.";

export type ConflictCode =
  | "pagbank_account_exists"
  | "pagbank_account_mismatch"
  | "pagbank_in_flight";

const conflictCodes: ConflictCode[] = [
  "pagbank_account_exists",
  "pagbank_account_mismatch",
  "pagbank_in_flight",
];

export class PagbankAccountConflict extends Error {
  readonly code: ConflictCode;

  constructor(code: ConflictCode) {
    super(code);
    this.name = "PagbankAccountConflict";
    this.code = code;
  }

  get message409(): string {
    return this.code === "pagbank_in_flight"
      ? inFlightMessage
      : accountExistsMessage;
  }
}

/// O Postgres devolve o SQLSTATE PB409 com o código na mensagem.
export function conflictFromRpc(
  error: { code?: string; message?: string } | null | undefined,
): PagbankAccountConflict | null {
  if (!error) return null;
  const message = error.message ?? "";
  for (const code of conflictCodes) {
    if (message.includes(code)) return new PagbankAccountConflict(code);
  }
  if (error.code === "PB409") {
    return new PagbankAccountConflict("pagbank_account_exists");
  }
  return null;
}

export function conflictBody(conflict: PagbankAccountConflict): {
  error: ConflictCode;
  message: string;
} {
  return { error: conflict.code, message: conflict.message409 };
}

export type BindingState = "none" | "ok" | "unverified" | "ambiguous" | "unreadable";

export type Binding = { state: BindingState; reason: string };

/// Lê o jsonb de public.venue_pagbank_binding. Resposta que não dá para ler
/// conta como ilegível: o repasse para, não adivinha.
export function parseBinding(raw: unknown): Binding {
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value || typeof value !== "object") {
    return { state: "unreadable", reason: "unreadable" };
  }
  const row = value as { state?: unknown; reason?: unknown };
  const state = row.state;
  const reason = typeof row.reason === "string" ? row.reason : "";
  if (
    state === "none" || state === "ok" || state === "unverified" ||
    state === "ambiguous"
  ) {
    return { state, reason };
  }
  return { state: "unreadable", reason: "unreadable" };
}

/// Só estes estados deixam o dinheiro andar. none e unverified passam porque
/// não há divergência provada: sem conta, os outros bloqueios já valem; token
/// antigo ainda sem conta gravada segue até a próxima conexão gravar.
export function bindingBlocksMoney(binding: Binding): boolean {
  return binding.state === "ambiguous" || binding.state === "unreadable";
}

/// Código para o alerta operacional (a-z, 0-9, _).
export function bindingAlertCode(binding: Binding): string {
  if (binding.state === "unreadable") return "conta_ilegivel";
  return binding.reason === "tokens_without_account"
    ? "token_sem_conta"
    : "conta_ambigua";
}
