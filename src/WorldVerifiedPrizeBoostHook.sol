// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPrizeHooks } from "../lib/pt-v5-vault/src/interfaces/IPrizeHooks.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { Ownable2Step, Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { IWorldIdAddressBook } from "./interfaces/IWorldIdAddressBook.sol";

/// @title PoolTogether V5 - World Verified Prize Boost Hook
/// @notice This contract is a prize hook for PoolTogether V5 that sends an additional multiplier of prize tokens to the winner
/// if the winning address is verified with a world ID.
/// @author G9 Software Inc.
contract WorldVerifiedPrizeBoostHook is Ownable2Step, IPrizeHooks {
    /// @notice Emitted when a prize win is boosted
    /// @param winner The winner of the boosted prize
    /// @param recipient The recipient of the boost
    /// @param vault The vault the prize was won through
    /// @param prizeAmount The original prize tokens won
    /// @param boostAmount The amount of boosted prize tokens sent to the recipient
    /// @param tier The prize tier won
    event VerifiedPrizeBoosted(address indexed winner, address indexed recipient, address indexed vault, uint256 prizeAmount, uint256 boostAmount, uint8 tier);

    /// @notice Emitted when the boost multiplier is set
    /// @param boostMultiplier The new boost multiplier
    event SetBoostMultiplier(uint256 boostMultiplier);

    /// @notice Emitted when the per winner boost limit is set
    /// @param perWinnerBoostLimit The new boost limit in prize tokens
    event SetPerWinnerBoostLimit(uint256 perWinnerBoostLimit);

    /// @notice Emitted when a vault's eligibility is set
    /// @param vault The vault address
    /// @param isEligible The vault's new eligibility
    event SetVaultEligibility(address indexed vault, bool isEligible);

    /// @notice The prize token used for boosting
    IERC20 public immutable PRIZE_TOKEN;

    /// @notice The world ID address book to check for address verification
    IWorldIdAddressBook public immutable WORLD_ID_ADDRESS_BOOK;

    /// @notice The prize boost multiplier
    uint256 public boostMultiplier;

    /// @notice The maximum total boost tokens that can be won by each verified address
    uint256 public perWinnerBoostLimit;

    /// @notice Eligible vault mapping
    mapping(address vault => bool eligible) public isEligibleVault;

    /// @notice The total boost tokens that have been received by an address
    mapping(address => uint256) public boostTokensReceived;

    /// @notice Constructor to set parameters for the vault hook
    /// @param _prizeToken The prize token to boost wins with
    /// @param _worldIdAddressBook The world ID address book to use for verification checks
    /// @param _initialOwner The initial owner of the vault hook
    /// @param _boostMultiplier The integer multipler that determines the boost amount from the prize won
    /// (ex. **1x** boost Multiplier will send **1x** the prize amount as a boost to the winner, effectively creating a **2x** prize multiplier)
    /// @param _perWinnerBoostLimit The initial max amount of total boosted prize tokens that will be sent to any verified address over any amount of time
    constructor(IERC20 _prizeToken, IWorldIdAddressBook _worldIdAddressBook, address _initialOwner, uint256 _boostMultiplier, uint256 _perWinnerBoostLimit) Ownable(_initialOwner) {
        PRIZE_TOKEN = _prizeToken;
        WORLD_ID_ADDRESS_BOOK = _worldIdAddressBook;
        _setBoostMultiplier(_boostMultiplier);
        _setPerWinnerBoostLimit(_perWinnerBoostLimit);
    }

    /// @inheritdoc IPrizeHooks
    /// @dev This prize hook does not implement the `beforeClaimPrize` call, but it is still required in the
    /// IPrizeHooks interface.
    function beforeClaimPrize(address, uint8, uint32, uint96, address) external pure returns (address, bytes memory) {}

    /// @inheritdoc IPrizeHooks
    /// @notice Sends `boostMultiplier` times the prize amount in *extra* prize tokens to the recipient if the winner's
    /// address is verified.
    /// @dev The sender must be an eligible vault.
    /// @dev Caps the boost amount to prevent the total amount of boost tokens the winner receives from exceeding the 
    /// `perWinnerBoostLimit`.
    /// @dev Fails silently as to not interrupt a prize claim if the prize is not eligible for a boost or if
    /// this contract runs out of boost funds.
    function afterClaimPrize(address winner, uint8 tier, uint32, uint256 prizeAmount, address recipient, bytes memory) external {
        uint256 winnerPreviousBoostReceived = boostTokensReceived[winner];
        if (
            isEligibleVault[msg.sender] &&
            winnerPreviousBoostReceived < perWinnerBoostLimit &&
            WORLD_ID_ADDRESS_BOOK.addressVerifiedUntil(winner) > block.timestamp
        ) {
            uint256 boostAmount = prizeAmount * boostMultiplier;
            if (winnerPreviousBoostReceived + boostAmount > perWinnerBoostLimit) {
                boostAmount = perWinnerBoostLimit - winnerPreviousBoostReceived;
            }
            if (
                boostAmount > 0 &&
                PRIZE_TOKEN.balanceOf(address(this)) >= boostAmount
            ) {
                boostTokensReceived[winner] += boostAmount;
                PRIZE_TOKEN.transfer(recipient, boostAmount); // boost is sent to the recipient of the prize, if different from the winner's address
                emit VerifiedPrizeBoosted(winner, recipient, msg.sender, prizeAmount, boostAmount, tier);
            }
        }
    }

    /// @notice ONLY OWNER function to withdraw funds from this contract
    /// @param _token The token to withdraw
    /// @param _to The address to send the tokens to
    /// @param _amount The amount of the token to withdraw
    function withdraw(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
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

    /// @notice ONLY OWNER function to change vault eligibility
    /// @param _vault The vault to change eligibility for
    /// @param _isEligible The vault's new eligibility
    function setVaultEligibility(address _vault, bool _isEligible) external onlyOwner {
        _setVaultEligibility(_vault, _isEligible);
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

    /// @notice Sets a vault's eligibility
    function _setVaultEligibility(address _vault, bool _isEligible) internal {
        isEligibleVault[_vault] = _isEligible;
        emit SetVaultEligibility(_vault, _isEligible);
    }
}