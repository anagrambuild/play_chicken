// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract PlayChicken is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant BPS = 10000;
    uint256 public constant BASE_AMOUNT = 10 ** 18;
    uint256 public constant MINIMUM_BUY_IN = 100 * BASE_AMOUNT;
    // bps slashed on forfeit
    uint256 public constant MINIMUM_SLASHING_PERCENT = 1000; // 10%
    uint256 public constant MINIMUM_PROTOCOL_FEE = 50; // 0.5%

    event ProtocolFeeChanged(uint256 protocolFee);
    event ProtocolFeeWithdrawn(uint256 amount, address token);
    event ChickenStarted(uint256 chickenId, address token, uint256 buyIn, uint256 slashingPercent);
    event PlayerJoined(uint256 chickenId, address player, uint256 totalDeposit);

    error TokenInvalid();
    error MinimumBuyInRequired();
    error MinimumSlashingPercentRequired();
    error ChickenFinished();
    error ChickenNotFinished();
    error InsufficientBuyIn();
    error InsufficientFunds();
    error DepositNotAuthorized(uint256 minimumDeposit);
    error PlayerIsWinner();
    error ChickenIdInvalid(uint256 chickenId);
    error PlayerIsNotInChickenPool(address player);
    error ProtocolFeeTooLow();
    error WaitForGameStart();

    enum ChickenState {
        WAITING,
        RUNNING,
        FINISHED
    }

    struct Chicken {
        address token;
        uint256 buyIn;
        uint256 slashingPercent;
        uint256 totalDeposits;
        uint256 rewardQuantity;
        uint256 protocolFee;
        ChickenState gameStatus;
    }

    uint256 public protocolFeeBps; // protocol fee in bps

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

    /**
     * Initialize the contract
     * @param _owner address of the owner
     */
    function initialize(address _owner) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);
        chickenCount = 0;
        protocolFeeBps = 100; // 1%
    }

    /**
     * Add a new chicken pool
     * @param _token address of the token
     * @param _buyIn buy in amount
     * @param _slashingPercent slashing percent on forfiet in bps
     */
    function start(address _token, uint256 _buyIn, uint256 _slashingPercent) external whenNotPaused nonReentrant {
        require(_token != address(0), TokenInvalid());
        require(_buyIn >= MINIMUM_BUY_IN, MinimumBuyInRequired());
        require(_slashingPercent >= MINIMUM_SLASHING_PERCENT, MinimumSlashingPercentRequired());
        chickenCount++;
        Chicken storage chicken = chickens[chickenCount];
        chicken.token = _token;
        chicken.buyIn = _buyIn;
        chicken.slashingPercent = _slashingPercent;
        chicken.totalDeposits = 0;
        chicken.rewardQuantity = 0;
        chicken.protocolFee = 0;
        chicken.gameStatus = ChickenState.WAITING;
        emit ChickenStarted(chickenCount, _token, _buyIn, _slashingPercent);
    }

    /**
     * Join the chicken pool
     * @param _chickenId id of the chicken pool
     * @param _deposit amount to deposit
     */
    function join(uint256 _chickenId, uint256 _deposit) external whenNotPaused nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.gameStatus != ChickenState.FINISHED, ChickenFinished());
        require(_deposit >= chicken.buyIn, InsufficientBuyIn());
        uint256 authorizedAmount = IERC20(chicken.token).allowance(msg.sender, address(this));
        require(_deposit <= authorizedAmount, DepositNotAuthorized(chicken.buyIn));
        IERC20(chicken.token).safeTransferFrom(msg.sender, address(this), _deposit);
        uint256 protocolFee = _deposit * protocolFeeBps / BPS;
        uint256 netDeposit = _deposit - protocolFee;
        playerBalance[_chickenId][msg.sender] += netDeposit;
        chicken.protocolFee += protocolFee;
        chicken.totalDeposits += netDeposit;
        addPlayerIfNotExists(_chickenId, msg.sender);
        if (getPlayerCount(_chickenId) > 1) {
            chicken.gameStatus = ChickenState.RUNNING;
        }
    }

    /**
     * Chicken out!
     * Retrieve your deposit while the game is still running.
     * You will forfiet the slashing percentage of your deposit.
     * @param _chickenId id of the chicken pool
     */
    function withdraw(uint256 _chickenId) external whenNotPaused nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.gameStatus != ChickenState.WAITING, WaitForGameStart());
        require(chicken.gameStatus != ChickenState.FINISHED, ChickenFinished());
        require(isPlayer(_chickenId, msg.sender), PlayerIsNotInChickenPool(msg.sender));
        require(getPlayerCount(_chickenId) > 1, PlayerIsWinner());
        uint256 deposit = playerBalance[_chickenId][msg.sender];
        require(deposit > 0, InsufficientFunds());
        uint256 slashingAmount = deposit * chicken.slashingPercent / BPS;
        uint256 withdrawAmount = deposit - slashingAmount;
        chicken.totalDeposits -= deposit;
        chicken.rewardQuantity += slashingAmount;
        playerBalance[_chickenId][msg.sender] = 0;
        delete playerBalance[_chickenId][msg.sender];
        removePlayer(_chickenId, msg.sender);
        IERC20(chicken.token).safeTransfer(msg.sender, withdrawAmount);
        if (getPlayerCount(_chickenId) == 1) {
            chicken.gameStatus = ChickenState.FINISHED;
        }
    }

    /**
     * Claim the prize if you are the last player standing
     * @param _chickenId id of the chicken pool
     */
    function claim(uint256 _chickenId) external whenNotPaused nonReentrant onlyValidChickenPool(_chickenId) {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.gameStatus == ChickenState.FINISHED, ChickenNotFinished());
        require(isPlayer(_chickenId, msg.sender), PlayerIsNotInChickenPool(msg.sender));
        uint256 deposit = playerBalance[_chickenId][msg.sender];
        require(deposit > 0, InsufficientFunds());
        uint256 reward = chicken.rewardQuantity;
        playerBalance[_chickenId][msg.sender] = 0;
        delete playerBalance[_chickenId][msg.sender];
        removePlayer(_chickenId, msg.sender);
        IERC20(chicken.token).safeTransfer(msg.sender, deposit + reward);
    }

    /**
     * withdraw protocol fee
     * @param _chickenId id of the chicken pool
     */
    function withdrawProtocolFee(uint256 _chickenId)
        external
        whenNotPaused
        nonReentrant
        onlyValidChickenPool(_chickenId)
        onlyRole(PROTOCOL_ROLE)
    {
        Chicken storage chicken = chickens[_chickenId];
        require(chicken.gameStatus == ChickenState.FINISHED, ChickenNotFinished());
        uint256 protocolFee = chicken.protocolFee;
        require(protocolFee > 0, InsufficientFunds());
        chicken.protocolFee = 0;
        IERC20(chicken.token).safeTransfer(msg.sender, protocolFee);
        emit ProtocolFeeWithdrawn(protocolFee, chicken.token);
    }

    /**
     * Get the balance for a given player in the pool
     * @param _chickenId id of the chicken pool
     * @param _player address of the player
     */
    function balance(uint256 _chickenId, address _player) public view onlyValidChickenPool(_chickenId) returns (uint256) {
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
        require(_protocolFee >= MINIMUM_PROTOCOL_FEE, ProtocolFeeTooLow());
        protocolFeeBps = _protocolFee;
        emit ProtocolFeeChanged(_protocolFee);
    }

    /**
     * Get protocol fee balance for a chicken pool
     * @param _chickenId id of the chicken pool
     */
    function getProtocolFeeBalance(uint256 _chickenId) external view returns (uint256) {
        Chicken storage chicken = chickens[_chickenId];
        return chicken.protocolFee;
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

    /**
     * Pause the contract
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * Unpause the contract
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
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
