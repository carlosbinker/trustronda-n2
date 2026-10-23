// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC (tUSD)
/// @author Carlos Binker
/// @notice Stablecoin de prueba de 6 decimales, como USDC, con un faucet público y limitado.
///         Solo existe para que cualquiera pueda probar TrustRonda en testnet sin depender de un faucet externo.
/// @dev No tiene owner ni roles: la única forma de emitir tokens es `faucet()`, con cooldown por cuenta.
///      NO usar en mainnet: el suministro no está respaldado.
contract MockUSDC is ERC20 {
    /// @notice Cantidad que entrega cada llamada a `faucet()`: 1.000 tUSD (6 decimales).
    uint256 public constant FAUCET_AMOUNT = 1_000e6;

    /// @notice Tiempo mínimo entre dos llamadas a `faucet()` desde la misma cuenta.
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    /// @notice Último timestamp en que cada cuenta usó el faucet.
    /// @dev 0 significa que la cuenta nunca lo usó.
    mapping(address account => uint256 timestamp) public lastFaucetClaim;

    /// @notice Se emite cada vez que una cuenta recibe tokens del faucet.
    /// @param to Cuenta que recibió los tokens.
    /// @param amount Cantidad emitida (con 6 decimales).
    event FaucetClaimed(address indexed to, uint256 amount);

    /// @notice La cuenta todavía está dentro del cooldown del faucet.
    /// @param availableAt Timestamp a partir del cual puede volver a pedir.
    error FaucetCooldown(uint256 availableAt);

    /// @notice Despliega el token con nombre "Test USD" y símbolo "tUSD".
    constructor() ERC20("Test USD", "tUSD") {}

    /// @notice Entrega `FAUCET_AMOUNT` tUSD a quien llama, como máximo una vez por `FAUCET_COOLDOWN`.
    /// @dev CEI: primero chequea el cooldown, después actualiza `lastFaucetClaim` y recién al final emite.
    ///      `_mint` no hace llamadas externas, así que no hay riesgo de reentrancy.
    function faucet() external {
        uint256 last = lastFaucetClaim[msg.sender];
        if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) {
            revert FaucetCooldown(last + FAUCET_COOLDOWN);
        }
        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Devuelve los decimales del token: 6, igual que USDC.
    /// @return Cantidad de decimales.
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
