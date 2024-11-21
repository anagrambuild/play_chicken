// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20CappedUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title ChickenTokenUpgradeable
 * @dev ERC20 token with a capped supply
 */
contract ChickenTokenUpgradeable is
    Initializable,
    ERC20Upgradeable,
    ERC20CappedUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _initialSupply The initial supply of the token
     * @param _initialOwner The address to receive the initial supply
     * @param _launcherContract The address of the launcher contract
     * @param _cap The cap of the token
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _initialOwner,
        address _launcherContract,
        uint256 _cap
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Capped_init(_cap);
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _launcherContract);

        _mint(_initialOwner, _initialSupply);
        _cap = _cap;
    }

    /**
     * @dev Mint new tokens
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
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

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20CappedUpgradeable, ERC20PausableUpgradeable, ERC20Upgradeable)
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
