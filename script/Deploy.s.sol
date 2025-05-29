// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Test, console } from "forge-std/Test.sol";

import {Azoth} from "../src/Azoth.sol";
import {TempAzoth} from "../src/misc/TempAzoth.sol";
import {Factory} from "../src/Factory.sol";
import {NFTManager} from "../src/NFTManager.sol";

contract DeployScripts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        
        Factory factory = new Factory();

        // deploy Azoth
        address feeRecipient = sender;
        TempAzoth tempazothImple = new TempAzoth();
        address proxyAzoth = UnsafeUpgrades.deployUUPSProxy(
            address(tempazothImple),
            abi.encodeCall(Azoth.initialize, (sender, feeRecipient))
        );

        // deploy NFTManager
        NFTManager nftManager = new NFTManager(proxyAzoth);
        address proxyNFTManager = UnsafeUpgrades.deployUUPSProxy(
            address(nftManager),
            ""
        );

        // upgrade azoth
        Azoth azothImple = new Azoth(address(factory), proxyNFTManager);
        UnsafeUpgrades.upgradeProxy(
            proxyAzoth,
            address(azothImple),
            ""
        );
        vm.stopBroadcast();

        console.log("============================ Deploy Contract ============================");
        console.log("Sender: ", sender);
        console.log("Azoth deployed at:", proxyAzoth);
        console.log("Factory deployed at:", address(factory));
        console.log("NFTManager deployed at:", proxyNFTManager);
    }
}