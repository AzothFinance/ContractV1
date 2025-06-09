// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.sol";
import {WrapRWA} from "src/WrapRWA.sol";
import {IAzoth} from "src/interfaces/IAzoth.sol";
import {Errors} from "src/Errors.sol";

contract WrapRWATest is BaseTest {
    address BAD_USER;

    function setUp() public override {
        super.setUp();
        BAD_USER = makeAddr("bad user");
    }
    
    function test_SetBlackList() public {
        do_newRWA();

        vm.prank(OWNER);
        azothContract.setWRWABlackList(wrwaAddr, BAD_USER);   // set true -> is bad
        assertEq(azothContract.inWRWABlacklist(wrwaAddr, BAD_USER), true, "wRWA: set in BlackList");

        // check transfer
        vm.prank(azothAddr);
        wrwaContract.mint(BAD_USER, 1e18);

        vm.expectRevert(Errors.Blacklisted.selector);
        vm.prank(BAD_USER);
        wrwaContract.transfer(USER, 1e18);

        // check transferFrom
        vm.prank(BAD_USER);
        wrwaContract.approve(azothAddr, 1e18);

        vm.expectRevert(Errors.Blacklisted.selector);
        vm.prank(azothAddr);
        wrwaContract.transferFrom(BAD_USER, USER, 1e18);

        vm.prank(OWNER);
        azothContract.setWRWABlackList(wrwaAddr, BAD_USER);   // set false -> is false
        assertEq(azothContract.inWRWABlacklist(wrwaAddr, BAD_USER), false, "wRWA: set out BlackList");

        // check transfer
        vm.prank(azothAddr);
        wrwaContract.mint(BAD_USER, 2e18);

        vm.prank(BAD_USER);
        wrwaContract.transfer(USER, 1e18);

        // check transferFrom
        vm.prank(BAD_USER);
        wrwaContract.approve(azothAddr, 1e18);

        vm.prank(azothAddr);
        wrwaContract.transferFrom(BAD_USER, USER, 1e18);
    }

    function test_RevertWhenRWANotExist_setWRWABlackList() public {
        do_newRWA();

        vm.expectRevert(Errors.RWANotExist.selector);
        vm.prank(OWNER);
        azothContract.setWRWABlackList(DEADBEEF, BAD_USER);
    }

    // check notAzoth
    function test_RevertWhenNotAzoth_setBlackList() public {
        do_newRWA();

        vm.expectRevert(Errors.NotAzoth.selector);
        vm.prank(USER);
        wrwaContract.setBlackList(BAD_USER);
    }
    
    function test_RevertWhenNotAzoth_mint() public {
        do_newRWA();

        vm.expectRevert(Errors.NotAzoth.selector);
        vm.prank(USER);
        wrwaContract.mint(USER, 1e18);
    }

    function test_RevertWhenNotAzoth_burn() public {
        do_newRWA();

        vm.expectRevert(Errors.NotAzoth.selector);
        vm.prank(USER);
        wrwaContract.mint(USER, 1e18);
    }
}