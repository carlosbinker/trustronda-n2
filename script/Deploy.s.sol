// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../contracts/MockUSDC.sol";
import {TrustRondaFactory} from "../contracts/TrustRondaFactory.sol";

/// @title Deploy
/// @notice Despliega MockUSDC (tUSD) y TrustRondaFactory, con tUSD ya habilitado, y guarda las direcciones en
///         deployments/<chainId>.json para que las usen el script de demo y el frontend.
/// @dev Uso (Sepolia, con verificación en Etherscan):
///      forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
contract Deploy is Script {
    function run() external returns (MockUSDC usdc, TrustRondaFactory factory) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        usdc = new MockUSDC();
        factory = new TrustRondaFactory(deployer, address(usdc));
        vm.stopBroadcast();

        console.log("Deployer          :", deployer);
        console.log("MockUSDC (tUSD)   :", address(usdc));
        console.log("TrustRondaFactory :", address(factory));

        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "deployBlock", block.number);
        vm.serializeAddress(key, "deployer", deployer);
        vm.serializeAddress(key, "MockUSDC", address(usdc));
        string memory json = vm.serializeAddress(key, "TrustRondaFactory", address(factory));
        vm.writeJson(json, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
    }
}
