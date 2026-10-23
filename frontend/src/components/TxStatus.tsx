import type { TxLog } from "../lib/useTx";
import { txUrl, short } from "../lib/format";

/** Muestra el paso en curso, el error traducido y los hashes de las últimas transacciones (evidencia on-chain). */
export default function TxStatus({ step, error, logs }: { step: string | null; error: string | null; logs: TxLog[] }) {
  return (
    <div className="tx" aria-live="polite">
      {step && <p className="step"><span className="spinner" aria-hidden="true" />{step}</p>}
      {error && <p className="err">{error}</p>}
      {logs.slice(0, 3).map((l) => (
        <p key={l.hash} className={l.ok ? "ok" : "err"}>
          {l.label} {l.ok ? "confirmada" : "revertida"}:{" "}
          {txUrl(l.hash) ? <a href={txUrl(l.hash)} target="_blank" rel="noreferrer">{short(l.hash)}</a> : short(l.hash)}
        </p>
      ))}
    </div>
  );
}
