import { useAccount, useReadContracts } from "wagmi";
import { USDC_ADDRESS } from "../config";
import { mockUSDCAbi } from "../abi/MockUSDC";
import { fmtUsd, fmtDate } from "../lib/format";
import { useTx } from "../lib/useTx";
import { useNow } from "../lib/useNow";
import TxStatus from "./TxStatus";

export default function Faucet() {
  const { address } = useAccount();
  const usdc = { address: USDC_ADDRESS, abi: mockUSDCAbi } as const;
  const { data } = useReadContracts({
    contracts: [
      { ...usdc, functionName: "balanceOf", args: [address!] },
      { ...usdc, functionName: "lastFaucetClaim", args: [address!] },
    ],
    query: { enabled: !!address },
  });
  const tx = useTx();
  const now = useNow();
  const balance = data?.[0].result;
  const last = data?.[1].result ?? 0n;
  const nextClaim = last === 0n ? 0n : last + 86400n;
  const canClaim = nextClaim <= BigInt(now);

  return (
    <div className="panel">
      <h2>Tu saldo</h2>
      <p className="big">{address ? fmtUsd(balance) : "Conectá tu wallet"}</p>
      {address && (
        <>
          <button
            className="btn"
            disabled={tx.busy || !canClaim}
            onClick={() => tx.run([{ label: "Faucet", request: { ...usdc, functionName: "faucet" } }])}
          >
            Pedir 1.000 tUSD de prueba
          </button>
          {!canClaim && <p className="small muted">Podés volver a pedir desde el {fmtDate(nextClaim)}</p>}
          <TxStatus {...tx} />
        </>
      )}
    </div>
  );
}
