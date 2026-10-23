import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError } from "viem";

/** Traducción de los custom errors de los contratos a mensajes que indican qué hacer. */
const MESSAGES: Record<string, string> = {
  AlreadyMember: "Esta cuenta ya está inscripta en la ronda.",
  NotMember: "Esta cuenta no es miembro de la ronda.",
  JoinWindowClosed: "La inscripción ya cerró. Cualquiera puede cancelar la ronda para liberar las garantías.",
  AlreadyPaid: "Ya pagaste el aporte de este turno.",
  RoundExpired: "El turno venció: el aporte ya no se puede pagar. Cerrá el turno para ejecutar las garantías.",
  RoundStillOpen: "Todavía no se puede cerrar: faltan aportes y el turno no venció.",
  NothingToWithdraw: "No tenés nada para retirar en esta ronda.",
  NotAuthorizedToCancel: "Solo el organizador puede cancelar antes de que venza la inscripción.",
  InvalidStatus: "La ronda no está en el estado necesario para esta acción.",
  InvalidCollateral: "La garantía tiene que ser igual o mayor que el aporte.",
  InvalidMemberCount: "El cupo tiene que ser de 2 a 12 miembros.",
  InvalidDuration: "Las duraciones tienen que estar entre 5 minutos y 90 días.",
  InvalidContribution: "El aporte tiene que ser mayor que cero.",
  TokenNotAllowed: "Ese token no está habilitado en la factory.",
  FaucetCooldown: "Ya usaste el faucet hoy. Podés volver a pedir en 24 h.",
  ERC20InsufficientBalance: "No te alcanza el saldo de tUSD. Pedí tUSD con el faucet.",
  ERC20InsufficientAllowance: "Falta la aprobación (approve) de tUSD.",
};

export function explainError(err: unknown): string {
  if (err instanceof BaseError) {
    if (err.walk((e) => e instanceof UserRejectedRequestError)) return "Cancelaste la firma en la wallet.";
    const revert = err.walk((e) => e instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName ?? "";
      return MESSAGES[name] ?? `El contrato revirtió: ${name || revert.shortMessage}`;
    }
    return err.shortMessage;
  }
  return err instanceof Error ? err.message : String(err);
}
