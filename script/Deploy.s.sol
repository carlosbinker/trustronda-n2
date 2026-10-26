// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../contracts/MockUSDC.sol";
import {TrustRondaFactory} from "../contracts/TrustRondaFactory.sol";
import {IVRFCoordinatorV2Plus} from
    "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

/// @title Deploy
/// @notice Despliega MockUSDC (tUSD) y TrustRondaFactory, con tUSD ya habilitado; agrega la factory como consumidor
///         de la suscripción de Chainlink VRF y guarda las direcciones en deployments/<chainId>.json.
/// @dev Sepolia (con verificación en Etherscan):
///        forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
///      Requiere VRF_SUBSCRIPTION_ID: la suscripción se crea en vrf.chain.link con la MISMA wallet de PRIVATE_KEY
///      (para que este script pueda llamar a addConsumer). Coordinador y key hash de Sepolia: valores de
///      docs.chain.link/vrf/v2-5/supported-networks, sobrescribibles con VRF_COORDINATOR y VRF_KEY_HASH.
///      Para ensayar en anvil: desplegar antes VRFCoordinatorV2_5Mock, crear y fondear una suscripción con cast y
///      pasar VRF_COORDINATOR y VRF_SUBSCRIPTION_ID (ver README, sección 7, "Ensayo local en anvil").
contract Deploy is Script {
    /// @dev Chainlink VRF v2.5, Ethereum Sepolia (docs.chain.link/vrf/v2-5/supported-networks).
    address internal constant SEPOLIA_VRF_COORDINATOR = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    /// @dev Gas lane de 500 gwei, la única disponible en Sepolia.
    bytes32 internal constant SEPOLIA_KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    function run() external returns (MockUSDC usdc, TrustRondaFactory factory) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address coordinator = vm.envOr("VRF_COORDINATOR", SEPOLIA_VRF_COORDINATOR);
        bytes32 keyHash = vm.envOr("VRF_KEY_HASH", SEPOLIA_KEY_HASH);
        uint256 subId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bool nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", false);

        vm.startBroadcast(pk);
        usdc = new MockUSDC();
        factory = new TrustRondaFactory(deployer, address(usdc), coordinator, keyHash, subId, nativePayment);
        // La factory es el único consumidor: pide los sorteos de todas las rondas
        IVRFCoordinatorV2Plus(coordinator).addConsumer(subId, address(factory));
        vm.stopBroadcast();

        console.log("Deployer          :", deployer);
        console.log("MockUSDC (tUSD)   :", address(usdc));
        console.log("TrustRondaFactory :", address(factory));
        console.log("VRF coordinator   :", coordinator);
        console.log("VRF subscription  :", subId);

        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "deployBlock", block.number);
        vm.serializeAddress(key, "deployer", deployer);
        vm.serializeAddress(key, "MockUSDC", address(usdc));
        vm.serializeAddress(key, "VRFCoordinator", coordinator);
        vm.serializeString(key, "VRFSubscriptionId", vm.toString(subId));
        string memory json = vm.serializeAddress(key, "TrustRondaFactory", address(factory));
        vm.writeJson(json, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
    }
}
