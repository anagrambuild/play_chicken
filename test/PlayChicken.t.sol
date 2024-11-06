// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {PlayChicken} from "../contracts/PlayChicken.sol";

contract PlayChickenTest is Test {
    address public CHICKEN_POOL;
    PlayChicken public playChicken;

    error InvalidInitialization();

    function setUp() public {
        CHICKEN_POOL = vm.addr(0x1);
        mockChickenPool(CHICKEN_POOL);
        playChicken = PlayChicken(CHICKEN_POOL);
    }

    function testBPSis10000() public view {
        assertEq(playChicken.BPS(), 10000);
    }

    function testDoubleInitializationFails() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        playChicken.initialize(address(this));
    }

    function mockChickenPool(address _chickenPool) internal {
        PlayChicken implementation = new PlayChicken();
        bytes memory code = address(implementation).code;
        vm.etch(_chickenPool, code);
        PlayChicken(_chickenPool).initialize(address(this));
    }
}
