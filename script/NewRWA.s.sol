// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Test, console, Vm } from "forge-std/Test.sol";

import {Azoth} from "src/Azoth.sol";

contract NEWRWA is Script, Test {
    address azoth = 0xD9aE19157f695c140CC45891bdEC9B467e7c1910;
    address rwa = 0x6D02ABC5fa967B0b085083F5Cf36c24502447244;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdt = vm.envAddress("USDT_ADDR");
        
        vm.startBroadcast(deployerPrivateKey);

        string memory name = "Azoth Wrapped RWA";
        string memory symbol = "awTestRWA";
        uint256 mintFee = 450;
        uint256 redeemFee = 450;

        vm.recordLogs();
        Azoth(azoth).newRWA(rwa, name, symbol, usdt, mintFee, redeemFee);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address wrwa, address vault) = abi.decode(logs[logs.length - 1].data, (address, address));

        console.log("============================== newRWA() =============================");
        console.log("Support RWA: ", rwa);
        console.log("wRWA: ", wrwa);
        console.log("vault: ", vault);

        vm.stopBroadcast();
    }
}