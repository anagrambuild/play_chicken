// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import {FixedPointMath} from "./FixedPointMath.sol";

library ChickenLiquidityPricer {
    error InvalidKurvature();
    error NPriceBinTooLarge();

    int256 public constant SCALE = 10 ** 18;

    /**
     * This function quotes the price of a token based on the amount of tokens available for a capped supply
     *
     * The price is calculated following the method here:
     * https://github.com/TeamRaccoons/Intuitive-Launchpool-Model-Paper/blob/266f546a4a2c6860bfa51333fc7af4007c11cb23/ILM.pdf
     *
     * In summary, a token total supply is distributed into price bins according to the pricing function.
     *
     * The distribution function is a polynomial function in curvature k, a function of the number of tokens
     * let
     * N(x) = a * x^k
     *
     * then by simple integration we can find the area under the curve for the total distribution
     *
     * D_max = a / (k + 1) * (x_max^(k + 1) - x_min^(k + 1))
     *
     * The curvature, k must not be -1 or greater than or equal to 1
     *
     * Then the amount of tokens in a particular price bin is given by
     *
     * N_bin(x) = a / (k + 1) * (x_2^(k + 1) - x_1^(k + 1)) / D_max
     *
     * because **a** occurs in both N_bin and D_max it can be eliminated from the calculation
     *
     * To find the price bin for a given amount of tokens, the goal is to sum the amount of tokens in each
     * price bin until the desired amount is reached.
     *
     * The price of the token is given by the price bin that contains it
     */
    function quote(
        uint256 _amount,
        uint256 _claimedTokens,
        uint256 _totalSupply,
        int256 _maxPrice,
        int256 _minPrice,
        int256 _kurvature,
        int256 nPriceBin
    ) internal pure returns (int256) {
        require(_kurvature != -1 && _kurvature < SCALE, InvalidKurvature());
        require(nPriceBin < 1000, NPriceBinTooLarge());
        int256 areaMax = FixedPointMath.areaUnderPolynomialOfDegreeK(_minPrice, _maxPrice, _kurvature);
        int256 quantitySoFar = 0;
        int256 priceStep = (_maxPrice - _minPrice) / nPriceBin;
        for (int256 i = _minPrice; i < _maxPrice; i += priceStep) {
            int256 quantityInBin =
                FixedPointMath.areaUnderPolynomialOfDegreeK(i, i + priceStep, _kurvature) * int256(_totalSupply) / areaMax;
            quantitySoFar += quantityInBin;
            if (quantitySoFar >= int256(_claimedTokens + _amount)) {
                return i + priceStep;
            }
        }
        return _maxPrice;
    }
}
