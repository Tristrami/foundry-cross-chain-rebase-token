// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declaration
// State variables
// errors
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Validator} from "./Validator.sol";

contract MiaoToken is ERC20, Ownable, AccessControl, Validator {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The precision factor used to calculate
    uint256 private constant PRECISION_FACTOR = 1e18;

    /// @dev The TOKEN_ADMIN role. The users granted with this role can call mint and burn function
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("TOKEN_ADMIN");

    /// @dev The OWNER role
    bytes32 private constant OWNER_ROLE = keccak256("OWNER");

    /* -------------------------------------------------------------------------- */
    /*                              Storage Variables                             */
    /* -------------------------------------------------------------------------- */

    /// @dev The global interest rate per second, 18 decimal position decimal represented by uint256
    /// Token minted: 2, interest rate: 0.5 time elapsed: 3 sec, interest = 2 * 0.5 * 3
    /// @notice This can only be modified by the owner of the contract by calling the
    /// setGlobalInterestRate(uint256) function
    /// @notice The global interest rate can only **decrease**
    /// @notice Any users deposit into the protocol will take this global interest rate
    /// at the time as their own interest rate
    uint256 private s_globalInterestRate;

    /// @dev This stores each user's interest rate
    mapping(address user => uint256 interestRate) s_userInterestRate;

    /// @dev Last timestamp the user's interest is transferred to user's principle balance.
    /// This is initialized to the block time when the user deposit to the protocol for the first time
    mapping(address user => uint256 updateTimestamp) s_lastUpdateTime;

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    error MiaoToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);
    error MiaoToken__AmountToBurnExceedsBalance(uint256 amountToBurn, uint256 balance);

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    event MiaoToken__GlobalInterestRateUpdated(uint256 indexed previousInterestRate, uint256 indexed newInterestRate);
    event MiaoToken__UserInterestRateUpdated(
        address indexed user, uint256 indexed previousInterestRate, uint256 indexed newInterestRate
    );

    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    constructor() ERC20("MIAO", "MIAO") Ownable(msg.sender) {
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _grantRole(OWNER_ROLE, msg.sender);
        _setRoleAdmin(MINT_AND_BURN_ROLE, OWNER_ROLE);
        _grantRole(MINT_AND_BURN_ROLE, msg.sender);
        s_globalInterestRate = 5e10;
    }

    /* -------------------------------------------------------------------------- */
    /*                         External / Public Functions                        */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Mint token to user, and set user's interest rate as the current global interest rate
     * @param user The user address
     * @param amount The amount of token to mint
     * @notice See mint(address, uint256, uint256)
     */
    function mint(address user, uint256 amount) external notZeroAddress(user) notZeroValue(amount) onlyRole(MINT_AND_BURN_ROLE) {
        mint(user, amount, 0);
    }

    /**
     * @dev Mint token to user, and set user's interest rate
     * @param user The user address
     * @param amount The amount of token to mint
     * @param interestRate The interest rate of user
     * @notice This function can only be called by the user whose role is TOKEN_ADMIN
     * @notice If this user has interest rate, it means it's not the first time this user
     * deposits to the protocol. We need to give the accrued interest to user before minting
     * new tokens, and take the current global interest rate as user's new interest rate
     */
    function mint(address user, uint256 amount, uint256 interestRate) public notZeroAddress(user) notZeroValue(amount) onlyRole(MINT_AND_BURN_ROLE) {
        _transferAccruedInterest(user);
        _updateUserInterestRate(user, interestRate);
        _mint(user, amount);
    }

    /**
     * @dev Burn user's token
     * @param user The user address
     * @param amount The amount of token to burn, if type(uint256).max is given, all of user's
     * principle balance and pending interest will be burned
     * @notice The accrued interest will be added to user's balance before the token is burned
     * @notice This function can only be called by the user whose role is TOKEN_ADMIN
     */
    function burn(address user, uint256 amount) external notZeroAddress(user) notZeroValue(amount) onlyRole(MINT_AND_BURN_ROLE) {
        _transferAccruedInterest(user);
        uint256 balance = balanceOf(user);
        if (type(uint256).max == amount) {
            amount = balance;
        } else if (amount > balance) {
            revert MiaoToken__AmountToBurnExceedsBalance(amount, balance);
        }
        _burn(user, amount);
    }

    /**
     * @dev Set the global interest rate
     * @param interestRate New global interest rate
     * @notice This will revert if new interest rate is greater than current interest rate
     * @notice This function can only be called by the owner of the contract
     */
    function setGlobalInterestRate(uint256 interestRate) external onlyOwner notZeroValue(interestRate) {
        if (interestRate > s_globalInterestRate) {
            revert MiaoToken__InterestRateCanOnlyDecrease(s_globalInterestRate, interestRate);
        }
        uint256 globalInterestRate = s_globalInterestRate;
        s_globalInterestRate = interestRate;
        emit MiaoToken__GlobalInterestRateUpdated(globalInterestRate, interestRate);
    }

    /**
     * @dev Get user's balance
     * balance = principleBalance + interest
     * @param user The user's address
     * @return balance The sum of user's principle balance and interest at the time this function is called
     */
    function balanceOf(address user) public view override returns (uint256) {
        return super.balanceOf(user) + _getAccruedInterest(user);
    }

    /**
     * @dev Get user's principle balance
     * @param user The user's address
     * @return balance User's principle balance
     */
    function principleBalanceOf(address user) public view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Transfer `value` amount of token from msg.sender to `to`. This function will transfer the accrued
     * interest to user before transferring token
     * @param to The address of receiver
     * @param value The amount of token to transfer. If type(uint256).max is given, all of sender's token
     * (including principle balance and accrued interest) will be transferred to the receiver
     * @notice If the receiver hasn't deposited to the protocol, the interest rate of the receiver
     * will be set to the current global interest rate
     */
    function transfer(address to, uint256 value) public override returns (bool) {
        // Transfer sender's and receiver's interest before real transferring
        _transferAccruedInterest(_msgSender());
        _transferAccruedInterest(to);
        if (value == type(uint256).max) {
            value = super.balanceOf(_msgSender());
        }
        if (s_userInterestRate[to] == 0) {
            _updateUserInterestRate(to);
        }
        _transfer(_msgSender(), to, value);
        return true;
    }

    /**
     * @dev Transfer `value` amount of token from msg.sender to `to`. This function will transfer the accrued
     * interest to user before transferring token
     * @param from The address of sender
     * @param to The address of receiver
     * @param value The amount of token to transfer. If type(uint256).max is given, all of sender's token
     * (including principle balance and accrued interest) will be transferred to the receiver
     * @notice If the receiver hasn't deposited to the protocol, the interest rate of the receiver
     * will be set to the current global interest rate
     * @notice An known issue is that if the msg.sender wants to transfer all of user's token by set the 
     * `value` argument to type(uint256).max, even if the `from` user approved `balanceOf(from)` amount of 
     * token to be spent before msg.sender calling this function, it may still revert an InsufficientAllowance
     * error, because the interest may accrue during the call between `approve` function and this function 
     * Thus at the time this function is executed, the `balanceOf(from)` may greater than the previous allowance. 
     * So it's recommended to set `value` to the same amount of token as what is approved by the sender if you
     * want to transfer all of sender's token. But possibly some interest will still remain in sender's balance
     */
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        // Transfer sender's and receiver's interest before real transferring
        _transferAccruedInterest(from);
        _transferAccruedInterest(to);
        if (value == type(uint256).max) {
            value = principleBalanceOf(from);
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        if (s_userInterestRate[to] == 0) {
            _updateUserInterestRate(to);
        }
        _transfer(from, to, value);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                        Internal / Private Functions                        */
    /* -------------------------------------------------------------------------- */

    function _updateUserInterestRate(address user) private {
        _updateUserInterestRate(user, 0);
    }

    function _updateUserInterestRate(address user, uint256 interestRate) private {
        interestRate = interestRate == 0 ? s_globalInterestRate : interestRate;
        uint256 previousInterestRate = s_userInterestRate[user];
        s_userInterestRate[user] = interestRate;
        emit MiaoToken__UserInterestRateUpdated(user, previousInterestRate, interestRate);
    }

    function _getAccruedInterest(address user) private view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_lastUpdateTime[user];
        uint256 principleBalance = super.balanceOf(user);
        uint256 interestRate = s_userInterestRate[user];
        return principleBalance * interestRate * timeElapsed / PRECISION_FACTOR;
    }

    function _transferAccruedInterest(address user) private {
        if (s_userInterestRate[user] != 0) {
            _update(address(0), user, _getAccruedInterest(user));
        }
        s_lastUpdateTime[user] = block.timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Getter Functions                              */
    /* -------------------------------------------------------------------------- */

    function getOwner() public view returns (address) {
        return owner();
    }

    function getGlobalInterestRate() public view returns (uint256) {
        return s_globalInterestRate;
    }

    function getUserInterestRate(address user) public view returns (uint256) {
        return s_userInterestRate[user];
    }

    function getMintAndBurnRole() public pure returns (bytes32) {
        return MINT_AND_BURN_ROLE;
    }

    function getOwnerRole() public pure returns (bytes32) {
        return OWNER_ROLE;
    }
}
