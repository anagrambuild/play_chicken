// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

library FixedPointMath {
    int256 public constant SCALE = 1e18; // Fixed-point scale (Q.64x64)
    int256 public constant N_SERIES = 200; // Number of terms in the Taylor series

    error LnInputMustBePositive();
    error InvalidKurvature();

    // Approximate ln(x) for x in fixed-point format
    function ln(int256 x) internal pure returns (int256) {
        require(x > 0, LnInputMustBePositive());

        int256 result = 0;
        int256 term = (x - SCALE) * SCALE / (x + SCALE);
        int256 termSquared = (term * term) / SCALE;

        for (int256 i = 1; i < N_SERIES; i += 2) {
            // Taylor series expansion
            result += term / i;
            term = (term * termSquared) / SCALE;
        }

        return result * 2; // Multiply by 2 for ln approximation
    }

    // Approximate exp(x) for x in fixed-point format
    function exp(int256 x) internal pure returns (int256) {
        int256 result = SCALE;
        int256 term = SCALE;

        for (int256 i = 1; i < N_SERIES; i++) {
            term = (term * x) / (SCALE * i); // Taylor series term
            result += term;
        }

        return result;
    }

    // Compute x^k where k < 1 in fixed-point math
    function pow(int256 x, int256 k) internal pure returns (int256) {
        if (k == SCALE) {
            return x;
        }

        if (x == 0) {
            if (k == 0) {
                return SCALE;
            }
            return 0;
        }

        require(k < SCALE, InvalidKurvature());
        int256 lnX = ln(x);
        int256 exponent = (lnX * k) / SCALE;
        return exp(exponent);
    }

    /**
     * Area under a polynomial of degree k
     * the constant value **a** is eliminated from the calculation
     * D_max = a / (k + 1) * (x_max^(k + 1) - x_min^(k + 1))
     * @param _x1 the lower bound of the area
     * @param _x2 the upper bound of the area
     * @param _k the curvature of the polynomial
     */
    function areaUnderPolynomialOfDegreeK(int256 _x1, int256 _x2, int256 _k) internal pure returns (int256) {
        require(_k != -1 && _k < SCALE, InvalidKurvature());
        int256 kPlus1 = _k + SCALE;
        int256 x1PowK = pow(_x1, _k) * _x1;
        int256 x2PowK = pow(_x2, _k) * _x2;
        return (x2PowK - x1PowK) / kPlus1;
    }
}
