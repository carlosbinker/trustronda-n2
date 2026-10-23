import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { chain } from "../config";
import { short } from "../lib/format";

export default function Header() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending, error } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const wrongChain = isConnected && chainId !== chain.id;

  return (
    <header className="top">
      <div className="brand">
        <svg viewBox="0 0 32 32" aria-hidden="true">
          <circle cx="16" cy="16" r="11" fill="none" stroke="currentColor" strokeWidth="2.5" />
          {[0, 1, 2, 3, 4].map((i) => {
            const a = (i / 5) * 2 * Math.PI - Math.PI / 2;
            return <circle key={i} cx={16 + 11 * Math.cos(a)} cy={16 + 11 * Math.sin(a)} r="3.2" fill={i === 0 ? "var(--amber)" : "currentColor"} />;
          })}
        </svg>
        <span>TrustRonda</span>
      </div>
      <div className="wallet">
        <span className="net">{chain.name}</span>
        {!isConnected && (
          <button className="btn" disabled={isPending} onClick={() => connect({ connector: connectors[0] })}>
            {isPending ? "Conectando…" : "Conectar wallet"}
          </button>
        )}
        {wrongChain && (
          <button className="btn warn" onClick={() => switchChain({ chainId: chain.id })}>
            Cambiar a {chain.name}
          </button>
        )}
        {isConnected && !wrongChain && (
          <button className="btn ghost" title="Desconectar" onClick={() => disconnect()}>
            {short(address)}
          </button>
        )}
        {error && <span className="err small">{error.message.includes("Provider not found") ? "Instalá MetaMask" : error.message}</span>}
      </div>
    </header>
  );
}
