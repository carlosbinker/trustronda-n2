import type { Address } from "viem";
import { short } from "../lib/format";

export type Seat = { address: Address; paid: boolean; defaults: number };

/**
 * La ronda dibujada como lo que es: un círculo de lugares. Cada lugar es un miembro, en orden de cobro.
 * Ya cobró → relleno; cobra este turno → anillo ámbar; pagó el turno → tilde; tuvo impagos → borde rojo.
 */
export default function Wheel({
  seats, capacity, currentRound, active, me, center,
}: {
  seats: Seat[]; capacity: number; currentRound: number; active: boolean; me?: Address; center: React.ReactNode;
}) {
  const R = 150, C = 200, r = capacity > 8 ? 22 : 28;
  return (
    <div className="wheel">
      <svg viewBox="0 0 400 400" role="img" aria-label={`Ronda de ${capacity} lugares, ${seats.length} ocupados`}>
        <circle cx={C} cy={C} r={R} className="track" />
        {Array.from({ length: capacity }, (_, i) => {
          const a = (i / capacity) * 2 * Math.PI - Math.PI / 2;
          const x = C + R * Math.cos(a), y = C + R * Math.sin(a);
          const s = seats[i];
          const cobro = s && i < currentRound;
          const turno = active && i === currentRound;
          const cls = ["seat", !s && "free", cobro && "done", turno && "turn", s && s.defaults > 0 && "default"]
            .filter(Boolean).join(" ");
          return (
            <g key={i} className={cls}>
              <circle cx={x} cy={y} r={r} />
              <text x={x} y={y + 4} textAnchor="middle" className="seat-n">{i + 1}</text>
              {s && active && s.paid && <path d={`M${x + r - 14} ${y - r + 6} l4 4 l8 -9`} className="check" />}
              <text x={x} y={y + r + 16} textAnchor="middle" className="seat-l">
                {s ? (s.address.toLowerCase() === me?.toLowerCase() ? "vos" : short(s.address)) : "libre"}
              </text>
            </g>
          );
        })}
      </svg>
      <div className="hub">{center}</div>
    </div>
  );
}
