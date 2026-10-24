// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./utils/BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TrustRonda,
    RondaStatus,
    ZeroAddress,
    InvalidContribution,
    InvalidCollateral,
    InvalidMemberCount,
    InvalidDuration,
    InvalidStatus,
    AlreadyMember,
    NotMember,
    JoinWindowClosed,
    AlreadyPaid,
    RoundExpired,
    RoundStillOpen,
    NothingToWithdraw,
    NotAuthorizedToCancel,
    NotFactory,
    DrawStillPending
} from "../contracts/TrustRonda.sol";

/// @title TrustRondaTest
/// @notice Tests unitarios y de integración del flujo principal de TrustRonda.
contract TrustRondaTest is BaseTest {
    // Eventos redeclarados para vm.expectEmit
    event MemberJoined(address indexed member, uint8 indexed position, uint256 collateral);
    event RondaStarted(uint64 firstDeadline);
    event RondaFull(uint64 drawRequestedAt);
    event ContributionMade(address indexed member, uint8 indexed round, uint256 amount);
    event CollateralSlashed(address indexed member, uint8 indexed round, uint256 amount);
    event RoundClosed(uint8 indexed round, address indexed beneficiary, uint256 pot, uint8 defaults);
    event RondaCompleted();
    event RondaCancelled(address indexed by);
    event Withdrawn(address indexed account, uint256 payout, uint256 collateral);

    // ─────────────────────────────────────────────────────────────────────
    // Flujo principal completo (happy path)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Flujo de punta a punta: 3 miembros, 3 turnos, todos pagan, todos cobran y recuperan la garantía.
    function test_FullCycle_AllPay_EveryoneEndsEven() public {
        TrustRonda ronda = _createActiveRonda();
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Active));

        address[] memory order = ronda.getMembers(); // orden sorteado por VRF
        for (uint8 r; r < MEMBERS; ++r) {
            assertEq(ronda.currentBeneficiary(), order[r]);
            _contribute(ronda, alice);
            _contribute(ronda, bob);
            _contribute(ronda, carol);
            ronda.closeRound(); // cualquiera puede cerrar
        }

        assertEq(uint8(ronda.status()), uint8(RondaStatus.Completed));
        assertEq(ronda.currentRound(), MEMBERS);

        // Cada uno cobró un pozo de 300 y recupera su garantía de 100
        for (uint256 i; i < 3; ++i) {
            (uint256 payout, uint256 collateral) = ronda.withdrawable(order[i]);
            assertEq(payout, CONTRIBUTION * MEMBERS);
            assertEq(collateral, COLLATERAL);
            vm.prank(order[i]);
            ronda.withdraw();
            // empezó con 1.000, puso 100 de garantía + 3 x 100 de aportes, recuperó 300 + 100
            assertEq(usdc.balanceOf(order[i]), 1_000e6);
        }
        assertEq(usdc.balanceOf(address(ronda)), 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    // join
    // ─────────────────────────────────────────────────────────────────────

    function test_Join_RegistersMemberAndTakesCollateral() public {
        TrustRonda ronda = _createDefaultRonda();

        vm.startPrank(alice);
        usdc.approve(address(ronda), COLLATERAL);
        vm.expectEmit(true, true, false, true, address(ronda));
        emit MemberJoined(alice, 0, COLLATERAL);
        ronda.join();
        vm.stopPrank();

        TrustRonda.MemberInfo memory info = ronda.getMemberInfo(alice);
        assertTrue(info.isMember);
        assertEq(info.position, 0);
        assertEq(info.collateral, COLLATERAL);
        assertEq(ronda.memberCount(), 1);
        assertEq(usdc.balanceOf(address(ronda)), COLLATERAL);
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Open));
    }

    /// @notice El último inscripto completa el cupo: la ronda pasa a Drawing y se pide el sorteo a Chainlink VRF.
    function test_Join_LastMemberRequestsDraw() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);

        vm.startPrank(carol);
        usdc.approve(address(ronda), COLLATERAL);
        vm.expectEmit(false, false, false, true, address(ronda));
        emit RondaFull(uint64(block.timestamp));
        ronda.join();
        vm.stopPrank();

        assertEq(uint8(ronda.status()), uint8(RondaStatus.Drawing));
        assertEq(ronda.drawRequestedAt(), uint64(block.timestamp));
        assertEq(ronda.roundDeadline(), 0); // el turno no arranca hasta que llega el sorteo
        uint256 requestId = factory.drawRequestOf(address(ronda));
        assertGt(requestId, 0);
        assertEq(factory.drawRequests(requestId), address(ronda));
    }

    /// @notice Llega el número de VRF: se sortea el orden (permutación de los inscriptos) y arranca el turno 0.
    function test_FulfillDraw_ShufflesAndStarts() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);
        _join(ronda, carol);

        vm.expectEmit(false, false, false, true, address(ronda));
        emit RondaStarted(uint64(block.timestamp) + ROUND);
        _fulfill(ronda);

        assertEq(uint8(ronda.status()), uint8(RondaStatus.Active));
        assertEq(ronda.roundDeadline(), uint64(block.timestamp) + ROUND);
        address[] memory m = ronda.getMembers();
        assertEq(m.length, 3);
        // es una permutación: cada uno aparece una vez y su `position` coincide con su índice
        for (uint256 i; i < 3; ++i) {
            assertEq(ronda.getMemberInfo(m[i]).position, i);
        }
        assertTrue(m[0] != m[1] && m[1] != m[2] && m[0] != m[2]);
        assertEq(ronda.currentBeneficiary(), m[0]);
        assertEq(factory.drawRequests(factory.drawRequestOf(address(ronda))), address(0)); // pedido consumido
    }

    function test_RevertWhen_FulfillDrawNotFactory() public {
        TrustRonda ronda = _createDefaultRonda();
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(NotFactory.selector, outsider));
        ronda.fulfillDraw(123);
    }

    /// @notice Un sorteo que llega tarde (ronda ya cancelada por timeout) se ignora sin revertir.
    function test_FulfillDraw_IgnoredWhenNotDrawing() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);
        _join(ronda, carol);
        vm.warp(block.timestamp + ronda.DRAW_TIMEOUT() + 1);
        ronda.cancel();
        _fulfill(ronda); // no revierte
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Cancelled));
    }

    function test_RevertWhen_JoinTwice() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        vm.startPrank(alice);
        usdc.approve(address(ronda), COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(AlreadyMember.selector, alice));
        ronda.join();
        vm.stopPrank();
    }

    function test_RevertWhen_JoinFullRonda() public {
        TrustRonda ronda = _createActiveRonda();
        vm.startPrank(outsider);
        usdc.approve(address(ronda), COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, RondaStatus.Open, RondaStatus.Active));
        ronda.join();
        vm.stopPrank();
    }

    function test_RevertWhen_JoinAfterDeadline() public {
        TrustRonda ronda = _createDefaultRonda();
        vm.warp(ronda.joinDeadline() + 1);
        vm.startPrank(alice);
        usdc.approve(address(ronda), COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(JoinWindowClosed.selector, ronda.joinDeadline()));
        ronda.join();
        vm.stopPrank();
    }

    function test_RevertWhen_JoinWithoutApprove() public {
        TrustRonda ronda = _createDefaultRonda();
        vm.prank(alice);
        vm.expectRevert(); // ERC20InsufficientAllowance de OpenZeppelin
        ronda.join();
    }

    // ─────────────────────────────────────────────────────────────────────
    // contribute
    // ─────────────────────────────────────────────────────────────────────

    function test_Contribute_MarksPaymentAndEmits() public {
        TrustRonda ronda = _createActiveRonda();
        vm.startPrank(bob);
        usdc.approve(address(ronda), CONTRIBUTION);
        vm.expectEmit(true, true, false, true, address(ronda));
        emit ContributionMade(bob, 0, CONTRIBUTION);
        ronda.contribute();
        vm.stopPrank();

        assertTrue(ronda.hasPaid(0, bob));
        assertFalse(ronda.hasPaid(0, alice));
        assertEq(ronda.paidCount(), 1);
    }

    function test_RevertWhen_ContributeWhileDrawing() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);
        _join(ronda, carol);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, RondaStatus.Active, RondaStatus.Drawing));
        ronda.contribute();
    }

    function test_RevertWhen_ContributeBeforeStart() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, RondaStatus.Active, RondaStatus.Open));
        ronda.contribute();
    }

    function test_RevertWhen_ContributeNotMember() public {
        TrustRonda ronda = _createActiveRonda();
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(NotMember.selector, outsider));
        ronda.contribute();
    }

    function test_RevertWhen_ContributeTwice() public {
        TrustRonda ronda = _createActiveRonda();
        _contribute(ronda, alice);
        vm.startPrank(alice);
        usdc.approve(address(ronda), CONTRIBUTION);
        vm.expectRevert(abi.encodeWithSelector(AlreadyPaid.selector, alice, uint8(0)));
        ronda.contribute();
        vm.stopPrank();
    }

    function test_RevertWhen_ContributeAfterDeadline() public {
        TrustRonda ronda = _createActiveRonda();
        uint64 deadline = ronda.roundDeadline();
        vm.warp(deadline + 1);
        vm.startPrank(alice);
        usdc.approve(address(ronda), CONTRIBUTION);
        vm.expectRevert(abi.encodeWithSelector(RoundExpired.selector, deadline));
        ronda.contribute();
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    // closeRound
    // ─────────────────────────────────────────────────────────────────────

    function test_RevertWhen_CloseRoundEarlyWithMissingPayments() public {
        TrustRonda ronda = _createActiveRonda();
        _contribute(ronda, alice);
        _contribute(ronda, bob);
        vm.expectRevert(abi.encodeWithSelector(RoundStillOpen.selector, ronda.roundDeadline()));
        ronda.closeRound();
    }

    function test_RevertWhen_CloseRoundNotActive() public {
        TrustRonda ronda = _createDefaultRonda();
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, RondaStatus.Active, RondaStatus.Open));
        ronda.closeRound();
    }

    function test_CloseRound_AllPaid_CreditsBeneficiary() public {
        TrustRonda ronda = _createActiveRonda();
        _contribute(ronda, alice);
        _contribute(ronda, bob);
        _contribute(ronda, carol);

        address[] memory m = ronda.getMembers();
        vm.expectEmit(true, true, false, true, address(ronda));
        emit RoundClosed(0, m[0], CONTRIBUTION * 3, 0);
        vm.prank(outsider); // un tercero puede cerrar (rol de keeper)
        ronda.closeRound();

        (uint256 payout, uint256 collateral) = ronda.withdrawable(m[0]);
        assertEq(payout, CONTRIBUTION * 3);
        assertEq(collateral, 0); // la garantía recién se libera al final
        assertEq(ronda.currentRound(), 1);
        assertEq(ronda.paidCount(), 0);
        assertEq(ronda.currentBeneficiary(), m[1]);
        assertEq(ronda.roundDeadline(), uint64(block.timestamp) + ROUND);
    }

    /// @notice Si alguien no paga, al vencer el turno se ejecuta su garantía y el beneficiario cobra el pozo completo.
    function test_CloseRound_Default_SlashesCollateral() public {
        TrustRonda ronda = _createActiveRonda();
        address[] memory m = ronda.getMembers();
        _contribute(ronda, m[0]);
        _contribute(ronda, m[1]);
        // m[2] no paga
        vm.warp(ronda.roundDeadline() + 1);

        vm.expectEmit(true, true, false, true, address(ronda));
        emit CollateralSlashed(m[2], 0, CONTRIBUTION);
        vm.expectEmit(true, true, false, true, address(ronda));
        emit RoundClosed(0, m[0], CONTRIBUTION * 3, 1);
        ronda.closeRound();

        TrustRonda.MemberInfo memory info = ronda.getMemberInfo(m[2]);
        assertEq(info.collateral, COLLATERAL - CONTRIBUTION);
        assertEq(info.defaults, 1);
        (uint256 payout,) = ronda.withdrawable(m[0]);
        assertEq(payout, CONTRIBUTION * 3);
    }

    /// @notice Con la garantía agotada, el pozo sale más chico: se acredita solo lo que efectivamente entró.
    function test_CloseRound_DefaultWithoutCollateral_SmallerPot() public {
        TrustRonda ronda = _createActiveRonda();
        address[] memory m = ronda.getMembers();
        // Turno 0: m[2] no paga, pierde su garantía completa (100)
        _contribute(ronda, m[0]);
        _contribute(ronda, m[1]);
        vm.warp(ronda.roundDeadline() + 1);
        ronda.closeRound();

        // Turno 1: m[2] vuelve a no pagar y ya no tiene garantía
        _contribute(ronda, m[0]);
        _contribute(ronda, m[1]);
        vm.warp(ronda.roundDeadline() + 1);
        vm.expectEmit(true, true, false, true, address(ronda));
        emit RoundClosed(1, m[1], CONTRIBUTION * 2, 1);
        ronda.closeRound();

        assertEq(ronda.getMemberInfo(m[2]).defaults, 2);
        assertEq(ronda.getMemberInfo(m[2]).collateral, 0);
    }

    function test_CloseRound_NobodyPays_AllCollateralSlashed() public {
        TrustRonda ronda = _createActiveRonda();
        vm.warp(ronda.roundDeadline() + 1);
        ronda.closeRound();
        (uint256 payout,) = ronda.withdrawable(ronda.getMembers()[0]);
        assertEq(payout, COLLATERAL * 3);
    }

    function test_CloseRound_LastRoundCompletes() public {
        TrustRonda ronda = _createActiveRonda();
        for (uint8 r; r < MEMBERS - 1; ++r) {
            _contribute(ronda, alice);
            _contribute(ronda, bob);
            _contribute(ronda, carol);
            ronda.closeRound();
        }
        _contribute(ronda, alice);
        _contribute(ronda, bob);
        _contribute(ronda, carol);

        vm.expectEmit(false, false, false, false, address(ronda));
        emit RondaCompleted();
        ronda.closeRound();

        assertEq(uint8(ronda.status()), uint8(RondaStatus.Completed));
        assertEq(ronda.roundDeadline(), 0);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, RondaStatus.Active, RondaStatus.Completed));
        ronda.currentBeneficiary();
    }

    // ─────────────────────────────────────────────────────────────────────
    // cancel
    // ─────────────────────────────────────────────────────────────────────

    function test_Cancel_ByOrganizerDuringJoin_RefundsCollateral() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);

        vm.expectEmit(true, false, false, false, address(ronda));
        emit RondaCancelled(organizer);
        vm.prank(organizer);
        ronda.cancel();
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Cancelled));

        (, uint256 collateral) = ronda.withdrawable(alice);
        assertEq(collateral, COLLATERAL);
        vm.prank(alice);
        ronda.withdraw();
        assertEq(usdc.balanceOf(alice), 1_000e6);
    }

    function test_Cancel_ByAnyoneAfterJoinDeadline() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        vm.warp(ronda.joinDeadline() + 1);
        vm.prank(outsider);
        ronda.cancel();
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Cancelled));
    }

    function test_RevertWhen_CancelByOutsiderBeforeDeadline() public {
        TrustRonda ronda = _createDefaultRonda();
        uint64 deadline = ronda.joinDeadline(); // se lee antes del prank: si no, el prank lo consume este getter
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorizedToCancel.selector, outsider, deadline));
        ronda.cancel();
    }

    /// @notice Si Chainlink VRF no responde en DRAW_TIMEOUT, cualquiera cancela y todos recuperan la garantía.
    function test_Cancel_DrawTimeout_RefundsCollateral() public {
        TrustRonda ronda = _createDefaultRonda();
        _join(ronda, alice);
        _join(ronda, bob);
        _join(ronda, carol);
        uint64 availableAt = ronda.drawRequestedAt() + ronda.DRAW_TIMEOUT();

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(DrawStillPending.selector, availableAt));
        ronda.cancel();

        vm.warp(availableAt + 1);
        vm.prank(outsider);
        ronda.cancel();
        assertEq(uint8(ronda.status()), uint8(RondaStatus.Cancelled));
        vm.prank(carol);
        ronda.withdraw();
        assertEq(usdc.balanceOf(carol), 1_000e6);
    }

    function test_RevertWhen_CancelActiveRonda() public {
        TrustRonda ronda = _createActiveRonda();
        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, RondaStatus.Open, RondaStatus.Active));
        ronda.cancel();
    }

    // ─────────────────────────────────────────────────────────────────────
    // withdraw
    // ─────────────────────────────────────────────────────────────────────

    function test_Withdraw_PayoutDuringActiveRonda() public {
        TrustRonda ronda = _createActiveRonda();
        _contribute(ronda, alice);
        _contribute(ronda, bob);
        _contribute(ronda, carol);
        ronda.closeRound();
        address first = ronda.getMembers()[0];

        uint256 before = usdc.balanceOf(first);
        vm.expectEmit(true, false, false, true, address(ronda));
        emit Withdrawn(first, CONTRIBUTION * 3, 0);
        vm.prank(first);
        ronda.withdraw();
        assertEq(usdc.balanceOf(first), before + CONTRIBUTION * 3);

        // el segundo retiro revierte: el saldo se puso en cero antes de transferir (CEI)
        vm.prank(first);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector, first));
        ronda.withdraw();
    }

    function test_RevertWhen_WithdrawNothing() public {
        TrustRonda ronda = _createActiveRonda();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector, bob));
        ronda.withdraw();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Constructor (validaciones)
    // ─────────────────────────────────────────────────────────────────────

    function test_Constructor_SetsParameters() public {
        TrustRonda ronda = _createDefaultRonda();
        assertEq(address(ronda.token()), address(usdc));
        assertEq(ronda.organizer(), organizer);
        assertEq(address(ronda.factory()), address(factory));
        assertEq(ronda.contributionAmount(), CONTRIBUTION);
        assertEq(ronda.collateralAmount(), COLLATERAL);
        assertEq(ronda.maxMembers(), MEMBERS);
        assertEq(ronda.roundDuration(), ROUND);
        assertEq(ronda.joinDeadline(), uint64(block.timestamp) + JOIN_WINDOW);
        assertEq(ronda.fullPot(), CONTRIBUTION * MEMBERS);
    }

    function test_RevertWhen_ConstructorZeroOrganizer() public {
        vm.expectRevert(ZeroAddress.selector);
        new TrustRonda(address(0), IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, MEMBERS, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorZeroToken() public {
        vm.expectRevert(ZeroAddress.selector);
        new TrustRonda(organizer, IERC20(address(0)), CONTRIBUTION, COLLATERAL, MEMBERS, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorZeroContribution() public {
        vm.expectRevert(InvalidContribution.selector);
        new TrustRonda(organizer, IERC20(address(usdc)), 0, COLLATERAL, MEMBERS, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorCollateralTooLow() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidCollateral.selector, CONTRIBUTION - 1, CONTRIBUTION));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, CONTRIBUTION - 1, MEMBERS, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorCollateralOverflowsUint128() public {
        uint256 huge = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidCollateral.selector, huge, CONTRIBUTION));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, huge, MEMBERS, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorTooFewMembers() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidMemberCount.selector, uint8(1)));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, 1, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorTooManyMembers() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidMemberCount.selector, uint8(13)));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, 13, ROUND, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorRoundTooShort() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, uint64(1 minutes)));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, MEMBERS, 1 minutes, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorRoundTooLong() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, uint64(91 days)));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, MEMBERS, 91 days, JOIN_WINDOW);
    }

    function test_RevertWhen_ConstructorJoinWindowTooShort() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, uint64(1)));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, MEMBERS, ROUND, 1);
    }

    function test_RevertWhen_ConstructorJoinWindowTooLong() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, uint64(91 days)));
        new TrustRonda(organizer, IERC20(address(usdc)), CONTRIBUTION, COLLATERAL, MEMBERS, ROUND, 91 days);
    }
}
