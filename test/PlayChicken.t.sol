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

    function testStartWithInvalidToken() public {
        // create a new chicken pool with invalid token
        vm.expectRevert(abi.encodeWithSelector(PlayChicken.TokenInvalid.selector));
        chickenPool.start(address(0), BUY_IN_AMOUNT, SLASHING_PERCENT);
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
