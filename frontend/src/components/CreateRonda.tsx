import { useState } from "react";
import { useAccount, usePublicClient } from "wagmi";
import { parseUnits, type Address } from "viem";
import { FACTORY_ADDRESS, USDC_ADDRESS } from "../config";
import { trustRondaFactoryAbi } from "../abi/TrustRondaFactory";
import { DECIMALS } from "../lib/format";
import { useTx } from "../lib/useTx";
import TxStatus from "./TxStatus";

const DURATIONS = [
  { label: "5 minutos (demo)", value: 300 },
  { label: "1 hora", value: 3600 },
  { label: "1 día", value: 86400 },
  { label: "1 semana", value: 604800 },
  { label: "30 días", value: 2592000 },
];

export default function CreateRonda({ onCreated }: { onCreated: (a: Address) => void }) {
  const { address } = useAccount();
  const client = usePublicClient();
  const [contribution, setContribution] = useState("50");
  const [collateral, setCollateral] = useState("50");
  const [members, setMembers] = useState(2);
  const [round, setRound] = useState(300);
  const [joinWindow, setJoinWindow] = useState(86400);

  const tx = useTx(async () => {
    // La ronda nueva es la última del registro de la factory
    const count = await client!.readContract({ address: FACTORY_ADDRESS, abi: trustRondaFactoryAbi, functionName: "rondasCount" });
    const [last] = await client!.readContract({
      address: FACTORY_ADDRESS, abi: trustRondaFactoryAbi, functionName: "getRondas", args: [count - 1n, 1n],
    });
    if (last) onCreated(last);
  });

  let parsed: { c: bigint; g: bigint } | null = null;
  try {
    parsed = { c: parseUnits(contribution || "0", DECIMALS), g: parseUnits(collateral || "0", DECIMALS) };
  } catch {
    parsed = null;
  }
  const invalid = !parsed || parsed.c === 0n || parsed.g < parsed.c;

  return (
    <form
      className="panel"
      onSubmit={(e) => {
        e.preventDefault();
        if (!parsed || invalid) return;
        tx.run([{
          label: "Crear ronda",
          request: {
            address: FACTORY_ADDRESS, abi: trustRondaFactoryAbi, functionName: "createRonda",
            args: [USDC_ADDRESS, parsed.c, parsed.g, members, BigInt(round), BigInt(joinWindow)],
          },
        }]);
      }}
    >
      <h2>Crear una ronda</h2>
      <div className="grid2">
        <label>Aporte por turno (tUSD)
          <input inputMode="decimal" value={contribution} onChange={(e) => setContribution(e.target.value)} />
        </label>
        <label>Garantía (tUSD)
          <input inputMode="decimal" value={collateral} onChange={(e) => setCollateral(e.target.value)} />
        </label>
        <label>Miembros
          <input type="number" min={2} max={12} value={members} onChange={(e) => setMembers(Number(e.target.value))} />
        </label>
        <label>Duración del turno
          <select value={round} onChange={(e) => setRound(Number(e.target.value))}>
            {DURATIONS.map((d) => <option key={d.value} value={d.value}>{d.label}</option>)}
          </select>
        </label>
        <label className="span2">Plazo para completar el cupo
          <select value={joinWindow} onChange={(e) => setJoinWindow(Number(e.target.value))}>
            {DURATIONS.map((d) => <option key={d.value} value={d.value}>{d.label}</option>)}
          </select>
        </label>
      </div>
      {parsed && parsed.g < parsed.c && <p className="err small">La garantía tiene que cubrir al menos un aporte.</p>}
      <button className="btn primary" disabled={!address || tx.busy || invalid}>Crear ronda</button>
      <TxStatus {...tx} />
    </form>
  );
}
