import { useAccount, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { USDC_ADDRESS } from "../config";
import { trustRondaAbi } from "../abi/TrustRonda";
import { mockUSDCAbi } from "../abi/MockUSDC";
import { STATUS, addrUrl, fmtDate, fmtDuration, fmtUsd, short } from "../lib/format";
import { useTx } from "../lib/useTx";
import { useNow } from "../lib/useNow";
import Wheel, { type Seat } from "./Wheel";
import Activity from "./Activity";
import TxStatus from "./TxStatus";

type MemberInfo = { collateral: bigint; position: number; defaults: number; isMember: boolean };

export default function RondaDetail({ address }: { address: Address }) {
  const { address: me } = useAccount();
  const now = useNow();
  const ronda = { address, abi: trustRondaAbi } as const;
  const usdc = { address: USDC_ADDRESS, abi: mockUSDCAbi } as const;
  const tx = useTx();

  // 1) Estado general de la ronda
  const base = useReadContracts({
    contracts: [
      { ...ronda, functionName: "status" },
      { ...ronda, functionName: "currentRound" },
      { ...ronda, functionName: "paidCount" },
      { ...ronda, functionName: "roundDeadline" },
      { ...ronda, functionName: "maxMembers" },
      { ...ronda, functionName: "contributionAmount" },
      { ...ronda, functionName: "collateralAmount" },
      { ...ronda, functionName: "joinDeadline" },
      { ...ronda, functionName: "organizer" },
      { ...ronda, functionName: "getMembers" },
      { ...ronda, functionName: "roundDuration" },
      { ...ronda, functionName: "drawRequestedAt" },
    ],
  });
  const d = base.data?.map((x) => x.result);
  const status = d?.[0] as number | undefined;
  const currentRound = Number(d?.[1] ?? 0);
  const paidCount = Number(d?.[2] ?? 0);
  const roundDeadline = Number(d?.[3] ?? 0n);
  const maxMembers = Number(d?.[4] ?? 0);
  const contribution = d?.[5] as bigint | undefined;
  const collateral = d?.[6] as bigint | undefined;
  const joinDeadline = Number(d?.[7] ?? 0n);
  const organizer = d?.[8] as Address | undefined;
  const members = (d?.[9] as readonly Address[] | undefined) ?? [];
  const roundDuration = Number(d?.[10] ?? 0n);
  const drawRequestedAt = Number(d?.[11] ?? 0n);
  const DRAW_TIMEOUT = 86400; // TrustRonda.DRAW_TIMEOUT

  // 2) Detalle por miembro: si pagó el turno en curso y sus impagos
  const perMember = useReadContracts({
    contracts: members.flatMap((m) => [
      { ...ronda, functionName: "hasPaid", args: [currentRound, m] } as const,
      { ...ronda, functionName: "getMemberInfo", args: [m] } as const,
    ]),
    query: { enabled: members.length > 0 },
  });
  const seats: Seat[] = members.map((m, i) => ({
    address: m,
    paid: Boolean(perMember.data?.[i * 2]?.result),
    defaults: Number((perMember.data?.[i * 2 + 1]?.result as MemberInfo | undefined)?.defaults ?? 0),
  }));

  // 3) Datos de la cuenta conectada
  const mine = useReadContracts({
    contracts: [
      { ...ronda, functionName: "withdrawable", args: [me!] },
      { ...ronda, functionName: "getMemberInfo", args: [me!] },
      { ...usdc, functionName: "allowance", args: [me!, address] },
      { ...usdc, functionName: "balanceOf", args: [me!] },
    ],
    query: { enabled: !!me },
  });
  const [payout, collateralBack] = (mine.data?.[0].result as readonly [bigint, bigint] | undefined) ?? [0n, 0n];
  const myInfo = mine.data?.[1].result as MemberInfo | undefined;
  const allowance = (mine.data?.[2].result as bigint | undefined) ?? 0n;
  const balance = (mine.data?.[3].result as bigint | undefined) ?? 0n;

  if (status === undefined || contribution === undefined || collateral === undefined) {
    return <div className="panel">Cargando ronda…</div>;
  }

  const isMember = !!myInfo?.isMember;
  // Mismo orden que el enum RondaStatus de Solidity
  const isOpen = status === 0, isDrawing = status === 1, isActive = status === 2;
  const drawExpired = isDrawing && now > drawRequestedAt + DRAW_TIMEOUT;
  const expired = isActive && now > roundDeadline;
  const iPaid = isMember && seats[myInfo!.position]?.paid;
  const beneficiary = isActive ? members[currentRound] : undefined;
  const pot = contribution * BigInt(maxMembers);

  /** Si el allowance no alcanza, primero se manda approve (dos transacciones). */
  const withApprove = (amount: bigint) =>
    allowance >= amount ? [] : [{ label: "Aprobar tUSD", request: { ...usdc, functionName: "approve", args: [address, amount] } as const }];

  const actions: React.ReactNode[] = [];
  if (me && isOpen && !isMember && now <= joinDeadline) {
    actions.push(
      <button key="join" className="btn primary" disabled={tx.busy || balance < collateral}
        onClick={() => tx.run([...withApprove(collateral), { label: "Inscribirme", request: { ...ronda, functionName: "join" } }])}>
        Inscribirme y dejar {fmtUsd(collateral)} de garantía
      </button>,
    );
  }
  if (me && isActive && isMember && !iPaid && !expired) {
    actions.push(
      <button key="pay" className="btn primary" disabled={tx.busy || balance < contribution}
        onClick={() => tx.run([...withApprove(contribution), { label: "Pagar aporte", request: { ...ronda, functionName: "contribute" } }])}>
        Pagar {fmtUsd(contribution)} del turno {currentRound + 1}
      </button>,
    );
  }
  if (me && isActive && (paidCount === maxMembers || expired)) {
    actions.push(
      <button key="close" className="btn primary" disabled={tx.busy}
        onClick={() => tx.run([{ label: "Cerrar turno", request: { ...ronda, functionName: "closeRound" } }])}>
        Cerrar turno {currentRound + 1} y acreditar el pozo a {beneficiary?.toLowerCase() === me.toLowerCase() ? "vos" : short(beneficiary)}
      </button>,
    );
  }
  if (me && payout + collateralBack > 0n) {
    actions.push(
      <button key="withdraw" className="btn primary" disabled={tx.busy}
        onClick={() => tx.run([{ label: "Retirar", request: { ...ronda, functionName: "withdraw" } }])}>
        Retirar {fmtUsd(payout + collateralBack)}
      </button>,
    );
  }
  if (me && ((isOpen && (me.toLowerCase() === organizer?.toLowerCase() || now > joinDeadline)) || drawExpired)) {
    actions.push(
      <button key="cancel" className="btn ghost" disabled={tx.busy}
        onClick={() => tx.run([{ label: "Cancelar ronda", request: { ...ronda, functionName: "cancel" } }])}>
        Cancelar ronda y liberar garantías
      </button>,
    );
  }

  const hint = !me ? "Conectá tu wallet para participar."
    : isOpen && isMember ? "Ya estás inscripto. Cuando se complete el cupo, Chainlink VRF sortea el orden de cobro."
    : isDrawing && !drawExpired ? "Cupo completo: Chainlink VRF está sorteando el orden de cobro. Suele tardar uno o dos minutos."
    : drawExpired ? "El sorteo no llegó a tiempo: cualquiera puede cancelar la ronda y liberar las garantías."
    : isActive && isMember && myInfo ? `Te tocó cobrar en el turno ${myInfo.position + 1}.${iPaid && paidCount < maxMembers ? ` Ya pagaste; faltan ${maxMembers - paidCount} aportes.` : ""}`
    : isOpen && now > joinDeadline ? "La inscripción venció sin completar el cupo."
    : isActive && !isMember ? "No sos miembro de esta ronda: podés cerrar el turno cuando corresponda."
    : status === 3 ? "La ronda terminó." : status === 4 ? "La ronda está cancelada." : "";

  return (
    <div className="detail">
      <div className="detail-head">
        <div>
          <h1>Ronda {short(address)}</h1>
          <p className="muted">
            {STATUS[status]}. Aporte {fmtUsd(contribution)} por turno, garantía {fmtUsd(collateral)}, turnos de{" "}
            {fmtDuration(roundDuration)}.{" "}
            {addrUrl(address) && <a href={addrUrl(address)} target="_blank" rel="noreferrer">Código verificado</a>}
          </p>
        </div>
      </div>

      <div className="detail-body">
        <Wheel
          seats={seats} capacity={maxMembers} currentRound={currentRound} active={isActive} me={me}
          center={
            <>
              <span className="pot">{fmtUsd(pot)}</span>
              <span className="muted">pozo por turno</span>
              {isActive && <>
                <span className="round">Turno {currentRound + 1} de {maxMembers}</span>
                <span className={expired ? "err" : ""}>{expired ? "Vencido" : `Vence en ${fmtDuration(roundDeadline - now)}`}</span>
                <span className="muted">{paidCount} de {maxMembers} pagaron</span>
              </>}
              {isDrawing && <>
                <span className="round drawing">Sorteando el orden</span>
                <span className="muted">con Chainlink VRF</span>
              </>}
              {isOpen && <>
                <span className="round">{members.length} de {maxMembers} inscriptos</span>
                <span className="muted">Inscripción hasta {fmtDate(joinDeadline)}</span>
              </>}
              {status === 3 && <span className="round">Terminada</span>}
              {status === 4 && <span className="round">Cancelada</span>}
            </>
          }
        />

        <div className="actions panel">
          <h2>Qué podés hacer</h2>
          {hint && <p>{hint}</p>}
          {actions.length ? <div className="stack">{actions}</div> : me && <p className="muted">No hay acciones disponibles ahora.</p>}
          {me && (payout > 0n || collateralBack > 0n) && (
            <p className="small muted">Pozo cobrado: {fmtUsd(payout)}. Garantía a devolver: {fmtUsd(collateralBack)}.</p>
          )}
          <TxStatus {...tx} />
        </div>
      </div>

      <Activity address={address} />
    </div>
  );
}
