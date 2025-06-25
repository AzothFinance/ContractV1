// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Test, console} from "forge-std/Test.sol";

import {Azoth} from "src/Azoth.sol";
import {Factory} from "src/Factory.sol";
import {NFTManager} from "src/NFTManager.sol";

contract DeployScripts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Pre Calc
        address nonce4Addr = address(0x0f04C8267028d5df8d74A989A8d9d7A051e5E491);
        
        Factory factory = new Factory();    // nonce 0

        // deploy Azoth
        address feeRecipient = sender;
        Azoth azothImple = new Azoth(address(factory), nonce4Addr);   // nonce 1
        address proxyAzoth = UnsafeUpgrades.deployUUPSProxy(          // nonce 2
            address(azothImple),
            abi.encodeCall(Azoth.initialize, (sender, feeRecipient))
        );

        // deploy NFTManager
        NFTManager nftManager = new NFTManager(proxyAzoth);          // nonce 3
        address proxyNFTManager = UnsafeUpgrades.deployUUPSProxy(    // nonce 4
            address(nftManager),
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