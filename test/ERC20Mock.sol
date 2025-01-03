// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract ERC20Mock is ERC20Capped {
    constructor(string memory _name, string memory _symbol, uint256 _maxSupply) ERC20(_name, _symbol) ERC20Capped(_maxSupply) {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
