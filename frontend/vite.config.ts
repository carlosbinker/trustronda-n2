import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    // viem + wagmi pesan ~180 kB gzip en un solo chunk. Es aceptable para una dApp de una página;
    // se sube el umbral del aviso a propósito (analizado, ver README > "Warnings analizados").
    chunkSizeWarningLimit: 700,
  },
})
