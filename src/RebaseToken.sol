//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);
    error RebaseToken__TransferFailed();

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant BURN_AND_MINT_ROLE = keccak256("BURN_AND_MINT_ROLE");

    uint256 private s_interestRate = 5e10;
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 timestamp) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantBurnAndMintRole(address account) external onlyOwner returns (bool) {
        return _grantRole(BURN_AND_MINT_ROLE, account);
    }

    function setInterestRate(uint256 newInterestRate) external {
        if (newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, newInterestRate);
        }
        s_interestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    function mint(address _to, uint256 _amount) external onlyRole(BURN_AND_MINT_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function _mintAccruedInterest(address _user) private {
        uint256 principalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - principalBalance;
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    function burn(address _from, uint256 _amount) external onlyRole(BURN_AND_MINT_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRate[_to] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRate[_to] = s_userInterestRate[msg.sender];
        }
        return super.transferFrom(_from, _to, _amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        uint256 principalBalance = super.balanceOf(_user);
        // balance = principalBalance + principalBalance * interestRate * timestampDiff
        // = principleBalance(1 + (interestRate * timestampDiff))
        return principalBalance * _calculateAccumulatedUserInterestRate(_user) / PRECISION_FACTOR;
    }

    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function _calculateAccumulatedUserInterestRate(address _user) private view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        uint256 userInterestRate = s_userInterestRate[_user];

        return PRECISION_FACTOR + (userInterestRate * timeElapsed);
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
