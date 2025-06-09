// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Test, console, Vm } from "forge-std/Test.sol";

import {Azoth} from "src/Azoth.sol";
import {Factory} from "src/Factory.sol";
import {NFTManager} from "src/NFTManager.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ExecuteAction is Script, Test {
    address public azothProxy = 0x708517eBF0BbEC6ebe758321ef39b2ff9f87d569;
    address public factory = 0xC1688Fa0aD433997002c018DF416b8961B70bFFC;
    address public nftManager = 0x0f04C8267028d5df8d74A989A8d9d7A051e5E491;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // ======== NFT Manager Upgrade =============
        // NFTManager nftManagerImple = new NFTManager(azothProxy);
        // address nftManagerImple = 0x555EE1a0A528735dFB61f72e7D701126392853C7;
        // address target01 = nftManager;
        // bytes memory data01 = abi.encodeCall(
        //     UUPSUpgradeable.upgradeToAndCall,
        //     (address(nftManagerImple), "")
        // );
        // bytes32 salt01 = keccak256(abi.encode("nftManagerUpgrade06"));

        // ================== Azoth upgrade ==============
        // Azoth azothImple = new Azoth(factory, nftManager);
        address azothImple = 0xc42A542749072E474b099ADb9d6ebf7565DeA906;
        address target02 = azothProxy;
        bytes memory data02 = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (address(azothImple), "")
        );
        bytes32 salt02 = keccak256(abi.encode("AzothUpgrade06"));

        // Azoth(azothProxy).scheduleAction(target01, data01, salt01);
        // Azoth(azothProxy).executeAction(target01, data01, salt01);
        // Azoth(azothProxy).scheduleAction(target02, data02, salt02);
        Azoth(azothProxy).executeAction(target02, data02, salt02);

        // bytes32 id01 = keccak256(abi.encode(target01, data01, salt01));
        bytes32 id02 = keccak256(abi.encode(target02, data02, salt02));
        
        // console.log("NFTManager Imple: ", address(nftManagerImple));
        // console.log("Action Id: ", Strings.toHexString(uint256(id01), 32));
        console.log("Azoth Imple: ", address(azothImple));
        console.log("Action Id: ", Strings.toHexString(uint256(id02), 32));

        vm.stopBroadcast();
    }
}