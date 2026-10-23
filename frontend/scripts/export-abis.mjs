// Copia los ABIs compilados por Foundry (out/) a frontend/src/abi como módulos TS tipados (`as const`),
// así wagmi/viem infieren tipos de argumentos y retornos. Correr después de `forge build` (o `make abi`).
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const contracts = ["MockUSDC", "TrustRonda", "TrustRondaFactory"];

for (const name of contracts) {
  const artifact = JSON.parse(readFileSync(resolve(root, `out/${name}.sol/${name}.json`), "utf8"));
  const out = resolve(root, `frontend/src/abi/${name}.ts`);
  writeFileSync(
    out,
    `// Generado por scripts/export-abis.mjs desde out/${name}.sol — no editar a mano.\n` +
      `export const ${name[0].toLowerCase() + name.slice(1)}Abi = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`,
  );
  console.log(`ABI exportado: ${out}`);
}
