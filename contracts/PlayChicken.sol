// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {AddressSet} from "./AddressSet.sol";

contract PlayChicken is ReentrancyGuardUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    uint256 public constant BPS = 10000;
    uint256 public constant MINIMUM_REWARD_AMOUNT = 1e18; // 1 token
    uint256 public constant MINIMUM_DEPOSIT_AMOUNT = 1e18; // 1 token

    event ProtocolFeeChanged(uint256 protocolFee);
    event ProtocolFeeWithdrawn(uint256 amount, address token);
    event PlayerClaimedReward(uint256 chickenId, address player, uint256 reward);
    event PlayerChickendOut(uint256 chickenId, address player, uint256 amount);
    event ChickenStarted(uint256 chickenId, uint256 start, uint256 end, uint256 reward, address token, address createdBy);
    event PlayerJoined(uint256 chickenId, address player, uint256 totalBalance);

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
    error PlayerIsNotInChickenPool(address player);

    struct Chicken {
        address token;
        uint256 start;
        uint256 end;
        uint256 rewardAmount;
        uint256 totalBalance;
        uint256 minimumDeposit;
        AddressSet players;
        mapping(address => uint256) playerBalance;
    }

    uint256 public protocolFee; // protocol fee in bps
    mapping(uint256 => Chicken) public chickens;
    uint256 public chickenCount;

    modifier onlyValidChickenPool(uint256 _chickenId) {
        require(_chickenId < chickenCount, ChickenIdInvalid(_chickenId));
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
        require(_rewardAmount > MINIMUM_REWARD_AMOUNT, ChickenRewardMustBeGreaterThanMinimum(MINIMUM_REWARD_AMOUNT));
        require(_minimumDeposit > MINIMUM_DEPOSIT_AMOUNT, ChickenMinimumDepositMustBeLarger(MINIMUM_DEPOSIT_AMOUNT));

        IERC20 poolToken = IERC20(_token);
        uint256 feeRequiredByProtocol = (_rewardAmount * protocolFee) / BPS;
        uint256 depositAmount = feeRequiredByProtocol + _rewardAmount;
        require(
            depositAmount < poolToken.allowance(msg.sender, address(this)),
            ChickenRewardAndProtocolFeeNotMet(depositAmount, protocolFee)
        );
        SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), depositAmount);

        Chicken storage chicken = chickens[chickenCount];
        chicken.token = _token;
        chicken.start = _start;
        chicken.end = _end;
        chicken.rewardAmount = _rewardAmount;
        chicken.totalBalance = 0;
        chicken.minimumDeposit = _minimumDeposit;
        chicken.players = new AddressSet();
        chickenCount++;

        emit ChickenStarted(chickenCount, _start, _end, _rewardAmount, _token, msg.sender);
    }

    /**
     * Claim reward for successfully completed chicken pool
     * @dev reward is sent to msg.sender, msg.sender must be part of the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function claim(uint256 _chickenId) external nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.end < block.number || chicken.players.size() == 1, ChickenNotFinished());
        require(chicken.players.contains(msg.sender), PlayerIsNotInChickenPool(msg.sender));

        uint256 playerDeposit = chicken.playerBalance[msg.sender];
        uint256 playerPortion = playerDeposit * BPS / chicken.totalBalance;

        uint256 rewardAmount = (chicken.rewardAmount * playerPortion) / BPS;
        SafeERC20.safeTransfer(IERC20(chicken.token), msg.sender, rewardAmount);
        emit PlayerClaimedReward(_chickenId, msg.sender, rewardAmount);
    }

    /**
     * Chicken out!   Retrieve your deposit prior to expiration of the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function withdraw(uint256 _chickenId) external nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.end < block.number, ChickenFinished());
        require(chicken.players.contains(msg.sender), PlayerIsNotInChickenPool(msg.sender));

        uint256 playerBalance = chicken.playerBalance[msg.sender];
        chicken.totalBalance -= playerBalance;
        chicken.playerBalance[msg.sender] = 0;
        delete chicken.playerBalance[msg.sender];
        chicken.players.erase(msg.sender);

        SafeERC20.safeTransfer(IERC20(chicken.token), msg.sender, playerBalance);
        emit PlayerChickendOut(_chickenId, msg.sender, playerBalance);
    }

    /**
     * join the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function join(uint256 _chickenId) external payable nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.start < block.number, ChickenRunning());

        uint256 depositAmount = msg.value;
        require(depositAmount >= chicken.minimumDeposit, ChickenMinimumDepositNotMet(chicken.minimumDeposit));

        SafeERC20.safeTransferFrom(IERC20(chicken.token), msg.sender, address(this), depositAmount);
        chicken.totalBalance += depositAmount;
        chicken.playerBalance[msg.sender] += depositAmount;

        if (!chicken.players.contains(msg.sender)) {
            chicken.players.add(msg.sender);
        }
        emit PlayerJoined(_chickenId, msg.sender, chicken.totalBalance);
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
        uint256 feeBalance = getProtocolFeeBalance(_chickenId);
        SafeERC20.safeTransfer(IERC20(chicken.token), msg.sender, feeBalance);
        emit ProtocolFeeWithdrawn(feeBalance, chicken.token);
    }

    /**
     * Get balance of the player in the chicken pool
     * @param _chickenId id of the chicken
     */
    function balance(uint256 _chickenId) external view onlyValidChickenPool(_chickenId) returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        if (chicken.players.contains(msg.sender)) {
            return chicken.playerBalance[msg.sender];
        }
        return 0;
    }

    /**
     * Get number of players in the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function remainingPlayers(uint256 _chickenId) external view onlyValidChickenPool(_chickenId) returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        return chicken.players.size();
    }

    /**
     * Get total balance of the chicken pool
     * @param _chickenId id of the chicken pool
     */
    function chickenPoolBalance(uint256 _chickenId) external view onlyValidChickenPool(_chickenId) returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        return chicken.totalBalance;
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
    function getProtocolFeeBalance(uint256 _chickenId) public view returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        return chicken.rewardAmount * protocolFee / BPS;
    }
}
