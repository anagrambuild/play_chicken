// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {PlayChicken} from "../contracts/PlayChicken.sol";

import {ERC20Mock} from "./ERC20Mock.sol";

contract PlayChickenTest is Test {
    address public CHICKEN_POOL;
    address public MEME_TOKEN;
    address public OWNER;
    address public PROTOCOL;
    address public PLAYER1;
    address public PLAYER2;
    address public PLAYER3;
    PlayChicken public chickenPool;
    IERC20 public memeToken;
    uint256 public REWARD_AMOUNT;
    uint256 public DEPOSIT_AMOUNT;

    error InvalidInitialization();

    function setUp() public {
        // chicken pool
        CHICKEN_POOL = vm.addr(0x1);
        mockChickenPool(CHICKEN_POOL);
        chickenPool = PlayChicken(CHICKEN_POOL);

        // meme token
        MEME_TOKEN = vm.addr(0x2);
        mockMemeToken(MEME_TOKEN);
        memeToken = IERC20(MEME_TOKEN);

        // setup users
        OWNER = vm.addr(0x3);
        PROTOCOL = vm.addr(0x4);
        PLAYER1 = vm.addr(0x5);
        PLAYER2 = vm.addr(0x6);
        PLAYER3 = vm.addr(0x7);

        REWARD_AMOUNT = chickenPool.MINIMUM_REWARD_AMOUNT();
        DEPOSIT_AMOUNT = chickenPool.MINIMUM_DEPOSIT_AMOUNT();

        // setup roles
        chickenPool.grantRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL);

        // mint tokens
        ERC20Mock _token = ERC20Mock(MEME_TOKEN);
        _token.mint(PROTOCOL, 10 * REWARD_AMOUNT);
        _token.mint(PLAYER1, 10 * DEPOSIT_AMOUNT);
        _token.mint(PLAYER2, 10 * DEPOSIT_AMOUNT);
        _token.mint(PLAYER3, 10 * DEPOSIT_AMOUNT);
    }

    function testTokenBalanceAndRoleSetup() public view {
        assertTrue(chickenPool.hasRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL));
        assertEq(memeToken.balanceOf(address(this)), 0);
        assertEq(memeToken.balanceOf(PROTOCOL), 10 * REWARD_AMOUNT);
        assertEq(memeToken.balanceOf(PLAYER1), 10 * DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(PLAYER2), 10 * DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(PLAYER3), 10 * DEPOSIT_AMOUNT);
    }

    function testBPSis10000() public view {
        assertEq(chickenPool.BPS(), 10000);
    }

    function testDoubleInitializationFails() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        chickenPool.initialize(address(this));
    }

    function testStartRequiresBlockInFuture() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenMustStartInFuture.selector));
        chickenPool.start(MEME_TOKEN, block.number, block.number + 1, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testStartRequiresEndInFuture() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenStartAndEndMustBeDifferent.selector));
        chickenPool.start(CHICKEN_POOL, block.number + 2, block.number + 1, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testStartMustBeLessThanEnd() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenStartAndEndMustBeDifferent.selector));
        chickenPool.start(CHICKEN_POOL, block.number + 1, block.number + 1, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testMinimumRewardIs100Token() public view {
        assertEq(chickenPool.MINIMUM_REWARD_AMOUNT(), 100);
    }

    function testStartRequiresMinimumReward() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayChicken.ChickenRewardMustBeGreaterThanMinimum.selector, chickenPool.MINIMUM_REWARD_AMOUNT()
            )
        );
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, 0, 0);
    }

    function testMinimumDepositIs1Token() public view {
        assertEq(chickenPool.MINIMUM_DEPOSIT_AMOUNT(), 1);
    }

    function testStartRequiresMinimumDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayChicken.ChickenMinimumDepositMustBeLarger.selector, chickenPool.MINIMUM_DEPOSIT_AMOUNT()
            )
        );
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT - 1);
    }

    function testRewardIsIncludedInDeposit() public {
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayChicken.ChickenRewardAndProtocolFeeNotMet.selector,
                chickenPool.MINIMUM_REWARD_AMOUNT(),
                chickenPool.MINIMUM_DEPOSIT_AMOUNT()
            )
        );
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testProtocolFeeIsIncludedInDeposit() public {
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, REWARD_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayChicken.ChickenRewardAndProtocolFeeNotMet.selector,
                chickenPool.MINIMUM_REWARD_AMOUNT(),
                chickenPool.MINIMUM_DEPOSIT_AMOUNT()
            )
        );
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testStartChicken() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 1);
        (address token, uint256 start, uint256 end, uint256 rewardAmount, uint256 totalBalance, uint256 minimumDeposit,)
        = chickenPool.chickens(1);
        assertEq(token, MEME_TOKEN);
        assertEq(start, block.number + 1);
        assertEq(end, block.number + 2);
        assertEq(rewardAmount, REWARD_AMOUNT);
        assertEq(totalBalance, 0);
        assertEq(minimumDeposit, DEPOSIT_AMOUNT);
    }

    function testJoinInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        chickenPool.join(0, DEPOSIT_AMOUNT);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, maxcount));
        chickenPool.join(maxcount, DEPOSIT_AMOUNT);
    }

    function testJoinAfterStart() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        uint256 start = block.number + 1;
        uint256 end = block.number + 2;
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, start, end, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        vm.roll(start + 1);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenRunning.selector));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.roll(end + 1);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenRunning.selector));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testJoinRequiresMinimumDeposit() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayChicken.ChickenMinimumDepositNotMet.selector, chickenPool.MINIMUM_DEPOSIT_AMOUNT()
            )
        );
        chickenPool.join(1, DEPOSIT_AMOUNT - 1);
        vm.stopPrank();
    }

    function testJoinRequiresDepositApproval() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenDepositNotAuthorized.selector, DEPOSIT_AMOUNT));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testJoinDepositsTokens() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertEq(memeToken.balanceOf(PLAYER1), 10 * DEPOSIT_AMOUNT - DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(CHICKEN_POOL), requiredSpend + DEPOSIT_AMOUNT);
        (,,,, uint256 totalBalance,,) = chickenPool.chickens(1);
        assertEq(totalBalance, DEPOSIT_AMOUNT);
        assertEq(chickenPool.totalDeposits(1), DEPOSIT_AMOUNT);
        assertEq(chickenPool.balance(1, PLAYER1), DEPOSIT_AMOUNT);
    }

    function testClaimInvalidChickenId() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.claim(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PLAYER1);
        chickenPool.claim(maxcount);
    }

    function testClaimWithoutHavingJoined() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.roll(block.number + 3);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.PlayerIsNotInChickenPool.selector, PLAYER1));
        vm.prank(PLAYER1);
        chickenPool.claim(1);
    }

    function testClaimBeforeEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenNotFinished.selector));
        chickenPool.claim(1);
        vm.stopPrank();
    }

    function testLastRemainingPlayerPermittedToClaimPriorToEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.roll(block.number + 1);
        chickenPool.claim(1);
        vm.stopPrank();
        uint256 balance = memeToken.balanceOf(PLAYER1);
        assertEq(balance, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT);
    }

    function testClaimIsDistributedAsWeightedAveragePortionOfReward() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, 2 * DEPOSIT_AMOUNT);
        chickenPool.join(1, 2 * DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(PLAYER3);
        memeToken.approve(CHICKEN_POOL, 3 * DEPOSIT_AMOUNT);
        chickenPool.join(1, 3 * DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.prank(PLAYER1);
        chickenPool.claim(1);
        vm.prank(PLAYER2);
        chickenPool.claim(1);
        vm.prank(PLAYER3);
        chickenPool.claim(1);
        uint256 balance1 = memeToken.balanceOf(PLAYER1);
        uint256 balance2 = memeToken.balanceOf(PLAYER2);
        uint256 balance3 = memeToken.balanceOf(PLAYER3);
        assertEq(balance1, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 6);
        assertEq(balance2, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 3);
        assertEq(balance3, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 2);
    }

    function testWithdrawInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.withdraw(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PLAYER1);
        chickenPool.withdraw(maxcount);
    }

    function testWithdrawAfterEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenFinished.selector));
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
    }

    function testWithdrawNonPlayer() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.PlayerIsNotInChickenPool.selector, PLAYER2));
        vm.prank(PLAYER2);
        chickenPool.withdraw(1);
    }

    function testWithdrawal() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
        assertEq(memeToken.balanceOf(PLAYER1), 10 * DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(CHICKEN_POOL), requiredSpend);
        (,,,, uint256 totalBalance,,) = chickenPool.chickens(1);
        assertEq(totalBalance, 0);
        assertEq(chickenPool.totalDeposits(1), 0);
        assertEq(chickenPool.balance(1, PLAYER1), 0);
    }

    function testProtocolWithdrawProtocolFee() public {
        uint256 expectProtocolFee = REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        uint256 requiredSpend = REWARD_AMOUNT + expectProtocolFee;
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        assertTrue(chickenPool.hasRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(1);
        assertEq(memeToken.balanceOf(PROTOCOL), 10 * REWARD_AMOUNT - requiredSpend + expectProtocolFee);
    }

    function testProtocolWithdrawNotAuthorized() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PROTOCOL_ROLE()
            )
        );
        chickenPool.withdrawProtocolFee(1);
    }

    function testWithdrawProtocolFeeInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(maxcount);
    }

    function testBalanceInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.balance(0, PLAYER1);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PLAYER1);
        chickenPool.balance(maxcount, PLAYER1);
    }

    function testBalanceNonPlayer() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.prank(PLAYER2);
        assertEq(chickenPool.balance(1), 0);
    }

    function testBalance() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertEq(chickenPool.balance(1, PLAYER1), DEPOSIT_AMOUNT);
    }

    function testTotalDepositsInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, 0));
        chickenPool.totalDeposits(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.ChickenIdInvalid.selector, maxcount));
        chickenPool.totalDeposits(maxcount);
    }

    function testTotalDeposits() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.totalDeposits(1), 0);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertEq(chickenPool.totalDeposits(1), DEPOSIT_AMOUNT);
    }

    function testChickenCount() public {
        assertEq(chickenPool.chickenCount(), 0);
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT * chickenPool.protocolFee() / chickenPool.BPS();
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 1);
    }

    function testSetProtocolFee() public {
        assertEq(chickenPool.protocolFee(), 100);
        vm.prank(PROTOCOL);
        chickenPool.setProtocolFee(200);
        assertEq(chickenPool.protocolFee(), 200);
    }

    function testSetProtocolFeeRequiresProtocol() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PROTOCOL_ROLE()
            )
        );
        chickenPool.setProtocolFee(2000);
    }

    function mockChickenPool(address _chickenPool) internal {
        PlayChicken implementation = new PlayChicken();
        bytes memory code = address(implementation).code;
        vm.etch(_chickenPool, code);
        PlayChicken(_chickenPool).initialize(address(this));
    }

    function mockMemeToken(address _memeToken) internal {
        ERC20Mock tokenImpl = new ERC20Mock("MemeToken", "MEME");
        bytes memory code = address(tokenImpl).code;
        vm.etch(_memeToken, code);
    }
}
