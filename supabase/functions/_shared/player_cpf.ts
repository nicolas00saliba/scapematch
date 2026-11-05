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

/// Cria o customer com o CPF ou preenche o que já existe e está vazio.
/// Quem já tem documento no Asaas não é reescrito.
export async function customerWithCpf(
  asaas: AsaasProvider,
  input: CustomerInput & { customerId: string | null; cpf: string },
): Promise<string> {
  const cpf = playerCpfDigits(input.cpf);
  if (!cpf) {
    const error = new Error("cpf_required");
    error.name = "CpfRequired";
    throw error;
  }
  if (!input.customerId) {
    const created = await asaas.createCustomer({
      name: input.name,
      email: input.email,
      externalReference: input.externalReference,
      cpfCnpj: cpf,
    });
    return created.id;
  }
  const current = await asaas.getCustomer(input.customerId);
  if (current.cpfCnpj.length === 0) {
    await asaas.updateCustomerCpf(input.customerId, cpf);
  }
  return input.customerId;
}
