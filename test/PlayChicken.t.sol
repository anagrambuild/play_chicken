// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PlayChicken} from "../contracts/PlayChicken.sol";

contract PlayChickenTest is Test {
    PlayChicken public playChicken;

    function setUp() public {
        playChicken = new PlayChicken();
    }

    function testBPSis10000() public {
        assertEq(playChicken.BPS(), 10000);
    }

}
