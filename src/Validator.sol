// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Validator {
    error Validator__ValueCanNotBeZero();
    error Validator__InvalidAddress(address addr);

    modifier notZeroValue(uint256 value) {
        if (value == 0) {
            revert Validator__ValueCanNotBeZero();
        }
        _;
    }

    modifier notZeroAddress(address addr) {
        if (addr == address(0)) {
            revert Validator__InvalidAddress(addr);
        }
        _;
    }
}
