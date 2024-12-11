// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable var-name-mixedcase

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Test} from "forge-std/Test.sol";

import {PlayChicken} from "../contracts/PlayChicken.sol";

import {ERC20Mock} from "./ERC20Mock.sol";

contract PlayChickenTest is Test {
    uint256 public constant MAX_SUPPLY = 1000000 * 10 ** 18;

    // these are used as constants but initialized in setUp
    address public CHICKEN_POOL;
    address public MEME_TOKEN;
    address public OWNER;
    address public PAUSER;
    address public PROTOCOL;
    address public PLAYER1;
    address public PLAYER2;
    address public PLAYER3;
    uint256 public BUY_IN_AMOUNT;
    uint256 public SLASHING_PERCENT;

    PlayChicken public chickenPool;
    IERC20 public memeToken;

    error InvalidInitialization();

    function setUp() public {
        // chicken pool mocking
        CHICKEN_POOL = vm.addr(0x1);
        // meme token
        MEME_TOKEN = vm.addr(0x2);
        // setup users
        OWNER = vm.addr(0x3);
        PROTOCOL = vm.addr(0x4);
        PLAYER1 = vm.addr(0x5);
        PLAYER2 = vm.addr(0x6);
        PLAYER3 = vm.addr(0x7);
        PAUSER = vm.addr(0x8);

        mockChickenPool(CHICKEN_POOL);
        chickenPool = PlayChicken(CHICKEN_POOL);

        mockMemeToken(MEME_TOKEN);
        memeToken = IERC20(MEME_TOKEN);

        // helpful constants
        BUY_IN_AMOUNT = chickenPool.MINIMUM_BUY_IN();
        SLASHING_PERCENT = 2500; // 25%

        // setup roles
        vm.startPrank(OWNER);
        chickenPool.grantRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL);
        chickenPool.revokeRole(chickenPool.PAUSER_ROLE(), OWNER);
        chickenPool.grantRole(chickenPool.PAUSER_ROLE(), PAUSER);

        vm.stopPrank();

        // mint tokens
        ERC20Mock _token = ERC20Mock(MEME_TOKEN);
        _token.mint(PLAYER1, 10 * BUY_IN_AMOUNT);
        _token.mint(PLAYER2, 10 * BUY_IN_AMOUNT);
        _token.mint(PLAYER3, 10 * BUY_IN_AMOUNT);
    }

    function testInitialize() public view {
        assertEq(chickenPool.hasRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL), true);
        assertEq(chickenPool.hasRole(chickenPool.DEFAULT_ADMIN_ROLE(), OWNER), true);
        assertEq(chickenPool.hasRole(chickenPool.PAUSER_ROLE(), PAUSER), true);

        // owner can not pause
        assertEq(chickenPool.hasRole(chickenPool.PAUSER_ROLE(), OWNER), false);
        // protocol is not the caller
        assertEq(chickenPool.hasRole(chickenPool.PROTOCOL_ROLE(), address(this)), false);
        // admin is not the caller
        assertEq(chickenPool.hasRole(chickenPool.DEFAULT_ADMIN_ROLE(), address(this)), false);
        // pauser is not the caller
        assertEq(chickenPool.hasRole(chickenPool.PAUSER_ROLE(), address(this)), false);
    }

    function testStart() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        (
            address token,
            uint256 buyIn,
            uint256 slashingPercent,
            uint256 totalDeposits,
            uint256 rewardQuantity,
            uint256 protocolFee,
            PlayChicken.ChickenState state
        ) = chickenPool.chickens(1);

        // check the chicken pool state
        assertEq(token, MEME_TOKEN);
        assertEq(buyIn, BUY_IN_AMOUNT);
        assertEq(slashingPercent, SLASHING_PERCENT);
        assertEq(totalDeposits, 0);
        assertEq(rewardQuantity, 0);
        assertEq(protocolFee, 0);
        assertTrue(state == PlayChicken.ChickenState.WAITING);
    }

    function testStartWithTwoJoiners() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        (,,,,,, PlayChicken.ChickenState state) = chickenPool.chickens(1);

        // check the chicken pool state
        assertTrue(state == PlayChicken.ChickenState.RUNNING);
    }

    function testStartWithInvalidToken() public {
        // create a new chicken pool with invalid token
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.TokenInvalid.selector));
        chickenPool.start(address(0), BUY_IN_AMOUNT, SLASHING_PERCENT);
    }

    function testStartBuyInTooLow() public {
        // create a new chicken pool with invalid token
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.MinimumBuyInRequired.selector));
        chickenPool.start(MEME_TOKEN, 0, SLASHING_PERCENT);
    }

    function testStartSlashingPercentTooLow() public {
        // create a new chicken pool with invalid token
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.MinimumSlashingPercentRequired.selector));
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, 0);
    }

    function testStartJoinBalance() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();

        // check the balance of the chicken pool
        assertEq(chickenPool.totalDeposits(1), 2 * BUY_IN_AMOUNT - 2 * protocolFee);
    }

    function testStartThenLeaveIsFinished() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // leave the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        (,,,,,, PlayChicken.ChickenState state) = chickenPool.chickens(1);

        // check the chicken pool state
        assertTrue(state == PlayChicken.ChickenState.FINISHED);
    }

    function testStartJoinThenLeaveThenTryToJoinOnFinished() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // leave the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // try to join the chicken pool again
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenFinished.selector));
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
    }

    function testJoinInsufficientBuyIn() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);

        // try to join the chicken pool with insufficient buy in
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.InsufficientBuyIn.selector));
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT / 2);
    }

    function testJoinDepositNotAuthorized() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // try to join the chicken pool without approving the deposit
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.DepositNotAuthorized.selector, BUY_IN_AMOUNT));
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
    }

    function testJoinProtocolFeeCollected() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        (,,,,, uint256 feeCollected,) = chickenPool.chickens(1);

        // check the balance of the chicken pool
        assertEq(feeCollected, 2 * protocolFee);
    }

    function testJoinPlayerIsInPool() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        assertTrue(chickenPool.isPlayer(1, PLAYER1));
        assertTrue(chickenPool.isPlayer(1, PLAYER2));
        assertEq(chickenPool.getPlayerCount(1), 2);
    }

    function testOkayForSamePlayerToJoinTwice() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        assertEq(chickenPool.getPlayerCount(1), 1);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        assertEq(chickenPool.balance(1, PLAYER1), 2 * BUY_IN_AMOUNT - 2 * protocolFee);
    }

    function testWithdrawAfterStart() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        uint256 playerBalance = BUY_IN_AMOUNT - protocolFee;
        uint256 amountSlashed = playerBalance * SLASHING_PERCENT / chickenPool.BPS();

        assertEq(memeToken.balanceOf(PLAYER1), 10 * BUY_IN_AMOUNT - protocolFee - amountSlashed);
    }

    function testLastPlayerIsWinnerWithdrawRevert() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // try to withdraw from the chicken pool
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenFinished.selector));
        vm.prank(PLAYER2);
        chickenPool.withdraw(1);
    }

    function testFirstPlayerCanNotWithdraw() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // try withdraw from the chicken pool
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.WaitForGameStart.selector));
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
    }

    function testWinnerClaim() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // claim the reward
        vm.prank(PLAYER2);
        chickenPool.claim(1);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        uint256 playerBalance = BUY_IN_AMOUNT - protocolFee;
        uint256 amountSlashed = playerBalance * SLASHING_PERCENT / chickenPool.BPS();

        assertEq(memeToken.balanceOf(PLAYER2), 10 * BUY_IN_AMOUNT - protocolFee + amountSlashed);
    }

    function testWithdrawNotInGame() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // try to withdraw from the chicken pool without being in the game
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.PlayerIsNotInChickenPool.selector, PLAYER3));
        vm.prank(PLAYER3);
        chickenPool.withdraw(1);
    }

    function testClaimNotInGame() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // try to claim from the chicken pool without being in the game
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.PlayerIsNotInChickenPool.selector, PLAYER3));
        vm.prank(PLAYER3);
        chickenPool.claim(1);
    }

    function testJoinWhenGameIsFinished() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // try to join the chicken pool again
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenFinished.selector));
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
    }

    function testDoubleClaim() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // claim the reward
        vm.prank(PLAYER2);
        chickenPool.claim(1);

        // try to claim the reward again
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.PlayerIsNotInChickenPool.selector, PLAYER2));
        vm.prank(PLAYER2);
        chickenPool.claim(1);
    }

    function testDoubleWithdraw() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // try to withdraw again
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenFinished.selector));
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
    }

    function testClaimFailsWhenNotOver() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // try to claim the reward
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenNotFinished.selector));
        vm.prank(PLAYER1);
        chickenPool.claim(1);
    }

    function testStartRevertWhenPaused() public {
        // pause the chicken pool
        vm.prank(PAUSER);
        chickenPool.pause();

        // try to start a new chicken pool
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);
    }

    function testJoinRevertWhenPaused() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // pause the chicken pool
        vm.prank(PAUSER);
        chickenPool.pause();

        // try to join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        chickenPool.join(1, BUY_IN_AMOUNT);
    }

    function testWithdrawRevertWhenPaused() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // pause the chicken pool
        vm.prank(PAUSER);
        chickenPool.pause();

        // try to withdraw from the chicken pool
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
    }

    function testClaimRevertWhenPaused() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from the chicken pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // pause the chicken pool
        vm.prank(PAUSER);
        chickenPool.pause();

        // try to claim the reward
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(PLAYER2);
        chickenPool.claim(1);
    }

    function testWithdrawProtocolFeeRevertWhenPaused() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // pause the chicken pool
        vm.prank(PAUSER);
        chickenPool.pause();

        // try to withdraw the protocol fee
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(1);
    }

    function testWithdrawProtocolFeeRequiresProtocolRole() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PROTOCOL_ROLE()
            )
        );
        chickenPool.withdrawProtocolFee(1);
    }

    function testPauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PAUSER_ROLE()
            )
        );
        chickenPool.pause();
    }

    function testPauseNotPossibleByOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, chickenPool.PAUSER_ROLE())
        );
        vm.prank(OWNER);
        chickenPool.pause();
    }

    function testUnpauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PAUSER_ROLE()
            )
        );
        chickenPool.unpause();
    }

    function testProtocolFeeIsOnePercent() public view {
        assertEq(chickenPool.protocolFeeBps(), 100);
    }

    function testBPSis10000() public view {
        assertEq(chickenPool.BPS(), 10000);
    }

    function testJoinWithInvalidChickenId() public {
        // try to join a chicken pool with invalid chicken id
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.join(0, BUY_IN_AMOUNT);
    }

    function testWithdrawWithInvalidChickenId() public {
        // try to withdraw from a chicken pool with invalid chicken id
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.withdraw(0);
    }

    function testClaimWithInvalidChickenId() public {
        // try to claim from a chicken pool with invalid chicken id
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.claim(0);
    }

    function testWithdrawProtocolFeeWithInvalidChickenId() public {
        // try to withdraw protocol fee from a chicken pool with invalid chicken id
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(0);
    }

    function testWithdrawProtocolFee() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // withdraw the protocol fee
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(1);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        assertEq(memeToken.balanceOf(PROTOCOL), 2 * protocolFee);
    }

    // withdraw protocol fee prior to finishing the pool will revert
    function testWithdrawProtocolFeeBeforeGameEnd() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // try to withdraw the protocol fee before the game ends
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenNotFinished.selector));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(1);
    }

    function testWithdrawProtocolFeeTwice() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        // withdraw from pool
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);

        // withdraw the protocol fee
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(1);

        // try to withdraw the protocol fee again
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.InsufficientFunds.selector));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(1);
    }

    function testPlayerBalance() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);

        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        uint256 playerBalance = BUY_IN_AMOUNT - protocolFee;

        assertEq(chickenPool.balance(1, PLAYER1), playerBalance);
        assertEq(chickenPool.balance(1, PLAYER2), playerBalance);
    }

    function testSetProtocolFee() public {
        assertEq(chickenPool.protocolFeeBps(), 100);
        vm.prank(PROTOCOL);
        chickenPool.setProtocolFee(200);
        assertEq(chickenPool.protocolFeeBps(), 200);
    }

    function testSetProtocolFeeRequiresProtocol() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PROTOCOL_ROLE()
            )
        );
        chickenPool.setProtocolFee(2000);
    }

    function testGetProtocolFeeBalance() public {
        // start a new chicken pool
        chickenPool.start(MEME_TOKEN, BUY_IN_AMOUNT, SLASHING_PERCENT);
        // join the chicken pool
        vm.prank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER1);
        chickenPool.join(1, BUY_IN_AMOUNT);

        vm.prank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, 2 * BUY_IN_AMOUNT);
        vm.prank(PLAYER2);
        chickenPool.join(1, BUY_IN_AMOUNT);

        uint256 protocolFee = BUY_IN_AMOUNT * chickenPool.protocolFeeBps() / chickenPool.BPS();
        assertEq(chickenPool.getProtocolFeeBalance(1), 2 * protocolFee);
    }

    function mockChickenPool(address _chickenPool) internal {
        PlayChicken implementation = new PlayChicken();
        bytes memory code = address(implementation).code;
        vm.etch(_chickenPool, code);
        PlayChicken(_chickenPool).initialize(OWNER);
    }

    function mockMemeToken(address _memeToken) internal {
        ERC20Mock tokenImpl = new ERC20Mock("MemeToken", "MEME", MAX_SUPPLY);
        bytes memory code = address(tokenImpl).code;
        vm.etch(_memeToken, code);
    }
}
