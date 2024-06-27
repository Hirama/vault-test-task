// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

error InvalidConfiguration();
error InsufficientShares();
error TransferFailed();
error AmountMustBeGreaterThanZero();
error RateUpdateFailed();
error ManagerFeeUpdateFailed();
error RewardsAccumulationFailed();

/**
 * @title Vault
 * @dev A vault contract that manages deposits, withdrawals, and rewards accumulation for a specific ERC20 token.
 *      The contract issues shares to users upon deposit and redeems shares upon withdrawal.
 */
contract Vault is ReentrancyGuard, Ownable2Step, Pausable {
    IERC20 public token;
    uint256 public rate; // Rate in terms of token per share
    uint256 public managerFee; // Fee in basis points (1% = 100 basis points)
    uint256 public constant BASIS_POINTS = 10000; // 100 basis points = 1%, 10000 basis points = 100%

    uint256 public totalDeposits; // Total amount of tokens deposited in the vault
    uint256 public totalShares; // Total number of shares issued by the vault
    uint256 public contractShares; // Number of shares owned by the manager

    mapping(address => uint256) public userBalances; // User balances in terms of tokens
    mapping(address => uint256) public userShares; // User shares

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 feeAmount,
        uint256 adjustedAmount,
        uint256 shares
    );
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event FeeWithdrawal(address indexed owner, uint256 amount);
    event RateUpdate(address indexed owner, uint256 newRate);
    event ManagerFeeUpdate(address indexed owner, uint256 newFee);
    event RewardsAccumulated(address indexed owner, uint256 amount);

    /**
     * @dev Initializes the vault with the given token, rate, and manager fee.
     * @param _token The address of the ERC20 token to be managed by the vault.
     * @param _rate The initial rate in terms of token per share.
     * @param _managerFee The fee in basis points (1% = 100 basis points).
     */
    constructor(
        address _token,
        uint256 _rate,
        uint256 _managerFee
    ) Ownable(msg.sender) {
        require(_token != address(0), InvalidConfiguration());
        require(_rate > 0, InvalidConfiguration());
        require(_managerFee > 0, InvalidConfiguration());
        token = IERC20(_token);
        rate = _rate;
        managerFee = _managerFee;
    }

    /**
     * @dev Allows a user to deposit tokens into the vault and receive shares in return.
     * @param _amount The amount of tokens to deposit.
     */
    function deposit(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, AmountMustBeGreaterThanZero());

        uint256 fee = (_amount * managerFee) / BASIS_POINTS;
        uint256 adjustedAmount = _amount - fee;

        uint256 usersSharesToMint = adjustedAmount / rate;
        uint256 feeToSharesToMint = fee / rate;

        totalDeposits += adjustedAmount;
        totalShares += usersSharesToMint + feeToSharesToMint;
        contractShares += feeToSharesToMint;

        userBalances[msg.sender] += adjustedAmount;
        userShares[msg.sender] += usersSharesToMint;

        require(
            token.transferFrom(msg.sender, address(this), _amount),
            TransferFailed()
        );

        emit Deposit(
            msg.sender,
            _amount,
            fee,
            adjustedAmount,
            usersSharesToMint
        );
    }

    /**
     * @dev Allows a user to withdraw tokens from the vault by redeeming their shares.
     * @param _shares The number of shares to redeem.
     */
    function withdraw(uint256 _shares) external nonReentrant whenNotPaused {
        require(_shares > 0, AmountMustBeGreaterThanZero());
        require(userShares[msg.sender] >= _shares, InsufficientShares());

        uint256 amountToWithdraw = _shares * rate;

        totalShares -= _shares;
        userShares[msg.sender] -= _shares;
        totalDeposits -= amountToWithdraw;
        

        if (amountToWithdraw > userBalances[msg.sender]) {
            userBalances[msg.sender] = 0;
        } else {
            userBalances[msg.sender] -= amountToWithdraw;   
        }
        

        require(token.transfer(msg.sender, amountToWithdraw), TransferFailed());

        emit Withdraw(msg.sender, amountToWithdraw, _shares);
    }

    /**
     * @dev Updates the rate of tokens per share. Only callable by the owner.
     * @param _newRate The new rate in terms of token per share.
     */
    function updateRate(uint256 _newRate) external onlyOwner whenNotPaused {
        require(_newRate > 0, RateUpdateFailed());
        rate = _newRate;

        emit RateUpdate(owner(), _newRate);
    }

    /**
     * @dev Updates the manager fee. Only callable by the owner.
     * @param _newFee The new fee in basis points (1% = 100 basis points).
     */
    function updateManagerFee(
        uint256 _newFee
    ) external onlyOwner whenNotPaused {
        require(_newFee > 0, ManagerFeeUpdateFailed());
        managerFee = _newFee;

        emit ManagerFeeUpdate(owner(), _newFee);
    }

    /**
     * @dev Accumulates rewards into the vault. Only callable by the owner.
     * @param _amount The amount of tokens to add as rewards.
     */
    function accumulateRewards(
        uint256 _amount
    ) external onlyOwner nonReentrant whenNotPaused {
        require(_amount > 0, AmountMustBeGreaterThanZero());
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            RewardsAccumulationFailed()
        );

        totalDeposits += _amount;

        rate = totalDeposits / totalShares;
        emit RewardsAccumulated(owner(), _amount);
    }

    /**
     * @dev Allows the owner to withdraw manager shares from the vault.
     * @param _shares The number of shares to withdraw.
     */
    function withdrawManagerShares(
        uint256 _shares
    ) external onlyOwner nonReentrant whenNotPaused {
        require(_shares > 0, AmountMustBeGreaterThanZero());
        require(contractShares >= _shares, InsufficientShares());

        uint256 amountToWithdraw = _shares * rate;

        totalShares -= _shares;
        contractShares -= _shares;

        require(token.transfer(owner(), amountToWithdraw), TransferFailed());

        emit Withdraw(owner(), amountToWithdraw, _shares);
    }

    /**
     * @dev Pauses the contract. Only callable by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract. Only callable by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Fallback function to reject any ETH transfers.
     */
    fallback() external payable {
        revert();
    }

    /**
     * @dev Receive function to reject any ETH transfers.
     */
    receive() external payable {
        revert();
    }
}
