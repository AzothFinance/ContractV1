// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm } from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.sol";
import {Azoth, IAzoth} from "../../src/Azoth.sol";

contract TimelockTest is BaseTest {
    function test_RevertWhenCallTimelockFuncDirectly() public {
        vm.startPrank(OWNER);

        vm.expectRevert(IAzoth.NotAzoth.selector);
        azothContract.withdrawRWA(wrwaAddr, AMOUNT_WITHDRAW_RWA);

        vm.expectRevert(IAzoth.NotAzoth.selector);
        azothContract.withdrawStablecoin(wrwaAddr, AMOUNT_WITHDRAW_USDT);

        vm.expectRevert(IAzoth.NotAzoth.selector);
        azothContract.transferOwnership(address(0x123));

        vm.expectRevert(IAzoth.NotAzoth.selector);
        azothContract.upgradeToAndCall(address(0x123), "");

        vm.expectRevert(IAzoth.NotAzoth.selector);
        nftManagerContract.upgradeToAndCall(address(0x123), "");

        vm.stopPrank();
    }

    function test_scheduleAction_executeAction() public {
        before_withdrawStablecoin();
        uint256 before_VaultUSDT = USDT_Contract.balanceOf(vaultAddr);
        uint256 before_OwnerUSDT = USDT_Contract.balanceOf(OWNER);

        vm.prank(OWNER);
        bytes memory data = abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT));
        bytes32 salt = keccak256(abi.encode(nonce++));
        azothContract.scheduleAction(azothAddr, data, salt);

        bytes32 id = keccak256(abi.encode(azothAddr, data, salt));
        uint256 before_unlockTime = azothContract.getUnlockTimestamp(id);

        assertEq(before_unlockTime, block.timestamp + 1 days, "Timelock: scheduleAction");

        vm.warp(block.timestamp + 1 days);

        vm.prank(OWNER);
        azothContract.executeAction(azothAddr, data, salt);
        uint256 after_unlockTime = azothContract.getUnlockTimestamp(id);

        assertEq(after_unlockTime, 0, "Timelock: executeAction");
        assertEq(USDT_Contract.balanceOf(OWNER), before_OwnerUSDT + AMOUNT_WITHDRAW_USDT, "Timelock: owner USDT");
        assertEq(USDT_Contract.balanceOf(vaultAddr), before_VaultUSDT - AMOUNT_WITHDRAW_USDT, "Timelock: Vault USDT");
    }

    function test_RevertWhenActionRepeat() public {
        vm.prank(OWNER);
        bytes memory data = abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT));
        bytes32 salt = keccak256(abi.encode(nonce++));
        azothContract.scheduleAction(azothAddr, data, salt);

        vm.prank(OWNER);
        vm.expectRevert(IAzoth.ActionRepeat.selector);
        azothContract.scheduleAction(azothAddr, data, salt);
    }

    function test_RevertWhenActionNotExist() public {
        bytes memory data = abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT));
        bytes32 salt = keccak256(abi.encode(nonce++));

        vm.prank(OWNER);
        vm.expectRevert(IAzoth.ActionNotExist.selector);
        azothContract.executeAction(azothAddr, data, salt);
    }

    function test_RevertWhenActionWaiting() public {
        vm.prank(OWNER);
        bytes memory data = abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT));
        bytes32 salt = keccak256(abi.encode(nonce++));
        azothContract.scheduleAction(azothAddr, data, salt);

        vm.warp(block.timestamp + 0.5 days);

        vm.prank(OWNER);
        vm.expectRevert(IAzoth.ActionWaiting.selector);
        azothContract.executeAction(azothAddr, data, salt);
    }

    function test_RevertWhenActionExecuteFail() public {
        before_withdrawStablecoin();

        vm.prank(OWNER);
        bytes memory data = abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT + 1));
        bytes32 salt = keccak256(abi.encode(nonce++));
        azothContract.scheduleAction(azothAddr, data, salt);

        vm.warp(block.timestamp + 1 days);

        vm.prank(OWNER);
        vm.expectRevert(IAzoth.WithdrawTooMuch.selector);
        azothContract.executeAction(azothAddr, data, salt);
    }

    function test_cancelAction() public {
        vm.prank(OWNER);
        bytes memory data = abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT));
        bytes32 salt = keccak256(abi.encode(nonce++));
        azothContract.scheduleAction(azothAddr, data, salt);

        bytes32 id = keccak256(abi.encode(azothAddr, data, salt));
        vm.prank(OWNER);
        azothContract.cancelAction(id);
        uint256 unlockTime = azothContract.getUnlockTimestamp(id);

        assertEq(unlockTime, 0, "Timelock: cancelAction");
    }
}