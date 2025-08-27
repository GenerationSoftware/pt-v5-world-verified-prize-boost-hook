// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "../lib/pt-v5-vault/src/interfaces/IPrizeHooks.sol";
import { PrizePool } from "../lib/pt-v5-vault/lib/pt-v5-prize-pool/src/PrizePool.sol";
import { IERC20 } from "../lib/pt-v5-vault/lib/pt-v5-prize-pool/lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { Ownable2Step, Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title PoolTogether V5 - World Verified Prize Boost Hook
/// @notice This contract is a prize hook for PoolTogether V5 that sends an additional multiplier of prize tokens to the winner
/// if the winning address is verified with a world ID.
/// @author G9 Software Inc.
contract WorldVerifiedPrizeBoostHook is Ownable2Step, IPrizeHooks {
    /// @notice Emitted when a prize win is boosted
    /// @param recipient The recipient of the prize and boost
    /// @param vault The vault the prize was won through
    /// @param prizeAmount The original prize tokens won
    /// @param boostAmount The amount of boosted prize tokens sent to the recipient
    /// @param tier The prize tier won
    event VerifiedPrizeBoosted(address indexed recipient, address indexed vault, uint256 prizeAmount, uint256 boostAmount, uint8 tier);

    /// @notice Emitted when the boost multiplier is set
    /// @param boostMultiplier The new boost multiplier
    event SetBoostMultiplier(uint256 boostMultiplier);

    /// @notice Emitted when the per winner boost limit is set
    /// @param perWinnerBoostLimit The new boost limit in prize tokens
    event SetPerWinnerBoostLimit(uint256 perWinnerBoostLimit);

    /// @notice The prize pool that is eligible for boosting
    PrizePool public immutable PRIZE_POOL;

    /// @notice The prize token used for boosting
    IERC20 public immutable PRIZE_TOKEN;

    /// @notice Mapping to keep track of boosted prizes and prevent replay attacks
    mapping(
        address vault => mapping(
            address account => mapping(
                uint24 drawId => mapping(
                    uint8 tier => mapping(
                        uint32 prizeIndex => bool hooked
                    )
                )
            )
        )
    ) public isPrizeBoosted;

    /// @notice The prize boost multiplier
    uint256 public boostMultiplier;

    /// @notice The maximum total boost tokens that can be won by each verified address
    uint256 public perWinnerBoostLimit;

    /// @notice The total boost tokens that have been received by an address
    mapping(address => uint256) public boostTokensReceived;

    /// @notice Constructor to set parameters for the vault hook
    /// @param _prizePool The prize pool to boost wins from
    /// @param _initialOwner The initial owner of the vault hook
    /// @param _boostMultiplier The integer multipler that determines the boost amount from the prize won
    /// (ex. **1x** boost Multiplier will send **1x** the prize amount as a boost to the winner, effectively creating a **2x** prize multiplier)
    /// @param _perWinnerBoostLimit The initial max amount of total boosted prize tokens that will be sent to any verified address over any amount of time
    constructor(PrizePool _prizePool, address _initialOwner, uint256 _boostMultiplier, uint256 _perWinnerBoostLimit) Ownable(_initialOwner) {
        PRIZE_POOL = _prizePool;
        PRIZE_TOKEN = _prizePool.prizeToken();
        _setBoostMultiplier(_boostMultiplier);
        _setPerWinnerBoostLimit(_perWinnerBoostLimit);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev This prize hook does not implement the `beforeClaimPrize` call, but it is still required in the
    /// IPrizeHooks interface.
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external pure returns (address, bytes memory) {}

    /// @inheritdoc IPrizeHooks
    /// @notice Sends `boostMultiplier` times the prize amount in *extra* prize tokens to the winner if the winner's address
    /// is verified and the prize hasn't already been boosted.
    /// @dev Ensures the winner is the recipient (this will always be the case on standard vaults using this hook)
    /// @dev Caps the boost amount to prevent the total amount of boost tokens the winner receives from exceeding the 
    /// `perWinnerBoostLimit`.
    /// @dev Fails silently as to not interrupt a prize claim if the prize is not eligible for a boost or if
    /// this contract runs out of boost funds.
    function afterClaimPrize(address winner, uint8 tier, uint32 prizeIndex, uint256 prizeAmount, address recipient, bytes memory) external {
        uint24 awardedDrawId = PRIZE_POOL.getLastAwardedDrawId();
        uint256 winnerPreviousBoostReceived = boostTokensReceived[winner];
        if (
            winner == recipient &&
            PRIZE_POOL.isWinner(msg.sender, winner, tier, prizeIndex) &&
            !isPrizeBoosted[msg.sender][winner][awardedDrawId][tier][prizeIndex] &&
            winnerPreviousBoostReceived < perWinnerBoostLimit
        ) {
            uint256 boostAmount = prizeAmount * boostMultiplier;
            if (winnerPreviousBoostReceived + boostAmount > perWinnerBoostLimit) {
                boostAmount = perWinnerBoostLimit - winnerPreviousBoostReceived;
            }
            if (
                boostAmount > 0 &&
                PRIZE_TOKEN.balanceOf(address(this)) >= boostAmount
            ) {
                isPrizeBoosted[msg.sender][winner][awardedDrawId][tier][prizeIndex] = true;
                PRIZE_TOKEN.transfer(winner, boostAmount);
                emit VerifiedPrizeBoosted(winner, msg.sender, prizeAmount, boostAmount, tier);
            }
        }
    }

    /// @notice ONLY OWNER function to change the boost multiplier
    /// @param _boostMultiplier The new integer boost multiplier
    function setBoostMultiplier(uint256 _boostMultiplier) external onlyOwner {
        _setBoostMultiplier(_boostMultiplier);
    }

    /// @notice ONLY OWNER function to change the per winner boost limit
    /// @param _perWinnerBoostLimit The new per winner boost limit
    function setPerWinnerBoostLimit(uint256 _perWinnerBoostLimit) external onlyOwner {
        _setPerWinnerBoostLimit(_perWinnerBoostLimit);
    }

    /// @notice Sets the boost multiplier and emits an event
    function _setBoostMultiplier(uint256 _boostMultiplier) internal {
        boostMultiplier = _boostMultiplier;
        emit SetBoostMultiplier(_boostMultiplier);
    }

    /// @notice Sets the per winner boost limit and emits an event
    function _setPerWinnerBoostLimit(uint256 _perWinnerBoostLimit) internal {
        perWinnerBoostLimit = _perWinnerBoostLimit;
        emit SetPerWinnerBoostLimit(_perWinnerBoostLimit);
    }
}