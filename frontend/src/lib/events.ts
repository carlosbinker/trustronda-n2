import type { Address, GetContractEventsReturnType, PublicClient } from "viem";
import { trustRondaAbi } from "../abi/TrustRonda";

/** Tramo inicial de bloques por consulta de eventos. Si el RPC lo rechaza, se achica solo. */
const INITIAL_CHUNK = 50_000n;
/** Tramo mínimo: algunos RPC gratuitos (Alchemy free) aceptan solo 10 bloques por eth_getLogs. */
const MIN_CHUNK = 10n;

export type RondaEvent = GetContractEventsReturnType<typeof trustRondaAbi>[number];

/** Eventos ya leídos por ronda y último bloque revisado: cada refresco pide solo los bloques nuevos. */
const cache = new Map<Address, { lastBlock: bigint; events: RondaEvent[]; chunk: bigint }>();

/**
 * Lee los eventos de una ronda desde `fromBlock` en tramos. Si el RPC rechaza un rango, lo divide por 10
 * hasta `MIN_CHUNK`, y recuerda el tramo que funcionó para los próximos refrescos.
 * @param client cliente público de viem (lecturas)
 * @param address dirección de la ronda
 * @param fromBlock primer bloque a revisar (el del deploy de la factory)
 * @return todos los eventos de la ronda, en orden de bloque
 */
export async function getRondaEvents(client: PublicClient, address: Address, fromBlock: bigint): Promise<RondaEvent[]> {
  const latest = await client.getBlockNumber();
  const entry = cache.get(address) ?? { lastBlock: fromBlock - 1n, events: [], chunk: INITIAL_CHUNK };
  let from = entry.lastBlock + 1n;
  let chunk = entry.chunk;

  while (from <= latest) {
    const to = from + chunk - 1n > latest ? latest : from + chunk - 1n;
    try {
      const logs = await client.getContractEvents({ address, abi: trustRondaAbi, fromBlock: from, toBlock: to });
      entry.events.push(...logs);
      entry.lastBlock = to;
      from = to + 1n;
    } catch (err) {
      if (chunk <= MIN_CHUNK) throw err;
      chunk = chunk / 10n < MIN_CHUNK ? MIN_CHUNK : chunk / 10n;
    }
  }
  entry.chunk = chunk;
  cache.set(address, entry);
  return [...entry.events];
}
