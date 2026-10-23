// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./utils/BaseTest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TrustRonda, InvalidMemberCount} from "../contracts/TrustRonda.sol";
import {TrustRondaFactory, TokenNotAllowed, ZeroTokenAddress} from "../contracts/TrustRondaFactory.sol";

/// @title TrustRondaFactoryTest
/// @notice Tests de la factory: creación de rondas (interacción entre contratos), registro y lista blanca.
contract TrustRondaFactoryTest is BaseTest {
    event TokenAllowed(address indexed token, bool allowed);

    function test_Constructor_AllowsInitialToken() public view {
        assertEq(factory.owner(), owner);
        assertTrue(factory.isTokenAllowed(address(usdc)));
    }

    function test_Constructor_WithoutInitialToken() public {
        TrustRondaFactory f = new TrustRondaFactory(owner, address(0));
        assertFalse(f.isTokenAllowed(address(0)));
    }

    function test_CreateRonda_DeploysAndRegisters() public {
        vm.expectEmit(false, true, true, false, address(factory)); // la dirección de la ronda no se conoce antes
        emit TrustRondaFactory.RondaCreated(address(0), organizer, address(usdc), 0, 0, 0, 0, 0);
        TrustRonda ronda = _createDefaultRonda();

        assertEq(factory.rondasCount(), 1);
        assertTrue(factory.isRonda(address(ronda)));
        assertEq(ronda.organizer(), organizer); // el organizador es quien llamó a la factory, no la factory
        address[] memory page = factory.getRondas(0, 10);
        assertEq(page.length, 1);
        assertEq(page[0], address(ronda));
    }

    function test_RevertWhen_CreateRondaWithTokenNotAllowed() public {
        address fake = makeAddr("fakeToken");
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, fake));
        factory.createRonda(fake, CONTRIBUTION, COLLATERAL, MEMBERS, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_CreateRondaWithInvalidParams() public {
        // la validación vive en el constructor de TrustRonda y revierte toda la transacción
        vm.expectRevert(abi.encodeWithSelector(InvalidMemberCount.selector, uint8(20)));
        factory.createRonda(address(usdc), CONTRIBUTION, COLLATERAL, 20, ROUND, JOIN_WINDOW);
        assertEq(factory.rondasCount(), 0);
    }

    function test_SetTokenAllowed_ByOwner() public {
        address other = makeAddr("otherToken");
        vm.expectEmit(true, false, false, true, address(factory));
        emit TokenAllowed(other, true);
        vm.prank(owner);
        factory.setTokenAllowed(other, true);
        assertTrue(factory.isTokenAllowed(other));

        vm.prank(owner);
        factory.setTokenAllowed(other, false);
        assertFalse(factory.isTokenAllowed(other));
    }

    function test_RevertWhen_SetTokenAllowedByNonOwner() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        factory.setTokenAllowed(address(usdc), false);
    }

    function test_RevertWhen_SetTokenAllowedZero() public {
        vm.prank(owner);
        vm.expectRevert(ZeroTokenAddress.selector);
        factory.setTokenAllowed(address(0), true);
    }

    function test_DisallowedToken_DoesNotAffectExistingRondas() public {
        TrustRonda ronda = _createDefaultRonda();
        vm.prank(owner);
        factory.setTokenAllowed(address(usdc), false);
        _join(ronda, alice); // la ronda existente sigue funcionando
        assertEq(ronda.memberCount(), 1);
    }

    function test_GetRondas_Pagination() public {
        for (uint256 i; i < 5; ++i) {
            _createDefaultRonda();
        }
        assertEq(factory.getRondas(0, 2).length, 2);
        assertEq(factory.getRondas(4, 10).length, 1);
        assertEq(factory.getRondas(5, 10).length, 0);
        assertEq(factory.getRondas(2, type(uint256).max).length, 3); // sin overflow
        assertEq(factory.getRondas(1, 2)[1], factory.getRondas(2, 1)[0]);
    }
}
