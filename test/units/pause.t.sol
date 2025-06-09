// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm } from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract PauseTest is BaseTest {
    
    function test_RevertWhenPause_unpause() public {
        vm.prank(OWNER);
        azothContract.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(OWNER);
        azothContract.newRWA(RWA_Addr, "Azoth Wrapped RWA", "awRWA", USDT_Addr, MINT_FEE, REDEEM_FEE);

        vm.prank(OWNER);
        azothContract.unpause();
        vm.prank(OWNER);
        azothContract.newRWA(RWA_Addr, "Azoth Wrapped RWA", "awRWA", USDT_Addr, MINT_FEE, REDEEM_FEE);
    }

    function test_RevertWhenPasue_all() public {
        vm.startPrank(OWNER);
        azothContract.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.depositRWA(wrwaAddr, AMOUNT_DEPOSIT_RWA, MINT_PRICE);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.repay(wrwaAddr, AMOUNT_REPAY_RWA, REDEEM_PRICE);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.setFeeRecipient(address(0x123));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.setFeePercent(wrwaAddr, 1000, 1000);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.setWRWABlackList(wrwaAddr, DEADBEEF);

        vm.stopPrank();

        // passed curve pool

        vm.startPrank(USER);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.mint(wrwaAddr, AMOUNT_MINT, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.requestRedeem(wrwaAddr, AMOUNT_REQUESR_REDEEM);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        azothContract.withdrawRedeem(0);

        vm.stopPrank();
    }
}