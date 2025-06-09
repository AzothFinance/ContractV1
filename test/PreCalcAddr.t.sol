// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "src/mock/ERC20Mock.sol";

contract PreCalcAddr is Test {
    function test_CalcAddr() public {
        address eoa = address(0x099e801B03BdD25Aef9CD9818e30f3bF6de11e20);
        vm.startPrank(eoa);
        address addr00 = address(new ERC20Mock("T", "T", 18));
        address addr01 = address(new ERC20Mock("T", "T", 18));
        address addr02 = address(new ERC20Mock("T", "T", 18));
        address addr03 = address(new ERC20Mock("T", "T", 18));
        address addr04 = address(new ERC20Mock("T", "T", 18));
        address addr05 = address(new ERC20Mock("T", "T", 18));
        address addr06 = address(new ERC20Mock("T", "T", 18));
        address addr07 = address(new ERC20Mock("T", "T", 18));
        address addr08 = address(new ERC20Mock("T", "T", 18));
        address addr09 = address(new ERC20Mock("T", "T", 18));
        vm.stopPrank();

        console.log("Nonce 0: ", addr00);
        console.log("Nonce 1: ", addr01);
        console.log("Nonce 2: ", addr02);
        console.log("Nonce 3: ", addr03);
        console.log("Nonce 4: ", addr04);
        console.log("Nonce 5: ", addr05);
        console.log("Nonce 6: ", addr06);
        console.log("Nonce 7: ", addr07);
        console.log("Nonce 8: ", addr08);
        console.log("Nonce 9: ", addr09);
    }
}