// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

contract PlayChicken {
    uint256 public constant BPS = 10000;
    
    struct Chicken {
        address token;
    }

    uint256 public protocolFee; // protocol fee in bps

}
