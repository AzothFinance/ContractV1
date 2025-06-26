// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.sol";
import {Azoth} from "src/Azoth.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
 
contract SetUpTest is BaseTest {
    function test_setUp() view public {
        console.log("SetUp Azoth: ", azothAddr);
        console.log("SetUp Factory: ", factoryAddr);
        console.log("SetUp NFTManager: ", nftManagerAddr);
        
        // Chekc Deploy
        assertTrue(azothAddr != address(0), "SetUp: Deploy Azoth");
        assertTrue(factoryAddr != address(0), "SetUp: Deploy Factory");
        assertTrue(nftManagerAddr != address(0), "SetUp: Deploy NFTManager");
        // assertTrue(curvePoolManagerAddr != address(0), "SetUp: Delpoy CurvePoolManager");

        // Check Azoth constructor
        assertEq(azothContract.factory(), factoryAddr,  "SetUp: Init Factory");
        assertEq(azothContract.nftManager(), nftManagerAddr, "SetUp: Init NFTManager");
        // assertEq(azothContract.curvePoolManager(), curvePoolManagerAddr, "SetUp: Init CurvePoolManager ");

        // Check Azoth initialize
        assertEq(azothContract.getFeeRecipient(), FEE_RECIPIENT, "SetUp: Init Fee Recipient");
        assertEq(azothContract.owner(), OWNER, "SetUp: Init Owner");

        // Check NFTManager initialize
        assertEq(nftManagerContract.name(), "AzothRedeemNFT", "SetUp: NFTManager Init");
        assertEq(nftManagerContract.symbol(), "Azoth-RD-NFT", "SetUp: NFTManager Init");

        // Check NFTManager & CurvePoolManager set Azoth
        assertEq(nftManagerContract.azoth(), azothAddr, "SetUp: NFTManager set Azoth");
        // assertEq(curvePoolManagerContract.azoth(), azothAddr, "SetUp: CurvePoolManager set Azoth");
    }
}