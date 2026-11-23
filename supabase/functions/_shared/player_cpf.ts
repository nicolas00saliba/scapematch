import { PagBankProvider, type CustomerInput } from "./pagbank_provider.ts";

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

/// Customer da conta PagBank atual. `replacedId` é o id que não existe mais
/// (404 ou `deleted`) e cujos cartões precisam ser desativados antes de
/// gravar o id novo.
export type ResolvedCustomer = {
  id: string;
  replacedId: string | null;
};

/// A cobrança com cartão salvo pede recadastro quando o customer foi trocado.
export const cardReregisterCode = "card_reregister";

type ClaimFilter = {
  eq(column: string, value: string): ClaimFilter;
  is(column: string, value: null): ClaimFilter;
  select(columns: string): PromiseLike<{
    data: unknown;
    error: { message?: string } | null;
  }>;
};

type CustomerStore = {
  from(table: string): {
    update(values: Record<string, unknown>): {
      eq(column: string, value: string): ClaimFilter;
    };
    select(columns: string): {
      eq(column: string, value: string): {
        maybeSingle(): PromiseLike<{
          data: Record<string, unknown> | null;
          error: { message?: string } | null;
        }>;
      };
    };
  };
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string } | null }>;
};

type CustomerCleaner = {
  deleteCustomer(id: string): Promise<void>;
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
  return error instanceof Error && /^PagBank 404\b/.test(error.message);
}

/// Cria o customer com o CPF, preenche o documento vazio, ou recria quando
/// o id salvo não existe na conta PagBank atual.
export async function resolveCustomerWithCpf(
  pagbank: PagBankProvider,
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
    const created = await pagbank.createCustomer(draft);
    return { id: created.id, replacedId: null };
  }
  try {
    const current = await pagbank.getCustomer(input.customerId);
    if (!current.deleted) {
      if (current.cpfCnpj.length === 0) {
        await pagbank.updateCustomerCpf(input.customerId, cpf);
      }
      return { id: input.customerId, replacedId: null };
    }
  } catch (error) {
    if (!customerMissing(error)) throw error;
  }
  const created = await pagbank.createCustomer(draft);
  return { id: created.id, replacedId: input.customerId };
}

/// O mesmo id de [resolveCustomerWithCpf], para quem só precisa da string.
export async function customerWithCpf(
  pagbank: PagBankProvider,
  input: PlayerCustomerInput,
): Promise<string> {
  return (await resolveCustomerWithCpf(pagbank, input)).id;
}

/// Quem grava o id novo é o update com `pagbank_customer_id = previousId`.
/// A outra chamada relê o perfil e usa o customer que ficou. O id que
/// ela criou no PagBank é apagado; se o DELETE falhar, a cobrança segue.
export async function storeReplacedCustomer(
  db: CustomerStore,
  userId: string,
  previousId: string | null,
  nextId: string,
  pagbank?: CustomerCleaner,
): Promise<{ id: string; replacedId: string | null }> {
  if (previousId && previousId !== nextId) {
    const deactivated = await db.rpc("deactivate_customer_saved_cards", {
      p_user_id: userId,
      p_customer_id: previousId,
    });
    if (deactivated.error) throw new Error("customer_cards");
  }
  const id = await claimCustomerId(db, userId, previousId, nextId);
  if (pagbank && id !== nextId) {
    try {
      await pagbank.deleteCustomer(nextId);
    } catch (_error) {
      // O perdedor pode ficar na conta. A cobrança usa o id que venceu.
    }
  }
  return {
    id,
    replacedId: previousId && id !== previousId ? previousId : null,
  };
}

async function claimCustomerId(
  db: CustomerStore,
  userId: string,
  previousId: string | null,
  nextId: string,
): Promise<string> {
  if (previousId === nextId) return nextId;
  let filter = db.from("profiles").update({
    pagbank_customer_id: nextId,
  }).eq("id", userId);
  filter = previousId === null
    ? filter.is("pagbank_customer_id", null)
    : filter.eq("pagbank_customer_id", previousId);
  const claimed = await filter.select("pagbank_customer_id");
  if (claimed.error) throw new Error("customer_profile");
  const rows = Array.isArray(claimed.data) ? claimed.data : [];
  if (rows.length > 0) return nextId;
  const current = await db.from("profiles").select("pagbank_customer_id").eq(
    "id",
    userId,
  ).maybeSingle();
  if (current.error) throw new Error("customer_profile");
  const id = current.data?.pagbank_customer_id;
  if (typeof id === "string" && id.length > 0) return id;
  throw new Error("customer_profile");
}

/// Cartão salvo ligado ao customer que acabou de ser trocado.
export function chargeAsksNewCard(
  replacedId: string | null,
  savedCardId: string,
): boolean {
  return replacedId !== null && savedCardId.length > 0;
}
