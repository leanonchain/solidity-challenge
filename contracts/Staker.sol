//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./RewardToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ERC20 token used for staking/rewards in Staker contract
/** @dev This contract will get deployed with some tokens minted for the distribution to the stakers. And then, according to a schedule, allocate the reward tokens to addresses that deposited those tokens into the contract. Then the allocated tokens are and divide by the total balance of the deposited tokens so each depositor get's proportional share of the rewards. Ultimately, a user will deposit some tokens and later will be able to withdraw the principal amount plus the earned rewards. The following functions must be implemented: deposit(), withdraw()
 */

/// Reward manage system based on:
/// https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/MasterChefV2.sol
contract Staker is Ownable, ReentrancyGuard {
    using SafeERC20 for RewardToken;

    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    RewardToken public immutable rewardToken;
    // A big number to perform mul and div operations
    uint256 private constant STAKER_SHARE_PRECISION = 1e18;
    uint256 public lastRewardBlock;
    uint256 public accRewardTokenPerShare;
    // Info of each user that stakes tokens
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(address _rewardToken, uint256 _startBlock) {
        rewardToken = RewardToken(_rewardToken);
        lastRewardBlock = _startBlock;
    }

    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        updateStaking();
        user.amount += _amount;
        user.rewardDebt +=
            (user.amount * accRewardTokenPerShare) /
            STAKER_SHARE_PRECISION;
        rewardToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        emit Deposit(msg.sender, _amount);
    }

    function withdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "Nothing to withdraw");
        updateStaking();
        uint256 pending = (user.amount * accRewardTokenPerShare) /
            STAKER_SHARE_PRECISION -
            user.rewardDebt;
        uint256 userTotalTokens = user.amount + pending;
        user.amount = 0;
        user.rewardDebt = 0;
        if (rewardToken.isWithdrawalFeeEnabled()) {
            uint256 withdrawalFee = (userTotalTokens *
                rewardToken.withdrawalFee()) / 10000;
            userTotalTokens -= withdrawalFee;
            rewardToken.safeTransfer(rewardToken.owner(), withdrawalFee);
        }
        rewardToken.safeTransfer(msg.sender, userTotalTokens);
        emit Withdraw(msg.sender, userTotalTokens);
    }

    function updateStaking() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 totalSupply = rewardToken.balanceOf(address(this));
        if (totalSupply != 0) {
            uint256 multiplier = block.number - lastRewardBlock;
            uint256 tokenReward = multiplier * rewardToken.rewardRate();
            accRewardTokenPerShare +=
                (tokenReward * STAKER_SHARE_PRECISION) /
                totalSupply;
        }
        lastRewardBlock = block.number;
    }
}
