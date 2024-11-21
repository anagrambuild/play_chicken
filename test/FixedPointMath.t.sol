// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable var-name-mixedcase
// solhint-disable no-console

import {Test, console} from "forge-std/Test.sol";

import {FixedPointMath} from "../contracts/FixedPointMath.sol";

contract FixedPointMathTest is Test {
    using FixedPointMath for uint256;

    int256 public constant SCALE = FixedPointMath.SCALE;

    // --- Tests for ln(x) ---
    function testLnSimple() public pure {
        int256 input = 2 * SCALE; // 2 in fixed-point
        int256 expected = 693147180559945309; // Approximation of ln(2) in fixed-point
        int256 result = FixedPointMath.ln(input);

        console.log("ln(2):", result);
        assertApproxEqAbs(result, expected, 1e10, "ln(2) is not accurate");
    }

    function testLnLargeInput() public pure {
        int256 input = 10 * SCALE; // 10 in fixed-point
        int256 expected = 2302585092994045684; // Approximation of ln(10)
        int256 result = FixedPointMath.ln(input);

        console.log("ln(10):", result);
        assertApproxEqAbs(result, expected, 10 ** 18 / 100, "ln(10) is not accurate");
    }

    function testLnSmallInput() public pure {
        int256 input = SCALE / 2; // 0.5 in fixed-point
        int256 expected = -693147180559945309; // Approximation of ln(0.5)
        int256 result = FixedPointMath.ln(input);

        console.log("ln(0.5):", result);
        assertApproxEqAbs(result, expected, 1e10, "ln(0.5) is not accurate");
    }

    function testLnInvalidInput() public {
        int256 input = 0; // ln(0) is undefined
        vm.expectRevert(abi.encodeWithSelector(FixedPointMath.LnInputMustBePositive.selector));
        FixedPointMath.ln(input);
    }

    // --- Tests for exp(x) ---
    function testExpZero() public pure {
        int256 input = 0; // exp(0) = 1
        int256 expected = SCALE; // 1 in fixed-point
        int256 result = FixedPointMath.exp(input);

        console.log("exp(0):", result);
        assertEq(result, expected, "exp(0) is not accurate");
    }

    function testExpPositive() public pure {
        int256 input = 1 * SCALE; // 1 in fixed-point
        int256 expected = 2718281828459045235; // Approximation of e^1
        int256 result = FixedPointMath.exp(input);

        console.log("exp(1):", result);
        assertApproxEqAbs(result, expected, 1e10, "exp(1) is not accurate");
    }

    function testExpNegative() public pure {
        int256 input = -1 * SCALE; // -1 in fixed-point
        int256 expected = 367879441171442321; // Approximation of e^(-1)
        int256 result = FixedPointMath.exp(input);

        console.log("exp(-1):", result);
        assertApproxEqAbs(result, expected, 1e10, "exp(-1) is not accurate");
    }

    function testExpLargeInput() public pure {
        int256 input = 10 * SCALE; // 10 in fixed-point
        // exp(10) is very large; ensure no overflow occurs
        int256 result = FixedPointMath.exp(input);

        console.log("exp(10):", result);
        assertTrue(result > SCALE, "exp(10) should be large");
    }

    // --- Tests for pow(x, k) ---
    function testPowSimple() public pure {
        int256 base = 2 * SCALE; // 2 in fixed-point
        int256 exponent = SCALE / 2; // 0.5 in fixed-point
        int256 expected = 1414213562373095049; // Approximation of 2^(0.5)
        int256 result = FixedPointMath.pow(base, exponent);

        console.log("2^0.5:", result);
        assertApproxEqAbs(result, expected, 1e10, "2^0.5 is not accurate");
    }

    function testPowZeroExponent() public pure {
        int256 base = 5 * SCALE; // 5 in fixed-point
        int256 exponent = 0; // 0 in fixed-point
        int256 expected = SCALE; // Any number^0 = 1
        int256 result = FixedPointMath.pow(base, exponent);

        console.log("5^0:", result);
        assertEq(result, expected, "5^0 is not accurate");
    }

    function testPowOneExponent() public pure {
        int256 base = 7 * SCALE; // 7 in fixed-point
        int256 exponent = SCALE; // 1 in fixed-point
        int256 expected = base; // Any number^1 = itself
        int256 result = FixedPointMath.pow(base, exponent);

        console.log("7^1:", result);
        assertEq(result, expected, "7^1 is not accurate");
    }

    function testPowLargeBaseSmallExponent() public pure {
        int256 base = 10 * SCALE; // 10 in fixed-point
        int256 exponent = SCALE / 3; // 0.333... in fixed-point
        int256 expected = 2154434690031883617; // Approximation of 10^(1/3)
        int256 result = FixedPointMath.pow(base, exponent);

        console.log("10^(1/3):", result);
        assertApproxEqAbs(result, expected, 10 ** 18 / 1000, "10^(1/3) is not accurate");
    }

    function testPowSmallBaseLargeExponent() public pure {
        int256 base = SCALE / 2; // 0.5 in fixed-point
        int256 exponent = 9 * 10 ** 17; // 0.9 in fixed-point
        int256 expected = 535886731268146500; // Approximation of 0.5^0.9
        //
        int256 result = FixedPointMath.pow(base, exponent);

        console.log("0.5^0.9:", result);
        assertApproxEqAbs(result, expected, 1e10, "0.5^0.9 is not accurate");
    }

    function testPowEdgeCaseBaseZero() public pure {
        int256 base = 0; // 0 in fixed-point
        int256 exponent = SCALE; // 1 in fixed-point
        int256 expected = 0; // 0^1 = 0
        int256 result = FixedPointMath.pow(base, exponent);

        console.log("0^1:", result);
        assertEq(result, expected, "0^1 is not accurate");
    }

    function testAreaUnderPolynomialofDegreeK() public pure {
        int256 maxPrice = 25 * SCALE; // 25 in fixed-point
        int256 minPrice = 0; // 0 in fixed-point
        int256 kurvature = SCALE / 3; // 1/3 in fixed-point
        int256 expected = 54.82533259e18; // area from 0 25
        int256 result = FixedPointMath.areaUnderPolynomialOfDegreeK(minPrice, maxPrice, kurvature);

        console.log("areaUnderPolynomialOfDegreeK():", result);
        assertApproxEqAbs(result, expected, 1e18 / 1e5, "areaUnderPolynomialOfDegreeK() is not accurate");
    }
}
