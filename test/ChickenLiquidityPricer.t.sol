// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable var-name-mixedcase
// solhint-disable no-console

import {Test, console} from "forge-std/Test.sol";

import {ChickenLiquidityPricer} from "../contracts/ChickenLiquidityPricer.sol";

contract ChickenLiquidityPricerTest is Test {
    using ChickenLiquidityPricer for uint256;

    int256 public constant SCALE = ChickenLiquidityPricer.SCALE;
    uint256 public constant USCALE = uint256(SCALE);

    // --- Tests for quote() ---
    function testQuoteSimple() public pure {
        uint256 amount = 2 * USCALE; // 2 in fixed-point
        uint256 claimedTokens = 1 * USCALE; // 1 in fixed-point
        uint256 totalSupply = 10 * USCALE; // 10 in fixed-point
        int256 maxPrice = 10 * SCALE; // 10 in fixed-point
        int256 minPrice = 1 * SCALE; // 1 in fixed-point
        int256 kurvature = SCALE / 2; // 0.5 in fixed-point
        int256 nPriceBin = 10;
        int256 expected = 5.5e18; // first bin
        int256 result = ChickenLiquidityPricer.quote(amount, claimedTokens, totalSupply, maxPrice, minPrice, kurvature, nPriceBin);

        console.log("quote():", result);
        assertApproxEqAbs(result, expected, 1e10, "quote() is not accurate");
    }

    function testQuoteLargeInput() public pure {
        uint256 amount = 10 * USCALE; // 10 in fixed-point
        uint256 claimedTokens = 5 * USCALE; // 5 in fixed-point
        uint256 totalSupply = 100 * USCALE; // 100 in fixed-point
        int256 maxPrice = 100 * SCALE; // 100 in fixed-point
        int256 minPrice = 10 * SCALE; // 10 in fixed-point
        int256 kurvature = SCALE / 3; // 1/3 in fixed-point
        int256 nPriceBin = 100;
        int256 expected = 28900000000000000000;
        int256 result = ChickenLiquidityPricer.quote(amount, claimedTokens, totalSupply, maxPrice, minPrice, kurvature, nPriceBin);

        console.log("quote():", result);
        assertApproxEqAbs(result, expected, 10 ** 18 / 100, "quote() is not accurate");
    }

    function testQuoteCubeRootSpline() public pure {
        uint256 amount = 1 * USCALE; // 1 in fixed-point
        // qty expected minted to first bin
        uint256 claimedTokens = 2155 * USCALE; // enough to fill the first bin in fixed-point
        uint256 totalSupply = 1_000_000 * USCALE; // 1,000,000 in fixed-point
        int256 maxPrice = 25 * SCALE; // 25 in fixed-point
        int256 minPrice = 0; // 0 in fixed-point
        int256 kurvature = SCALE / 3; // 1/3 in fixed-point
        int256 nPriceBin = 100; // not scaled
        int256 expected = 0.5e18; // second price bin is 0.50
        int256 result = ChickenLiquidityPricer.quote(amount, claimedTokens, totalSupply, maxPrice, minPrice, kurvature, nPriceBin);
        assertApproxEqAbs(result, expected, 1e10, "quote() is not accurate");
    }
}
