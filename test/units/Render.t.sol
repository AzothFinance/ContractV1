// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { NFTManager } from "src/NFTManager.sol";

contract Render is Test, NFTManager {

    constructor(address _azoth) NFTManager(_azoth) {}

    function test_getSVG() public {
        uint256 tokenId = 146;
        string memory symbol = "azTestRWA";
        uint256 amount = 500000;
        uint256 epoch = 1;
        uint256 location = 600000;
        string memory jsonContent = _render(tokenId, symbol, amount, epoch, location);
        console.log(jsonContent);
        vm.writeFile("./tokenuri", jsonContent);
    }
}