// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {TokenMath} from "../contracts/TokenMath.sol";

contract TestPriceTable is Test {
    using TokenMath for uint256;

    function testBps1() public pure {
        uint256 value = 100;
        uint256 bps = 10000;
        uint256 result = TokenMath.bps(value, bps);
        assertEq(result, 100);
    }

    function testBps2() public pure {
        uint256 value = 100;
        uint256 bps = 5000;
        uint256 result = TokenMath.bps(value, bps);
        assertEq(result, 50);
    }

    function testBps3() public pure {
        uint256 value = 100;
        uint256 bps = 20000;
        uint256 result = TokenMath.bps(value, bps);
        assertEq(result, 200);
    }

    function testBps4() public pure {
        uint256 value = 100;
        uint256 bps = 0;
        uint256 result = TokenMath.bps(value, bps);
        assertEq(result, 0);
    }

    function testBps5() public pure {
        uint256 value = 100;
        uint256 bps = 100;
        uint256 result = TokenMath.bps(value, bps);
        assertEq(result, 1);
    }

    function testBps6() public pure {
        uint256 value = 100;
        uint256 bps = 150;
        uint256 result = TokenMath.bps(value, bps);
        assertEq(result, 2);
    }

    function testBpsBaseIs10000() public pure {
        assertEq(TokenMath.BPS, 10000);
    }

    function testBps() public pure {
        assertEq(uint256(10).bps(999), 1);
        assertEq(uint256(500).bps(100), 5);
        assertEq(uint256(1000).bps(100), 10);
    }
}
