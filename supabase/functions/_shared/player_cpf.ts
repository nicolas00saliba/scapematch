import { AsaasProvider, type CustomerInput } from "./asaas_provider.ts";

/// 11 dígitos com os dois verificadores. CPF repetido não vale.
export function playerCpfDigits(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/\D/g, "");
  if (!/^\d{11}$/.test(digits) || /^(\d)\1{10}$/.test(digits)) return null;
  const digit = (length: number) => {
    let sum = 0;
    for (let i = 0; i < length; i++) {
      sum += Number(digits[i]) * (length + 1 - i);
    }
    const mod = (sum * 10) % 11;
    return mod === 10 ? 0 : mod;
  };
  if (digit(9) !== Number(digits[9]) || digit(10) !== Number(digits[10])) {
    return null;
  }
  return digits;
}

export type PlayerCustomerInput = CustomerInput & {
  customerId: string | null;
  cpf: string;
};

/// Customer da conta Asaas atual. `replacedId` é o id que não existe mais
/// (404 ou `deleted`) e cujos cartões precisam ser desativados antes de
/// gravar o id novo.
export type ResolvedCustomer = {
  id: string;
  replacedId: string | null;
};

/// A cobrança com cartão salvo pede recadastro quando o customer foi trocado.
export const cardReregisterCode = "card_reregister";

type CustomerStore = {
  from(table: string): {
    update(values: Record<string, unknown>): {
      eq(
        column: string,
        value: string,
      ): PromiseLike<{ error: { message?: string } | null }>;
    };
  };
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string } | null }>;
};

function cpfOrThrow(value: string): string {
  const cpf = playerCpfDigits(value);
  if (!cpf) {
    const error = new Error("cpf_required");
    error.name = "CpfRequired";
    throw error;
  }
  return cpf;
}

/// 404 é customer de outra conta (sandbox ou chave antiga). Outro status sobe.
function customerMissing(error: unknown): boolean {
  return error instanceof Error && /^Asaas 404\b/.test(error.message);
}

/// Cria o customer com o CPF, preenche o documento vazio, ou recria quando
/// o id salvo não existe na conta Asaas atual.
export async function resolveCustomerWithCpf(
  asaas: AsaasProvider,
  input: PlayerCustomerInput,
): Promise<ResolvedCustomer> {
  const cpf = cpfOrThrow(input.cpf);
  const draft = {
    name: input.name,
    email: input.email,
    externalReference: input.externalReference,
    cpfCnpj: cpf,
  };
  if (!input.customerId) {
    const created = await asaas.createCustomer(draft);
    return { id: created.id, replacedId: null };
  }
  try {
    const current = await asaas.getCustomer(input.customerId);
    if (!current.deleted) {
      if (current.cpfCnpj.length === 0) {
        await asaas.updateCustomerCpf(input.customerId, cpf);
      }
      return { id: input.customerId, replacedId: null };
    }
  } catch (error) {
    if (!customerMissing(error)) throw error;
  }
  const created = await asaas.createCustomer(draft);
  return { id: created.id, replacedId: input.customerId };
}

/// O mesmo id de [resolveCustomerWithCpf], para quem só precisa da string.
export async function customerWithCpf(
  asaas: AsaasProvider,
  input: PlayerCustomerInput,
): Promise<string> {
  return (await resolveCustomerWithCpf(asaas, input)).id;
}

/// Desativa os cartões do customer antigo e só então grava o id novo.
/// A ordem importa: o gatilho do cartão exige que o perfil ainda aponte
/// para o customer do cartão.
export async function storeReplacedCustomer(
  db: CustomerStore,
  userId: string,
  previousId: string | null,
  nextId: string,
): Promise<string | null> {
  const replaced = previousId && previousId !== nextId ? previousId : null;
  if (replaced) {
    const deactivated = await db.rpc("deactivate_customer_saved_cards", {
      p_user_id: userId,
      p_customer_id: replaced,
    });
    if (deactivated.error) throw new Error("customer_cards");
  }
  if (nextId !== previousId) {
    const updated = await db.from("profiles").update({
      asaas_customer_id: nextId,
    }).eq("id", userId);
    if (updated.error) throw new Error("customer_profile");
  }
  return replaced;
}

/// Cartão salvo ligado ao customer que acabou de ser trocado.
export function chargeAsksNewCard(
  replacedId: string | null,
  savedCardId: string,
): boolean {
  return replacedId !== null && savedCardId.length > 0;
}
