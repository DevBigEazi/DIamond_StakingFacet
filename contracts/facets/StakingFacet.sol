// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import { IERC165 } from "../interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingFacet is
    ReentrancyGuard,
    Ownable,
    IERC721Receiver,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;

    event TokenStaked(
        address indexed user,
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount
    );
    event RewardClaimed(
        address indexed user,
        address indexed token,
        uint256 indexed tokenId,
        uint256 rewardAmount
    );
    event TokenUnstaked(
        address indexed user,
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount
    );

    constructor() Ownable(msg.sender) {}

    // receiver interfaces implementation
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    // Stake tokens (supports ERC20, ERC721, ERC1155)
    function stakeToken(
        address token,
        uint256 tokenId,
        uint256 amount
    ) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Validate token support
        require(
            s.supportedTokens[token].isERC20 ||
                s.supportedTokens[token].isERC721 ||
                s.supportedTokens[token].isERC1155,
            "Unsupported token type"
        );

        // Stake amount validations
        if (s.minStakeAmount > 0) {
            require(amount >= s.minStakeAmount, "Below minimum stake");
        }

        if (s.maxStakeAmount > 0) {
            require(
                s.totalStakedPerToken[token] + amount <= s.maxStakeAmount,
                "Exceeds max stake limit"
            );
        }

        // Handle different token types
        if (s.supportedTokens[token].isERC20) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            _stakeERC20(token, amount);
        } else if (s.supportedTokens[token].isERC721) {
            require(
                IERC721(token).ownerOf(tokenId) == msg.sender,
                "Not token owner"
            );
            IERC721(token).safeTransferFrom(msg.sender, address(this), tokenId);
            _stakeERC721(token, tokenId);
        } else if (s.supportedTokens[token].isERC1155) {
            IERC1155(token).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                amount,
                ""
            );
            _stakeERC1155(token, tokenId, amount);
        }

        emit TokenStaked(msg.sender, token, tokenId, amount);
    }

    // Internal stake methods
    function _stakeERC20(address token, uint256 amount) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.StakeInfo storage stake = s.stakes[msg.sender][token][0];

        // Update stake info
        stake.amount += amount;
        stake.stakedAt = block.timestamp;
        stake.lastClaimedAt = block.timestamp;

        s.totalStakedPerToken[token] += amount;
    }

    function _stakeERC721(address token, uint256 tokenId) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.StakeInfo storage stake = s.stakes[msg.sender][token][
            tokenId
        ];

        // Update stake info
        stake.amount = 1;
        stake.stakedAt = block.timestamp;
        stake.lastClaimedAt = block.timestamp;

        s.totalStakedPerToken[token] += 1;
    }

    function _stakeERC1155(
        address token,
        uint256 tokenId,
        uint256 amount
    ) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.StakeInfo storage stake = s.stakes[msg.sender][token][
            tokenId
        ];

        // Update stake info
        stake.amount += amount;
        stake.stakedAt = block.timestamp;
        stake.lastClaimedAt = block.timestamp;

        s.totalStakedPerToken[token] += amount;
    }

    // Claim rewards calculation
    function calculateRewards(
        address token,
        uint256 tokenId
    ) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.StakeInfo storage stake = s.stakes[msg.sender][token][
            tokenId
        ];

        if (stake.amount == 0) return 0;

        // Calculate time since last claim
        uint256 timeSinceLastClaim = block.timestamp - stake.lastClaimedAt;
        if (timeSinceLastClaim == 0) return 0;

        // Dynamic reward calculation
        uint256 stakeDuration = block.timestamp - stake.stakedAt;

        // Base reward rate with decay
        uint256 baseReward = (stake.amount * s.baseAPR * stakeDuration) /
            (365 days * 100);

        // Apply decay rate (reduces rewards over time)
        uint256 decayFactor = s.rewardDecayRate > 0
            ? (s.rewardDecayRate ** (stakeDuration / s.compoundingFrequency))
            : 10 ** 18;

        uint256 finalReward = (baseReward * decayFactor) / (10 ** 18);

        return finalReward;
    }

    // Claim rewards
    function claimRewards(address token, uint256 tokenId) public nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.StakeInfo storage stake = s.stakes[msg.sender][token][
            tokenId
        ];

        require(stake.amount > 0, "No stake found");

        uint256 rewards = calculateRewards(token, tokenId);
        require(rewards > 0, "No rewards to claim");

        // Transfer reward token
        IERC20(s.rewardToken).safeTransfer(msg.sender, rewards);

        // Update stake info
        stake.lastClaimedAt = block.timestamp;
        stake.accumulatedRewards += rewards;

        emit RewardClaimed(msg.sender, token, tokenId, rewards);
    }

    // Unstake tokens with cooldown
    function unstake(address token, uint256 tokenId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.StakeInfo storage stake = s.stakes[msg.sender][token][
            tokenId
        ];

        uint256 amount = stake.amount;
        require(amount > 0, "No stake to withdraw");

        if (s.cooldownPeriod > 0) {
            require(
                block.timestamp >= stake.stakedAt + s.cooldownPeriod,
                "Cooldown period not elapsed"
            );
        }

        // Attempt to claim any pending rewards before unstaking
        if (calculateRewards(token, tokenId) > 0) {
            try this.claimRewards(token, tokenId) {} catch {}
        }

        // Return tokens based on type
        if (s.supportedTokens[token].isERC20) {
            IERC20(token).safeTransfer(msg.sender, amount);
        } else if (s.supportedTokens[token].isERC721) {
            IERC721(token).safeTransferFrom(address(this), msg.sender, tokenId);
        } else if (s.supportedTokens[token].isERC1155) {
            IERC1155(token).safeTransferFrom(
                address(this),
                msg.sender,
                tokenId,
                amount,
                ""
            );
        }

        // Reset stake
        s.totalStakedPerToken[token] -= amount;
        delete s.stakes[msg.sender][token][tokenId];

        emit TokenUnstaked(msg.sender, token, tokenId, amount);
    }

    // Admin functions to manage supported tokens
    function addSupportedToken(
        address token,
        bool isERC20,
        bool isERC721,
        bool isERC1155
    ) external onlyOwner {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.supportedTokens[token] = LibAppStorage.TokenType({
            isERC20: isERC20,
            isERC721: isERC721,
            isERC1155: isERC1155
        });
    }

    // Admin functions to set staking parameters
    function setStakingParameters(
        uint256 _baseAPR,
        uint256 _rewardDecayRate,
        uint256 _compoundingFrequency,
        address _rewardToken,
        uint256 _cooldownPeriod,
        uint256 _maxStakeAmount,
        uint256 _minStakeAmount
    ) external onlyOwner {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.baseAPR = _baseAPR;
        s.rewardDecayRate = _rewardDecayRate;
        s.compoundingFrequency = _compoundingFrequency;
        s.rewardToken = _rewardToken;
        s.cooldownPeriod = _cooldownPeriod;
        s.maxStakeAmount = _maxStakeAmount;
        s.minStakeAmount = _minStakeAmount;
    }

    // Implement supportsInterface to satisfy ERC-165
    function supportsInterface(
        bytes4 interfaceId
    ) external override pure returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

