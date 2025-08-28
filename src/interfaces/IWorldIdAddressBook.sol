// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWorldIdAddressBook {
    function addressVerifiedUntil(address account) external view returns (uint256);
}