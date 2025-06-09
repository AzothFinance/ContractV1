// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm } from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.sol";
import {Azoth} from "src/Azoth.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract OwnershipTest is BaseTest {
    function test_RevertWhenNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                USER
            )
        );
        
        azothContract.setFeeRecipient(USER);
    }

    function test_ownershipTransfer() public {
        address newOwner = makeAddr("new owner");

        do_timelockAction(
            azothAddr,
            abi.encodeCall(Azoth.transferOwnership, (newOwner)),
            keccak256(abi.encode(nonce++))
        );

        vm.prank(newOwner);
        azothContract.acceptOwnership();

        vm.prank(newOwner);
        azothContract.setFeeRecipient(newOwner);

    }
}