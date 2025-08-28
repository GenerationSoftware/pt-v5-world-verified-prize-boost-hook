// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IWorldIdAddressBook } from "../../src/interfaces/IWorldIdAddressBook.sol";

/// @notice Mock address book that lets addresses "verify" their account by calling `setAccountVerification`.
contract MockWorldIdAddressBook is IWorldIdAddressBook {

    mapping(address => uint256) public addressVerifiedUntil;

    function setAccountVerification(uint256 verifiedUntil) external {
        addressVerifiedUntil[msg.sender] = verifiedUntil;
    }

}