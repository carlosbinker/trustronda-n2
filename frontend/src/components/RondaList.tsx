import { useReadContract, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { FACTORY_ADDRESS } from "../config";
import { trustRondaFactoryAbi } from "../abi/TrustRondaFactory";
import { trustRondaAbi } from "../abi/TrustRonda";
import { STATUS, fmtUsd, short } from "../lib/format";

const PAGE = 50n;

export default function RondaList({ selected, onSelect }: { selected: Address | null; onSelect: (a: Address) => void }) {
  const factory = { address: FACTORY_ADDRESS, abi: trustRondaFactoryAbi } as const;
  const { data: count } = useReadContract({ ...factory, functionName: "rondasCount" });
  const offset = count && count > PAGE ? count - PAGE : 0n;
  const { data: rondas } = useReadContract({
    ...factory, functionName: "getRondas", args: [offset, PAGE], query: { enabled: count !== undefined },
  });
  const list = [...(rondas ?? [])].reverse(); // más nuevas primero

  const fields = ["status", "memberCount", "maxMembers", "contributionAmount"] as const;
  const { data } = useReadContracts({
    contracts: list.flatMap((address) => fields.map((functionName) => ({ address, abi: trustRondaAbi, functionName }))),
    query: { enabled: list.length > 0 },
  });

  return (
    <div className="panel">
      <h2>Rondas {count !== undefined && <span className="muted">({count.toString()})</span>}</h2>
      {list.length === 0 && <p className="muted">Todavía no hay rondas. Creá la primera.</p>}
      <ul className="rondas">
        {list.map((addr, i) => {
          const r = data?.slice(i * 4, i * 4 + 4).map((x) => x.result);
          const status = r?.[0] as number | undefined;
          return (
            <li key={addr}>
              <button className={`ronda-row ${selected === addr ? "sel" : ""}`} onClick={() => onSelect(addr)}>
                <span className={`dot s${status ?? 0}`} aria-hidden="true" />
                <span className="addr">{short(addr)}</span>
                <span className="muted">{r ? `${r[1]} de ${r[2]} miembros, ${fmtUsd(r[3] as bigint)}` : "…"}</span>
                <span className="small">{status !== undefined ? STATUS[status] : ""}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
