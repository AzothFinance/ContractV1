// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console } from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.sol";
import {Azoth} from "../../src/Azoth.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
 
contract SetUpTest is BaseTest {
    function test_setUp() view public {
        // Chekc Deploy
        assertTrue(azothAddr != address(0), "SetUp: Deploy Azoth");
        assertTrue(factoryAddr != address(0), "SetUp: Deploy Factory");
        assertTrue(nftManagerAddr != address(0), "SetUp: Deploy NFTManager");

        // Check Azoth constructor
        assertEq(azothContract.factory(), factoryAddr,  "SetUp: Init Factory");
        assertEq(azothContract.nftManager(), nftManagerAddr, "SetUp: Init NFTManager");

        // Check Azoth initialize
        assertEq(azothContract.getFeeRecipient(), FEE_RECIPIENT, "SetUp: Init Fee Recipient");
        assertEq(azothContract.owner(), OWNER, "SetUp: Init Owner");

        // Check NFTManager set Azoth
        assertEq(nftManagerContract.azoth(), azothAddr, "SetUp: NFTManager set Azoth");
    }
}