// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ChickenTokenUpgradeable} from "./ChickenTokenUpgradeable.sol";

//     ________
//   /        \
//  |          |
//  |   O  O   |   <-- Chicken
//   \    >   /
//    |______|_____
//    |     /      \
//    |    /        \
// ---|===|==========\--
//    |    \__________\
//    \________________\
//     [===LAUNCHER===]
//    /    --------    \
//   /                  \
//  |....................|
/**
 * @title ChickenLauncher
 * @dev Contract for launching the ChickenToken
 */
contract ChickenLauncher is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Clones for address;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event TokenUpgraded(address indexed newImplementation, address indexed oldImplementation);
    event TokenCreated(
        address indexed token, string name, string symbol, uint256 initialSupply, address initialOwner, uint256 cap
    );

    address private implementation;

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param _ownerAdmin The address of the proxy admin
     */
    function initialize(address _ownerAdmin) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _ownerAdmin);
        _grantRole(PAUSER_ROLE, _ownerAdmin);
        implementation = address(new ChickenTokenUpgradeable());
    }

    /**
     * @dev Launch the ChickenToken
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _initialSupply The initial supply of the token
     * @param _initialOwner The address to receive the initial supply
     * @param _cap The cap of the token
     */
    function launch(string memory _name, string memory _symbol, uint256 _initialSupply, address _initialOwner, uint256 _cap)
        public
        whenNotPaused
        returns (address _token)
    {
        _token = implementation.clone();
        ChickenTokenUpgradeable(_token).initialize(_name, _symbol, _initialSupply, _initialOwner, address(this), _cap);
        emit TokenCreated(_token, _name, _symbol, _initialSupply, _initialOwner, _cap);
    }

    /**
     * @dev Pause the contract
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function upgradeToken() public onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldImplementation = implementation;
        implementation = address(new ChickenTokenUpgradeable());
        emit TokenUpgraded(implementation, oldImplementation);
    }
}
