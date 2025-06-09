// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "src/mock/ERC20Mock.sol";
import {Test, console } from "forge-std/Test.sol";

contract CreateToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory name = "TOXIC Token For Test";
        string memory symbol = "TOXIC9";
        uint8 decimal = 9;
        
        // mock RWA
        ERC20Mock rwa = new ERC20Mock(name, symbol, decimal);
        rwa.mint(msg.sender, 1_370_000_000);
        uint256 balance = rwa.balanceOf(msg.sender);

        vm.stopBroadcast();

        console.log("======================== Deploy Mock RWA ====================");
        console.log("Deploy ", symbol, " :", address(rwa));
        console.log("Owner Balance: ", balance);
    }
}