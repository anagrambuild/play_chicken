// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable var-name-mixedcase

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Test} from "forge-std/Test.sol";

import {RewardChicken} from "../contracts/RewardChicken.sol";
import {TokenMath} from "../contracts/TokenMath.sol";

import {ERC20Mock} from "./ERC20Mock.sol";

contract RewardChickenTest is Test {
    using TokenMath for uint256;

    uint256 public constant MAX_SUPPLY = 1000000 * TokenMath.TOKEN_BASE_QTY;

    // these are used as constants but initialized in setUp
    address public CHICKEN_POOL;
    address public MEME_TOKEN;
    address public OWNER;
    address public PAUSER;
    address public PROTOCOL;
    address public PLAYER1;
    address public PLAYER2;
    address public PLAYER3;
    uint256 public REWARD_AMOUNT;
    uint256 public DEPOSIT_AMOUNT;

    RewardChicken public chickenPool;
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
        chickenPool = RewardChicken(CHICKEN_POOL);

        mockMemeToken(MEME_TOKEN);
        memeToken = IERC20(MEME_TOKEN);

        // helpful constants
        REWARD_AMOUNT = chickenPool.MINIMUM_REWARD_AMOUNT();
        DEPOSIT_AMOUNT = chickenPool.MINIMUM_DEPOSIT_AMOUNT();

        assertTrue(1000 * REWARD_AMOUNT < MAX_SUPPLY);
        assertTrue(100 * DEPOSIT_AMOUNT < MAX_SUPPLY);

        // setup roles
        vm.startPrank(OWNER);
        chickenPool.grantRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL);
        chickenPool.revokeRole(chickenPool.PAUSER_ROLE(), OWNER);
        chickenPool.grantRole(chickenPool.PAUSER_ROLE(), PAUSER);

        vm.stopPrank();

        // mint tokens
        ERC20Mock _token = ERC20Mock(MEME_TOKEN);
        _token.mint(PROTOCOL, 10 * REWARD_AMOUNT);
        _token.mint(PLAYER1, 10 * DEPOSIT_AMOUNT);
        _token.mint(PLAYER2, 10 * DEPOSIT_AMOUNT);
        _token.mint(PLAYER3, 10 * DEPOSIT_AMOUNT);
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

    function testTokenBalanceAndRoleSetup() public view {
        assertTrue(chickenPool.hasRole(chickenPool.PROTOCOL_ROLE(), PROTOCOL));
        assertEq(memeToken.balanceOf(address(this)), 0);
        assertEq(memeToken.balanceOf(PROTOCOL), 10 * REWARD_AMOUNT);
        assertEq(memeToken.balanceOf(PLAYER1), 10 * DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(PLAYER2), 10 * DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(PLAYER3), 10 * DEPOSIT_AMOUNT);
    }

    function testDoubleInitializationFails() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        chickenPool.initialize(address(this));
    }

    function testStartRequiresBlockInFuture() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.MustStartInFuture.selector));
        chickenPool.start(MEME_TOKEN, block.number, block.number + 1, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testStartRequiresEndInFuture() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.StartAndEndMustBeDifferent.selector));
        chickenPool.start(CHICKEN_POOL, block.number + 2, block.number + 1, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testStartMustBeLessThanEnd() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.StartAndEndMustBeDifferent.selector));
        chickenPool.start(CHICKEN_POOL, block.number + 1, block.number + 1, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testMinimumRewardIs100Token() public view {
        assertEq(chickenPool.MINIMUM_REWARD_AMOUNT(), uint256(100).tokens());
    }

    function testStartRequiresMinimumReward() public {
        vm.expectRevert(
            abi.encodeWithSelector(RewardChicken.RewardMustBeGreaterThanMinimum.selector, chickenPool.MINIMUM_REWARD_AMOUNT())
        );
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, 0, 0);
    }

    function testMinimumDepositIs1Token() public view {
        assertEq(chickenPool.MINIMUM_DEPOSIT_AMOUNT(), uint256(1).tokens());
    }

    function testStartRequiresMinimumDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(RewardChicken.MinimumDepositMustBeLarger.selector, chickenPool.MINIMUM_DEPOSIT_AMOUNT())
        );
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT - 1);
    }

    function testRewardIsIncludedInDeposit() public {
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardChicken.RewardAndProtocolFeeNotMet.selector,
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
                RewardChicken.RewardAndProtocolFeeNotMet.selector,
                chickenPool.MINIMUM_REWARD_AMOUNT(),
                chickenPool.MINIMUM_DEPOSIT_AMOUNT()
            )
        );
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function testStartChicken() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.startPrank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertEq(chickenPool.chickenCount(), 1);
        (
            address token,
            uint256 start,
            uint256 end,
            uint256 rewardAmount,
            uint256 rewardDistributed,
            uint256 claimCount,
            uint256 totalBalance,
            uint256 minimumDeposit,
            uint256 withdrawFee,
            address poolCreator
        ) = chickenPool.chickens(1);
        assertEq(token, MEME_TOKEN);
        assertEq(start, block.number + 1);
        assertEq(end, block.number + 2);
        assertEq(rewardAmount, REWARD_AMOUNT);
        assertEq(rewardDistributed, 0);
        assertEq(claimCount, 0);
        assertEq(totalBalance, 0);
        assertEq(withdrawFee, 0);
        assertEq(minimumDeposit, DEPOSIT_AMOUNT);
        assertEq(poolCreator, PROTOCOL);
    }

    function testJoinInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, 0));
        chickenPool.join(0, DEPOSIT_AMOUNT);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, maxcount));
        chickenPool.join(maxcount, DEPOSIT_AMOUNT);
    }

    function testJoinAfterStart() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        uint256 start = block.number + 1;
        uint256 end = block.number + 2;
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, start, end, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        vm.roll(start + 1);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenRunning.selector));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.roll(end + 1);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenRunning.selector));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testJoinRequiresMinimumDeposit() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT - 1);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.MinimumDepositNotMet.selector, chickenPool.MINIMUM_DEPOSIT_AMOUNT()));
        chickenPool.join(1, DEPOSIT_AMOUNT - 1);
        vm.stopPrank();
    }

    function testJoinRequiresDepositApproval() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.DepositNotAuthorized.selector, DEPOSIT_AMOUNT));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testJoinDepositsTokens() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        (,,,,,, uint256 totalBalance,,,) = chickenPool.chickens(1);
        assertEq(totalBalance, DEPOSIT_AMOUNT);
        assertEq(chickenPool.totalDeposits(1), DEPOSIT_AMOUNT);
        assertEq(chickenPool.balance(1, PLAYER1), DEPOSIT_AMOUNT);
    }

    function testClaimInvalidChickenId() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.claim(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PLAYER1);
        chickenPool.claim(maxcount);
    }

    function testClaimWithoutHavingJoined() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.roll(block.number + 3);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.PlayerIsNotInChickenPool.selector, PLAYER1));
        vm.prank(PLAYER1);
        chickenPool.claim(1);
    }

    function testClaimBeforeEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenNotFinished.selector));
        chickenPool.claim(1);
        vm.stopPrank();
    }

    function testClaimAfterEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        assertEq(chickenPool.balance(1, PLAYER1), DEPOSIT_AMOUNT);
        vm.roll(block.number + 3);
        chickenPool.claim(1);
        vm.stopPrank();
        assertEq(chickenPool.balance(1, PLAYER1), 0);
        uint256 balance = memeToken.balanceOf(PLAYER1);
        assertEq(balance, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT);
    }

    function testLastRemainingPlayerPermittedToClaimPriorToEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        (,,,, uint256 rewardDistributed, uint256 claimCount,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, REWARD_AMOUNT * TokenMath.BPS / 60000);
        assertEq(claimCount, 1);
        vm.prank(PLAYER2);
        chickenPool.claim(1);
        (,,,, rewardDistributed, claimCount,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, REWARD_AMOUNT / 6 + REWARD_AMOUNT / 3);
        assertEq(claimCount, 2);
        vm.prank(PLAYER3);
        chickenPool.claim(1);
        (,,,, rewardDistributed, claimCount,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, REWARD_AMOUNT);
        assertEq(claimCount, 3);
        uint256 balance1 = memeToken.balanceOf(PLAYER1);
        uint256 balance2 = memeToken.balanceOf(PLAYER2);
        uint256 balance3 = memeToken.balanceOf(PLAYER3);
        assertEq(chickenPool.balance(1, PLAYER1), 0);
        assertEq(balance1, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 6);
        assertEq(chickenPool.balance(1, PLAYER2), 0);
        assertEq(balance2, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 3);
        assertEq(chickenPool.balance(1, PLAYER3), 0);
        // player three gets the benefit of rounding so the reward is not REWARD_AMOUNT / 2
        // it is what is left after the first two players claim
        assertEq(balance3, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT - REWARD_AMOUNT / 6 - REWARD_AMOUNT / 3);
    }

    function testEntireClaimDistributedInSpiteOfRounding() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT); // 33%
        vm.stopPrank();
        vm.startPrank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT); // 33%
        vm.stopPrank();
        vm.startPrank(PLAYER3);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT); // 33%
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.prank(PLAYER1);
        chickenPool.claim(1);
        (,,,, uint256 rewardDistributed, uint256 claimCount,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, REWARD_AMOUNT / 3);
        assertEq(claimCount, 1);
        vm.prank(PLAYER2);
        chickenPool.claim(1);
        (,,,, rewardDistributed, claimCount,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, REWARD_AMOUNT / 3 + REWARD_AMOUNT / 3);
        assertEq(claimCount, 2);
        vm.prank(PLAYER3);
        chickenPool.claim(1);
        (,,,, rewardDistributed, claimCount,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, REWARD_AMOUNT);
        assertEq(claimCount, 3);
        uint256 balance1 = memeToken.balanceOf(PLAYER1);
        uint256 balance2 = memeToken.balanceOf(PLAYER2);
        uint256 balance3 = memeToken.balanceOf(PLAYER3);
        assertEq(balance1, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 3);
        assertEq(balance2, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 3);
        // player three gets the benefit of rounding so the reward is not 33%
        // it is 33% plus the smallest unit of token
        assertEq(balance3, 10 * DEPOSIT_AMOUNT + REWARD_AMOUNT / 3 + 1);
    }

    function testTotalBalanceAccrual() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT); // 33%
        vm.stopPrank();
        assertEq(chickenPool.totalDeposits(1), DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER2);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT); // 33%
        vm.stopPrank();
        assertEq(chickenPool.totalDeposits(1), 2 * DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER3);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT); // 33%
        vm.stopPrank();
        assertEq(chickenPool.totalDeposits(1), 3 * DEPOSIT_AMOUNT);
        // one player witdraw
        vm.startPrank(PLAYER3);
        chickenPool.withdraw(1);
        vm.stopPrank();
        assertEq(chickenPool.totalDeposits(1), 2 * DEPOSIT_AMOUNT);
        assertEq(chickenPool.balance(1, PLAYER3), 0);
        (,,,, uint256 rewardDistributed,,,,,) = chickenPool.chickens(1);
        assertEq(rewardDistributed, 0);
    }

    function testWithdrawInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.withdraw(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PLAYER1);
        chickenPool.withdraw(maxcount);
    }

    function testWithdrawAfterEnd() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        // player should claim rather than withdraw
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenFinished.selector));
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
    }

    function testWithdrawNonPlayer() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.PlayerIsNotInChickenPool.selector, PLAYER3));
        vm.prank(PLAYER3);
        chickenPool.withdraw(1);
    }

    function testWithdrawAsWinner() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 1);
        // player should claim rather than withdraw
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenFinished.selector));
        vm.prank(PLAYER2);
        chickenPool.withdraw(1);
    }

    function testWithdraw() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
        assertEq(memeToken.balanceOf(PLAYER1), 10 * DEPOSIT_AMOUNT);
        assertEq(memeToken.balanceOf(CHICKEN_POOL), requiredSpend + DEPOSIT_AMOUNT);
        (,,,,,, uint256 totalDeposits,,,) = chickenPool.chickens(1);
        assertEq(totalDeposits, DEPOSIT_AMOUNT);
        assertEq(chickenPool.totalDeposits(1), DEPOSIT_AMOUNT);
        assertEq(chickenPool.balance(1, PLAYER1), 0);
    }

    function testWithdrawWithWithdrawFee() public {
        uint256 withdrawFeeBps = 100;
        vm.startPrank(PROTOCOL);
        chickenPool.setProtocolFee(chickenPool.protocolFeeBps(), withdrawFeeBps);
        vm.stopPrank();
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
        uint256 withdrawFee = DEPOSIT_AMOUNT.bps(withdrawFeeBps);
        uint256 protocolFee = REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        assertEq(memeToken.balanceOf(PLAYER1), 10 * DEPOSIT_AMOUNT - withdrawFee);
        assertEq(memeToken.balanceOf(CHICKEN_POOL), requiredSpend + DEPOSIT_AMOUNT + withdrawFee);
        (,,,,,, uint256 totalDeposits,,,) = chickenPool.chickens(1);
        assertEq(totalDeposits, DEPOSIT_AMOUNT);
        assertEq(chickenPool.totalDeposits(1), DEPOSIT_AMOUNT);
        assertEq(chickenPool.balance(1, PLAYER1), 0);
        assertEq(chickenPool.getProtocolFeeBalance(1), protocolFee + withdrawFee);
    }

    function testProtocolWithdrawProtocolFee() public {
        uint256 expectProtocolFee = REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PROTOCOL);
        chickenPool.withdrawProtocolFee(maxcount);
    }

    function testBalanceInvalidId() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, 0));
        vm.prank(PLAYER1);
        chickenPool.balance(0, PLAYER1);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, maxcount));
        vm.prank(PLAYER1);
        chickenPool.balance(maxcount, PLAYER1);
    }

    function testBalanceNonPlayer() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, 0));
        chickenPool.totalDeposits(0);
        uint256 maxcount = chickenPool.chickenCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenIdInvalid.selector, maxcount));
        chickenPool.totalDeposits(maxcount);
    }

    function testTotalDeposits() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
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
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 1);
    }

    function testSetProtocolFee() public {
        assertEq(chickenPool.protocolFeeBps(), 100);
        assertEq(chickenPool.withdrawFeeBps(), 0);
        vm.prank(PROTOCOL);
        chickenPool.setProtocolFee(200, 333);
        assertEq(chickenPool.protocolFeeBps(), 200);
        assertEq(chickenPool.withdrawFeeBps(), 333);
    }

    function testSetProtocolFeeRequiresProtocol() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), chickenPool.PROTOCOL_ROLE()
            )
        );
        chickenPool.setProtocolFee(2000, 0);
    }

    function testSetProtocolFeeExceedsMaximum() public {
        uint256 maximumFee = chickenPool.MAXIMUM_PROTOCOL_FEE();
        vm.prank(PROTOCOL);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ProtocolFeeExceedsMaximum.selector));
        chickenPool.setProtocolFee(maximumFee, 0);
    }

    function testSetWithdrawFeeExceedsMaximum() public {
        uint256 maximumFee = chickenPool.MAXIMUM_PROTOCOL_FEE();
        vm.prank(PROTOCOL);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.WithdrawFeeExceedsMaximum.selector));
        chickenPool.setProtocolFee(100, maximumFee);
    }

    function testGetProtocolFeeBalance() public {
        assertEq(chickenPool.getProtocolFeeBalance(1), 0);
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.getProtocolFeeBalance(1), requiredSpend - REWARD_AMOUNT);
    }

    function testPauseContract() public {
        assertEq(chickenPool.paused(), false);
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
    }

    function testUnpauseContract() public {
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
        vm.prank(PAUSER);
        chickenPool.unpause();
        assertEq(chickenPool.paused(), false);
    }

    function testStartRevertWhenPaused() public {
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 0);
    }

    function testJoinRevertWhenPaused() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 1);
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testClaimRevertWhenPaused() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 1);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(PLAYER1);
        chickenPool.claim(1);
        vm.stopPrank();
    }

    function testWithdrawRevertWhenPaused() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.prank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        vm.prank(PROTOCOL);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        assertEq(chickenPool.chickenCount(), 1);
        vm.startPrank(PLAYER1);
        memeToken.approve(CHICKEN_POOL, DEPOSIT_AMOUNT);
        chickenPool.join(1, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(PLAYER1);
        chickenPool.withdraw(1);
        vm.stopPrank();
    }

    function testWithdrawProtocolFeeRevertWhenPaused() public {
        vm.prank(PAUSER);
        chickenPool.pause();
        assertEq(chickenPool.paused(), true);
        vm.prank(PROTOCOL);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
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

    function testRewardMayBeClaimedByCreatorIfNobodyJoinsPool() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.startPrank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 3);
        vm.prank(PROTOCOL);
        chickenPool.claim(1);
        uint256 protocolFee = requiredSpend - REWARD_AMOUNT;
        // total balance at start less protocol fee calculated at start
        assertEq(memeToken.balanceOf(PROTOCOL), 10 * REWARD_AMOUNT - protocolFee);
    }

    function testRewardMayNotBeClaimedBeforePoolStarts() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.startPrank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenNotFinished.selector));
        vm.prank(PROTOCOL);
        chickenPool.claim(1);
    }

    function testRewardMayNotBeClaimedBeforePoolEnds() public {
        uint256 requiredSpend = REWARD_AMOUNT + REWARD_AMOUNT.bps(chickenPool.protocolFeeBps());
        vm.startPrank(PROTOCOL);
        memeToken.approve(CHICKEN_POOL, requiredSpend);
        chickenPool.start(MEME_TOKEN, block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.ChickenNotFinished.selector));
        vm.prank(PROTOCOL);
        chickenPool.claim(1);
    }

    function testStartWithInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(RewardChicken.TokenInvalid.selector));
        vm.prank(PROTOCOL);
        chickenPool.start(address(0), block.number + 1, block.number + 2, REWARD_AMOUNT, DEPOSIT_AMOUNT);
    }

    function mockChickenPool(address _chickenPool) internal {
        RewardChicken implementation = new RewardChicken();
        bytes memory code = address(implementation).code;
        vm.etch(_chickenPool, code);
        RewardChicken(_chickenPool).initialize(OWNER);
    }

    function mockMemeToken(address _memeToken) internal {
        ERC20Mock tokenImpl = new ERC20Mock("MemeToken", "MEME", MAX_SUPPLY);
        bytes memory code = address(tokenImpl).code;
        vm.etch(_memeToken, code);
    }
}
