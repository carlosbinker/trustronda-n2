import { formatUnits } from "viem";
import { EXPLORER } from "../config";

/** tUSD tiene 6 decimales, como USDC. */
export const DECIMALS = 6;

export const fmtUsd = (v?: bigint) =>
  v === undefined ? "—" : `${Number(formatUnits(v, DECIMALS)).toLocaleString("es-AR", { maximumFractionDigits: 2 })} tUSD`;

export const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—");

export const txUrl = (hash: string) => (EXPLORER ? `${EXPLORER}/tx/${hash}` : "");
export const addrUrl = (addr: string) => (EXPLORER ? `${EXPLORER}/address/${addr}#code` : "");

/** Estados del enum RondaStatus, en el mismo orden que en Solidity. */
export const STATUS = ["Inscripción abierta", "Sorteando el orden", "En curso", "Terminada", "Cancelada"] as const;

export function fmtDuration(seconds: number) {
  if (seconds <= 0) return "vencido";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d) return `${d} d ${h} h`;
  if (h) return `${h} h ${m} min`;
  const s = seconds % 60;
  if (m && !s) return `${m} min`;
  return m ? `${m} min ${s} s` : `${s} s`;
}

export const fmtDate = (ts: bigint | number) =>
  new Date(Number(ts) * 1000).toLocaleString("es-AR", { dateStyle: "short", timeStyle: "short" });
