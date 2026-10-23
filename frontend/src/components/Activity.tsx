import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { trustRondaAbi } from "../abi/TrustRonda";
import { DEPLOY_BLOCK } from "../config";
import { fmtUsd, short, txUrl } from "../lib/format";

type Args = Record<string, unknown>;

function describe(name: string, a: Args): string {
  switch (name) {
    case "MemberJoined": return `${short(a.member as string)} se inscribió y cobra en el turno ${Number(a.position) + 1}`;
    case "RondaStarted": return "Se completó el cupo: arrancó la ronda";
    case "NewRound": return `Arrancó el turno ${Number(a.round) + 1}`;
    case "ContributionMade": return `${short(a.member as string)} pagó ${fmtUsd(a.amount as bigint)} (turno ${Number(a.round) + 1})`;
    case "CollateralSlashed": return `Se ejecutaron ${fmtUsd(a.amount as bigint)} de la garantía de ${short(a.member as string)}`;
    case "RoundClosed": return `Turno ${Number(a.round) + 1} cerrado: ${fmtUsd(a.pot as bigint)} para ${short(a.beneficiary as string)}`;
    case "RondaCompleted": return "Todos cobraron: la ronda terminó";
    case "RondaCancelled": return `${short(a.by as string)} canceló la ronda`;
    case "Withdrawn": return `${short(a.account as string)} retiró ${fmtUsd((a.payout as bigint) + (a.collateral as bigint))}`;
    default: return name;
  }
}

/** Historial leído de los eventos del contrato: es la evidencia on-chain de cada paso, con link a Etherscan. */
export default function Activity({ address }: { address: Address }) {
  const client = usePublicClient();
  const { data, isLoading, error } = useQuery({
    queryKey: ["events", address],
    queryFn: () => client!.getContractEvents({ address, abi: trustRondaAbi, fromBlock: DEPLOY_BLOCK }),
    enabled: !!client,
  });

  return (
    <div className="panel">
      <h2>Historial on-chain</h2>
      {isLoading && <p className="muted">Leyendo eventos…</p>}
      {error && <p className="err small">No se pudieron leer los eventos (probá con otro RPC en VITE_RPC_URL).</p>}
      <ol className="log">
        {[...(data ?? [])].reverse().map((ev) => (
          <li key={`${ev.transactionHash}-${ev.logIndex}`}>
            <span>{describe(ev.eventName, ev.args as Args)}</span>
            {txUrl(ev.transactionHash) && (
              <a href={txUrl(ev.transactionHash)} target="_blank" rel="noreferrer">ver tx</a>
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}
