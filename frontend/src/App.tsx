import { useState } from "react";
import type { Address } from "viem";
import { isAddress, zeroAddress } from "viem";
import { FACTORY_ADDRESS, USDC_ADDRESS } from "./config";
import Header from "./components/Header";
import Faucet from "./components/Faucet";
import CreateRonda from "./components/CreateRonda";
import RondaList from "./components/RondaList";
import RondaDetail from "./components/RondaDetail";

export default function App() {
  const [selected, setSelected] = useState<Address | null>(null);
  const configured =
    isAddress(FACTORY_ADDRESS ?? "") && isAddress(USDC_ADDRESS ?? "") && FACTORY_ADDRESS !== zeroAddress;

  if (!configured) {
    return (
      <>
        <Header />
        <main className="setup">
          <h1>Falta configurar las direcciones</h1>
          <p>
            Copiá <code>frontend/.env.example</code> a <code>frontend/.env.local</code> y completá
            <code> VITE_FACTORY_ADDRESS</code> y <code>VITE_USDC_ADDRESS</code> con lo que imprimió{" "}
            <code>make deploy</code>.
          </p>
        </main>
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="layout">
        <aside className="side">
          <Faucet />
          <CreateRonda onCreated={setSelected} />
          <RondaList selected={selected} onSelect={setSelected} />
        </aside>
        <section className="stage">
          {selected ? (
            <RondaDetail key={selected} address={selected} />
          ) : (
            <div className="empty">
              <h1>Ahorrá en ronda, sin que nadie guarde la plata</h1>
              <p>
                Cada miembro deja una garantía y aporta lo mismo en cada turno. El pozo lo cobra uno distinto por
                turno, en un orden que sortea Chainlink VRF cuando se completa el cupo, y que nadie puede arreglar. Si
                alguien no paga, su garantía cubre el aporte.
              </p>
              <p>Elegí una ronda de la lista o creá una nueva para empezar.</p>
            </div>
          )}
        </section>
      </main>
    </>
  );
}
