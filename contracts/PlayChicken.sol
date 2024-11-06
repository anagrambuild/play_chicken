// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AddressSet} from "./AddressSet.sol";

contract PlayChicken {
    uint256 public constant BPS = 10000;
    
    struct Chicken {
        address token;
        uint256 start;
        uint256 end;
        uint256 reward_amount;
        uint256 total_balance;
        AddressSet players;
        mapping(address => uint256) player_balance;
    }

    uint256 public protocolFee; // protocol fee in bps

}
