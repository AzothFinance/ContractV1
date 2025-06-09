// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.sol";
import {IAzoth} from "src/interfaces/IAzoth.sol";

contract CalcMint is BaseTest {
    function test_RWA2USDT() public {
        before_depositRWA();
        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, AMOUNT_DEPOSIT_RWA, MINT_PRICE);

        uint256 amountRWA = 10_000 * 1e18;
        uint256 amountUSDT = azothContract.calcStablecoinByWRWA(wrwaAddr, amountRWA);
        uint256 RE_amountRWA = azothContract.calcWRWAByStablecoin(wrwaAddr, amountUSDT);

        console.log("================= RWA -> USDT -> RWA =================");
        console.log("In RWA: ", amountRWA);
        console.log("Out USDT: ", amountUSDT);
        console.log("Re RWA: ", RE_amountRWA);
    }

    function test_USDT2RWA() public {
        before_depositRWA();
        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, AMOUNT_DEPOSIT_RWA, MINT_PRICE);

        uint256 amountUSDT = 10_000 * 1e6;
        uint256 amountRWA = azothContract.calcWRWAByStablecoin(wrwaAddr, amountUSDT);
        uint256 RE_amountUSDT = azothContract.calcStablecoinByWRWA(wrwaAddr, amountRWA);

        console.log("================= USDT -> RWA -> USDT =================");
        console.log("In USDT: ", amountUSDT);
        console.log("Out RWA: ", amountRWA);
        console.log("Re USDT: ", RE_amountUSDT);
    }
}