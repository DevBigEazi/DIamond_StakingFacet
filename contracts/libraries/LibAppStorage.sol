// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Library for managing AppStorage
library LibAppStorage {
    struct StakeInfo {
        uint256 amount;
        uint256 stakedAt;
        uint256 lastClaimedAt;
        uint256 accumulatedRewards;
    }

    struct TokenType {
        bool isERC20;
        bool isERC721;
        bool isERC1155;
    }

    struct AppStorage {
        // Staking token mappings
        mapping(address => TokenType) supportedTokens;
        // User stakes
        mapping(address => mapping(address => mapping(uint256 => StakeInfo))) stakes;
        // Staking parameters
        uint256 baseAPR;
        uint256 rewardDecayRate;
        uint256 compoundingFrequency;
        // Reward token
        address rewardToken;
        // Total staked amounts per token
        mapping(address => uint256) totalStakedPerToken;
        // Withdrawal cooldown
        uint256 cooldownPeriod;
        // Stake limits
        uint256 maxStakeAmount;
        uint256 minStakeAmount;

    }

    function appStorage() internal pure returns (AppStorage storage appS) {
        assembly {
            appS.slot := 0
        }
    }
}
