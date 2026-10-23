/// <reference types="vite/client" />
interface ImportMetaEnv {
  readonly VITE_CHAIN_ID?: string;
  readonly VITE_FACTORY_ADDRESS?: string;
  readonly VITE_USDC_ADDRESS?: string;
  readonly VITE_DEPLOY_BLOCK?: string;
  readonly VITE_RPC_URL?: string;
}
