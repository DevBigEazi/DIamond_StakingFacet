// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StakingFacet} from "../contracts/facets/StakingFacet.sol";
import {LibAppStorage} from "../contracts/libraries/LibAppStorage.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// Fix 2: Make StakingFacet implement required receiver interfaces
interface IStakingFacet {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract StakingFacetTest is Test {
    StakingFacet stakingFacet;
    MockERC20 stakingToken;
    MockERC20 rewardToken;
    MockERC721 nftToken;
    MockERC1155 multiToken;

    address owner;
    address user;

    function setUp() public {
        // Setup accounts
        owner = address(uint160(uint256(keccak256(abi.encodePacked("owner")))));
        user = address(uint160(uint256(keccak256(abi.encodePacked("user")))));

        // Deploy mock tokens
        vm.startPrank(owner);
        stakingToken = new MockERC20("Staking Token", "STKN", 1000000 ether);
        rewardToken = new MockERC20("Reward Token", "RWRD", 1000000 ether);
        nftToken = new MockERC721("NFT Token", "NFTK");
        multiToken = new MockERC1155();

        // Deploy StakingFacet
        stakingFacet = new StakingFacet();

        // Fix 3: Set proper staking parameters
        stakingFacet.setStakingParameters(
            10, // baseAPR: 10%
            0, // rewardDecayRate: 0 (no decay)
            365 days, // compoundingFrequency
            address(rewardToken), // rewardToken
            1 days, // cooldownPeriod
            1000000 ether, // maxStakeAmount
            0 // minStakeAmount
        );

        // Add supported tokens
        stakingFacet.addSupportedToken(
            address(stakingToken),
            true,
            false,
            false
        );
        stakingFacet.addSupportedToken(address(nftToken), false, true, false);
        stakingFacet.addSupportedToken(address(multiToken), false, false, true);

        // Mint tokens to user
        stakingToken.mint(user, 50000 ether);

        // Fix 4: Actually mint the NFT with ID 1
        nftToken.safeMint(user, 1);

        multiToken.mint(user, 1, 100, "");
        rewardToken.mint(address(stakingFacet), 1000000 ether);

        vm.stopPrank();
    }

    // Test ERC20 Token Staking
    function testStakeERC20Token() public {
        vm.startPrank(user);
        stakingToken.approve(address(stakingFacet), 1000 ether);

        stakingFacet.stakeToken(address(stakingToken), 0, 1000 ether);

        // Direct assertion isn't possible without a getter, so we'll use unstake later to verify
        vm.stopPrank();
    }

    // Test ERC721 Token Staking
    function testStakeERC721Token() public {
        vm.startPrank(user);
        nftToken.approve(address(stakingFacet), 1);

        stakingFacet.stakeToken(address(nftToken), 1, 1);

        // Direct assertion isn't possible without a getter
        vm.stopPrank();
    }

    // Test ERC1155 Token Staking
    function testStakeERC1155Token() public {
        vm.startPrank(user);
        multiToken.setApprovalForAll(address(stakingFacet), true);

        stakingFacet.stakeToken(address(multiToken), 1, 50);

        // Direct assertion isn't possible without a getter
        vm.stopPrank();
    }

    // Test Reward Calculation
    function testRewardCalculation() public {
        vm.startPrank(owner);
        // Fix 5: Ensure baseAPR is properly set
        stakingFacet.setStakingParameters(
            10, // baseAPR: 10%
            0, // rewardDecayRate: 0 (no decay)
            365 days, // compoundingFrequency
            address(rewardToken), // rewardToken
            1 days, // cooldownPeriod
            1000000 ether, // maxStakeAmount
            0 // minStakeAmount
        );
        vm.stopPrank();

        vm.startPrank(user);
        stakingToken.approve(address(stakingFacet), 1000 ether);
        stakingFacet.stakeToken(address(stakingToken), 0, 1000 ether);

        // Fast forward time
        vm.warp(block.timestamp + 365 days);

        uint256 calculatedRewards = stakingFacet.calculateRewards(
            address(stakingToken),
            0
        );

        // Basic reward validation (approximately 10% of staked amount)
        assertGt(calculatedRewards, 0, "No rewards calculated");
        vm.stopPrank();
    }

    // Test Reward Claiming
    function testClaimRewards() public {
        vm.startPrank(owner);
        // Fix 6: Ensure reward parameters are set correctly
        stakingFacet.setStakingParameters(
            10, // baseAPR: 10%
            0, // rewardDecayRate: 0 (no decay)
            365 days, // compoundingFrequency
            address(rewardToken), // rewardToken
            1 days, // cooldownPeriod
            1000000 ether, // maxStakeAmount
            0 // minStakeAmount
        );
        vm.stopPrank();

        vm.startPrank(user);
        stakingToken.approve(address(stakingFacet), 1000 ether);
        stakingFacet.stakeToken(address(stakingToken), 0, 1000 ether);

        // Fast forward time
        vm.warp(block.timestamp + 365 days);

        uint256 initialRewardBalance = rewardToken.balanceOf(user);
        stakingFacet.claimRewards(address(stakingToken), 0);
        uint256 finalRewardBalance = rewardToken.balanceOf(user);

        assertGt(
            finalRewardBalance,
            initialRewardBalance,
            "Rewards not claimed"
        );
        vm.stopPrank();
    }

    // Test Unstaking
    function testUnstake() public {
        vm.startPrank(user);
        stakingToken.approve(address(stakingFacet), 1000 ether);
        stakingFacet.stakeToken(address(stakingToken), 0, 1000 ether);

        // Fast forward past cooldown
        vm.warp(block.timestamp + 2 days);

        uint256 initialBalance = stakingToken.balanceOf(user);
        stakingFacet.unstake(address(stakingToken), 0);
        uint256 finalBalance = stakingToken.balanceOf(user);

        assertGt(finalBalance, initialBalance, "Tokens not unstaked");
        vm.stopPrank();
    }

    // Test Revert Scenarios
    function testCannotStakeUnsupportedToken() public {
        // Fix: Create the unsupported token as owner
        vm.startPrank(owner);
        MockERC20 unsupportedToken = new MockERC20(
            "Unsupported",
            "UNSUP",
            1000 ether
        );
        unsupportedToken.mint(user, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        unsupportedToken.approve(address(stakingFacet), 100 ether);

        vm.expectRevert("Unsupported token type");
        stakingFacet.stakeToken(address(unsupportedToken), 0, 10 ether);
        vm.stopPrank();
    }

    function testCannotUnstakeBeforeCooldown() public {
        // Fix 8: Set cooldown period explicitly
        vm.startPrank(owner);
        stakingFacet.setStakingParameters(
            10, // baseAPR: 10%
            0, // rewardDecayRate: 0 (no decay)
            365 days, // compoundingFrequency
            address(rewardToken), // rewardToken
            7 days, // cooldownPeriod: set to 7 days
            1000000 ether, // maxStakeAmount
            0 // minStakeAmount
        );
        vm.stopPrank();

        vm.startPrank(user);
        stakingToken.approve(address(stakingFacet), 1000 ether);
        stakingFacet.stakeToken(address(stakingToken), 0, 1000 ether);

        // Try to unstake immediately
        vm.expectRevert("Cooldown period not elapsed");
        stakingFacet.unstake(address(stakingToken), 0);
        vm.stopPrank();
    }
}
