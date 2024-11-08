// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract PlayChicken is ReentrancyGuardUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    uint256 public constant BPS = 10000;
    uint256 public constant MINIMUM_REWARD_AMOUNT = 100; // 100 token
    uint256 public constant MINIMUM_DEPOSIT_AMOUNT = 1; // 1 token

    event ProtocolFeeChanged(uint256 protocolFee);
    event ProtocolFeeWithdrawn(uint256 amount, address token);
    event PlayerClaimedReward(uint256 chickenId, address player, uint256 reward);
    event PlayerChickendOut(uint256 chickenId, address player, uint256 amount);
    event ChickenStarted(
        uint256 chickenId, uint256 start, uint256 end, uint256 reward, address token, address createdBy
    );
    event PlayerJoined(uint256 chickenId, address player, uint256 totalDeposits);

    error ChickenMustEndInFuture();
    error ChickenMustStartInFuture();
    error ChickenStartAndEndMustBeDifferent();
    error ChickenRunning();
    error ChickenRewardMustBeGreaterThanMinimum(uint256 _minimum);
    error ChickenMinimumDepositMustBeLarger(uint256 _minimum);
    error ChickenRewardAndProtocolFeeNotMet(uint256 requiredReward, uint256 protocolFee);
    error ChickenNotFinished();
    error ChickenFinished();
    error ChickenIdInvalid(uint256 _chickenId);
    error ChickenMinimumDepositNotMet(uint256 _minimum);
    error ChickenDepositNotAuthorized(uint256 _minimum);
    error PlayerIsNotInChickenPool(address player);

    uint256 public protocolFee; // protocol fee in bps

    struct Chicken {
        address token;
        uint256 start;
        uint256 end;
        uint256 rewardAmount;
        uint256 rewardDistributed;
        uint256 claimCount;
        uint256 totalDeposits;
        uint256 minimumDeposit;
    }

    uint256 public chickenCount;

    mapping(uint256 => Chicken) public chickens;
    mapping(uint256 => EnumerableSet.AddressSet) internal players;
    mapping(uint256 => mapping(address => uint256)) internal playerBalance;

    // Reserve 50 slots for future upgrades
    uint256[50] private __gap;

    modifier onlyValidChickenPool(uint256 _chickenId) {
        require(_chickenId > 0 && _chickenId <= chickenCount, ChickenIdInvalid(_chickenId));
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        chickenCount = 0;
        protocolFee = 100; // 1%
    }

    /**
     * Start a new chicken pool.   Requires transfer of reward amount + protocol fee to the contract
     * @param _token address of the token to be used as reward
     * @param _start block number when the chicken will start
     * @param _end block number when the chicken will end
     * @param _rewardAmount amount of reward to be distributed
     */
    function start(address _token, uint256 _start, uint256 _end, uint256 _rewardAmount, uint256 _minimumDeposit)
        external
        nonReentrant
    {
        require(_start > block.number, ChickenMustStartInFuture());
        require(_end > block.number, ChickenMustEndInFuture());
        require(_start < _end, ChickenStartAndEndMustBeDifferent());
        require(_rewardAmount >= MINIMUM_REWARD_AMOUNT, ChickenRewardMustBeGreaterThanMinimum(MINIMUM_REWARD_AMOUNT));
        require(_minimumDeposit >= MINIMUM_DEPOSIT_AMOUNT, ChickenMinimumDepositMustBeLarger(MINIMUM_DEPOSIT_AMOUNT));

        IERC20 poolToken = IERC20(_token);
        uint256 feeRequiredByProtocol = (_rewardAmount * protocolFee) / BPS;
        uint256 depositAmount = feeRequiredByProtocol + _rewardAmount;
        uint256 authorizedAmount = poolToken.allowance(msg.sender, address(this));
        require(
            depositAmount <= authorizedAmount, ChickenRewardAndProtocolFeeNotMet(_rewardAmount, feeRequiredByProtocol)
        );
        SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), depositAmount);

        chickenCount++;

        Chicken storage chicken = chickens[chickenCount];
        chicken.token = _token;
        chicken.start = _start;
        chicken.end = _end;
        chicken.rewardAmount = _rewardAmount;
        chicken.rewardDistributed = 0;
        chicken.totalDeposits = 0;
        chicken.minimumDeposit = _minimumDeposit;
        emit ChickenStarted(chickenCount, _start, _end, _rewardAmount, _token, msg.sender);
    }

    /**
     * join the chicken pool
     * @param _chickenId id of the chicken pool
     * @param _depositAmount amount to be deposited
     */
    function join(uint256 _chickenId, uint256 _depositAmount) external nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(block.number < chicken.start, ChickenRunning());
        require(_depositAmount >= chicken.minimumDeposit, ChickenMinimumDepositNotMet(chicken.minimumDeposit));
        uint256 authorizedAmount = IERC20(chicken.token).allowance(msg.sender, address(this));
        require(_depositAmount <= authorizedAmount, ChickenDepositNotAuthorized(chicken.minimumDeposit));
        SafeERC20.safeTransferFrom(IERC20(chicken.token), msg.sender, address(this), _depositAmount);
        chicken.totalDeposits += _depositAmount;
        playerBalance[_chickenId][msg.sender] += _depositAmount;

        addPlayerIfNotExists(_chickenId, msg.sender);
        emit PlayerJoined(_chickenId, msg.sender, chicken.totalDeposits);
    }

    /**
     * Claim reward for successfully completed chicken pool
     * @dev reward is sent to msg.sender, msg.sender must be part of the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function claim(uint256 _chickenId) external nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.end < block.number || getPlayerCount(_chickenId) == 1, ChickenNotFinished());
        require(isPlayer(_chickenId, msg.sender), PlayerIsNotInChickenPool(msg.sender));

        uint256 playerDeposit = balance(_chickenId, msg.sender);
        uint256 rewardAmount = 0;
        if (getPlayerCount(_chickenId) - chicken.claimCount == 1) {
            // last player remaining - get all the remaining reward including dust
            rewardAmount = chicken.rewardAmount - chicken.rewardDistributed;
        } else {
            uint256 playerPortion = playerDeposit * BPS / chicken.totalDeposits;
            rewardAmount = (chicken.rewardAmount * playerPortion) / BPS;
        }

        chicken.rewardDistributed += rewardAmount;
        chicken.claimCount++;

        SafeERC20.safeTransfer(IERC20(chicken.token), msg.sender, playerDeposit + rewardAmount);
        emit PlayerClaimedReward(_chickenId, msg.sender, rewardAmount);
    }

    /**
     * Chicken out!
     * Retrieve your deposit prior to expiration of the chicken pool
     * @dev If player is last remaining player, or pool is ended, the player must
     * claim reward instead of withdrawing
     * @param _chickenId id of the chicken pool
     */
    function withdraw(uint256 _chickenId) external nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(block.number < chicken.end && getPlayerCount(_chickenId) > 1, ChickenFinished());
        require(isPlayer(_chickenId, msg.sender), PlayerIsNotInChickenPool(msg.sender));

        uint256 currentBalance = playerBalance[_chickenId][msg.sender];
        chicken.totalDeposits -= currentBalance;
        playerBalance[_chickenId][msg.sender] = 0;
        delete playerBalance[_chickenId][msg.sender];
        removePlayer(_chickenId, msg.sender);

        SafeERC20.safeTransfer(IERC20(chicken.token), msg.sender, currentBalance);
        emit PlayerChickendOut(_chickenId, msg.sender, currentBalance);
    }

    /**
     * Withdraw protocol fee
     * @dev only protocol can withdraw protocol fee
     * @param _chickenId id of the chicken pool
     */
    function withdrawProtocolFee(uint256 _chickenId)
        external
        onlyRole(PROTOCOL_ROLE)
        nonReentrant
        onlyValidChickenPool(_chickenId)
    {
        Chicken storage chicken = chickens[_chickenId];
        uint256 feeBalance = chicken.rewardAmount * protocolFee / BPS;
        SafeERC20.safeTransfer(IERC20(chicken.token), msg.sender, feeBalance);
        emit ProtocolFeeWithdrawn(feeBalance, chicken.token);
    }

    /**
     * Get balance of the player in the chicken pool
     * @param _chickenId id of the chicken
     */
    function balance(uint256 _chickenId) external view returns (uint256) {
        return balance(_chickenId, msg.sender);
    }

    /**
     * Get the balance for a given player in the pool
     * @param _chickenId id of the chicken pool
     * @param _player address of the player
     */
    function balance(uint256 _chickenId, address _player)
        public
        view
        onlyValidChickenPool(_chickenId)
        returns (uint256)
    {
        return playerBalance[_chickenId][_player];
    }

    /**
     * Get total balance of the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function totalDeposits(uint256 _chickenId) external view onlyValidChickenPool(_chickenId) returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        return chicken.totalDeposits;
    }

    /**
     * Set protocol fee in bps for the PlayChicken contract
     * @dev only the protocol can set the protocol fee
     * @param _protocolFee protocol fee in bps
     */
    function setProtocolFee(uint256 _protocolFee) external onlyRole(PROTOCOL_ROLE) {
        protocolFee = _protocolFee;
        emit ProtocolFeeChanged(_protocolFee);
    }

    /**
     * Get protocol fee balance for a chicken pool
     * @param _chickenId id of the chicken pool
     */
    function getProtocolFeeBalance(uint256 _chickenId) external view returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        return chicken.rewardAmount * protocolFee / BPS;
    }

    /**
     * @return true if player is in the chicken pool
     */
    function isPlayer(uint256 _chickenId, address _player) public view returns (bool) {
        return players[_chickenId].contains(_player);
    }

    /**
     *  @param _chickenId id of the chicken pool
     * @return uint256 number of players in the chicken pool
     */
    function getPlayerCount(uint256 _chickenId) public view returns (uint256) {
        return players[_chickenId].length();
    }

    function removePlayer(uint256 _chickenId, address _player) internal {
        players[_chickenId].remove(_player);
    }

    function addPlayerIfNotExists(uint256 _chickenId, address _player) internal {
        if (!isPlayer(_chickenId, _player)) {
            players[_chickenId].add(_player);
        }
    }
}
