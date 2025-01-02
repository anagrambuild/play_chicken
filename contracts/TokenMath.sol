// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

library TokenMath {
    uint256 public constant PERCENT = 100;
    uint256 public constant BPS = 10000; // 100%
    uint256 public constant BPS_ROUNDING_ERROR = BPS / 2;
    uint256 public constant TOKEN_BASE_QTY = 10 ** 18;

    function percent(uint256 _value) internal pure returns (uint256) {
        return _value * PERCENT;
    }

    function bps(uint256 _value, uint256 _bps) internal pure returns (uint256) {
        // properly rounds the result
        return (_value * _bps + BPS_ROUNDING_ERROR) / TokenMath.BPS;
    }

    function tokens(uint256 _qty) internal pure returns (uint256) {
        return _qty * TOKEN_BASE_QTY;
    }
}
