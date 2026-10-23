import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { usePublicClient, useWriteContract } from "wagmi";
import type { Hash } from "viem";
import { explainError } from "./errors";

export type TxLog = { label: string; hash: Hash; ok: boolean };

/**
 * Envía una o más transacciones en secuencia (por ejemplo approve + join), espera cada receipt
 * y al final refresca todas las lecturas. Expone el paso actual, el error traducido y los hashes.
 */
export function useTx(onDone?: (logs: TxLog[]) => void) {
  const { writeContractAsync } = useWriteContract();
  const client = usePublicClient();
  const qc = useQueryClient();
  const [step, setStep] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [logs, setLogs] = useState<TxLog[]>([]);

  type Call = { label: string; request: Parameters<typeof writeContractAsync>[0] };

  async function run(calls: Call[]) {
    setError(null);
    const done: TxLog[] = [];
    try {
      for (const c of calls) {
        setStep(`${c.label}: firmá en la wallet`);
        const hash = await writeContractAsync(c.request);
        setStep(`${c.label}: esperando confirmación`);
        const receipt = await client!.waitForTransactionReceipt({ hash });
        done.push({ label: c.label, hash, ok: receipt.status === "success" });
        if (receipt.status !== "success") throw new Error(`${c.label}: la transacción revirtió`);
      }
      onDone?.(done);
    } catch (e) {
      setError(explainError(e));
    } finally {
      setLogs((l) => [...done, ...l]);
      setStep(null);
      await qc.invalidateQueries();
    }
  }

  return { run, step, error, logs, busy: step !== null };
}
