//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 public constant DEPOSIT_AMOUNT = 1e18;

    function setUp() public {
        vm.startPrank(owner);
        vm.deal(owner, DEPOSIT_AMOUNT);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantBurnAndMintRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 _rewards) public {
        (bool success,) = payable(address(vault)).call{value: _rewards}("");
    }

    function testDeposit() public {
        vm.startPrank(user);
        vm.deal(user, DEPOSIT_AMOUNT);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(rebaseToken.principleBalanceOf(user), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testDepositLinear() public {
        vm.startPrank(user);
        vm.deal(user, DEPOSIT_AMOUNT);
        //Starting Balance
        vault.deposit{value: DEPOSIT_AMOUNT}();
        vm.warp(block.timestamp + 1 hours);
        //Middle Balance
        uint256 middleBalance = rebaseToken.balanceOf(user);
        vm.warp(block.timestamp + 1 hours);
        //Ending Balance
        uint256 endingBalance = rebaseToken.balanceOf(user);
        vm.assertApproxEqAbs(endingBalance - middleBalance, middleBalance - DEPOSIT_AMOUNT, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway() public {
        vm.startPrank(user);
        vm.deal(user, DEPOSIT_AMOUNT);
        uint256 startingUserBalance = user.balance;
        //deposit
        vault.deposit{value: DEPOSIT_AMOUNT}();
        uint256 afterDepositUserBalance = user.balance;
        assertEq(rebaseToken.balanceOf(user), DEPOSIT_AMOUNT);
        //redeem
        vault.redeem(DEPOSIT_AMOUNT);
        uint256 endingUserBalance = user.balance;
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(startingUserBalance, endingUserBalance);
        assertEq(afterDepositUserBalance, startingUserBalance - DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed() public {
        vm.deal(user, DEPOSIT_AMOUNT);
        //deposit
        vm.prank(user);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        uint256 startingBalance = rebaseToken.balanceOf(user);
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        vm.prank(owner);
        addRewardsToVault(middleBalance - startingBalance);
        //calculate interest
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 timeElapsed = 1 * 60 * 60; // 1 hour in seconds
        uint256 expectedInterest = (startingBalance * userInterestRate * timeElapsed) / PRECISION_FACTOR;
        assertApproxEqAbs(middleBalance - startingBalance, expectedInterest, 1);
        //redeem after time passed
        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 endingBalance = rebaseToken.balanceOf(user);
        assertEq(endingBalance, 0);
    }
}

