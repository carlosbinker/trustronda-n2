// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../utils/BaseTest.sol";
import {console} from "forge-std/console.sol";
import {TrustRonda, RondaStatus} from "../../contracts/TrustRonda.sol";
import {TrustRondaHandler} from "./TrustRondaHandler.sol";

/// @title TrustRondaInvariantTest
/// @notice Invariantes que deben valer después de CUALQUIER secuencia de join/contribute/closeRound/withdraw/cancel.
/// @dev Se evitan invariantes triviales ("balance >= 0"): la de solvencia compara la contabilidad interna con el
///      saldo real del token, dos magnitudes que se desalinearían ante cualquier bug de contabilidad.
contract TrustRondaInvariantTest is BaseTest {
    TrustRonda internal ronda;
    TrustRondaHandler internal handler;
    address[] internal actors;

    function setUp() public override {
        super.setUp();
        ronda = _createDefaultRonda();
        actors.push(alice);
        actors.push(bob);
        actors.push(carol);
        actors.push(outsider);
        for (uint256 i; i < actors.length; ++i) {
            deal(address(usdc), actors[i], 10_000e6);
        }
        handler = new TrustRondaHandler(ronda, usdc, actors);
        targetContract(address(handler));
    }

    /// @notice Solvencia exacta: el saldo de tUSD del contrato es igual a lo que debe
    ///         (pozos acreditados + garantías + aportes del turno abierto).
    function invariant_SolvencyExact() public view {
        uint256 owed;
        address[] memory members = ronda.getMembers();
        for (uint256 i; i < members.length; ++i) {
            (uint256 payout,) = ronda.withdrawable(members[i]);
            owed += payout + ronda.getMemberInfo(members[i]).collateral;
        }
        if (ronda.status() == RondaStatus.Active) {
            owed += uint256(ronda.paidCount()) * ronda.contributionAmount();
        }
        assertEq(usdc.balanceOf(address(ronda)), owed);
    }

    /// @notice El cupo nunca se excede.
    function invariant_MembersNeverExceedCap() public view {
        assertLe(ronda.memberCount(), ronda.maxMembers());
    }

    /// @notice El turno en curso nunca pasa la cantidad de miembros, y Completed implica que se jugaron todos.
    function invariant_RoundBounds() public view {
        assertLe(ronda.currentRound(), ronda.maxMembers());
        assertLe(ronda.paidCount(), ronda.maxMembers());
        if (ronda.status() == RondaStatus.Completed) assertEq(ronda.currentRound(), ronda.maxMembers());
    }

    /// @notice La garantía de un miembro nunca supera la que depositó.
    function invariant_CollateralNeverGrows() public view {
        address[] memory members = ronda.getMembers();
        for (uint256 i; i < members.length; ++i) {
            assertLe(ronda.getMemberInfo(members[i]).collateral, ronda.collateralAmount());
        }
    }

    /// @notice Al final de cada corrida, imprime cuántas veces se ejecutó cada acción (con -vv),
    ///         para confirmar que el fuzzer recorrió el flujo completo y no solo llamadas vacías.
    function afterInvariant() external view {
        console.log("join", handler.calls("join"), "contribute", handler.calls("contribute"));
        console.log("closeRound", handler.calls("closeRound"), "withdraw", handler.calls("withdraw"));
        console.log("cancel", handler.calls("cancel"));
    }
}
