import { http, createConfig } from "wagmi";
import { foundry, sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import type { Address } from "viem";

/** Red objetivo: Sepolia por defecto; 31337 para probar contra anvil. */
export const CHAIN_ID = Number(import.meta.env.VITE_CHAIN_ID ?? sepolia.id);
export const chain = CHAIN_ID === foundry.id ? foundry : sepolia;

export const FACTORY_ADDRESS = import.meta.env.VITE_FACTORY_ADDRESS as Address;
export const USDC_ADDRESS = import.meta.env.VITE_USDC_ADDRESS as Address;
export const DEPLOY_BLOCK = BigInt(import.meta.env.VITE_DEPLOY_BLOCK ?? 0);
const RPC_URL = (import.meta.env.VITE_RPC_URL as string | undefined) || undefined;

export const EXPLORER = chain.id === sepolia.id ? "https://sepolia.etherscan.io" : "";

export const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [injected()],
  transports: { [chain.id]: http(RPC_URL) } as Record<number, ReturnType<typeof http>>,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
