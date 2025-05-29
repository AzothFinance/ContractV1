// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm } from "forge-std/Test.sol";
import {NFTManager} from "../../src/NFTManager.sol";
import {ERC20Mock} from "../../src/mock/ERC20Mock.sol";

contract Handler is Test {
    NFTManager public nftManager;
    address public wRWA;
    address public TO = address(0xabcdef);

    uint256 public mintedTotalAmount = 0;
    uint256 public mintedNFTAmount = 0;
    uint256 public repayedAmount = 0;
    uint256 public callTimes = 0;

    function setNFTManager(NFTManager _nftManager) public {
        nftManager = _nftManager;
    }

    function setWRWA(address _wRWA) public {
        wRWA = _wRWA;
    }

    function mint(uint256 _amount) public {
        _amount = bound(_amount, 1e18, 500_000 * 1e18);
        mintedTotalAmount += _amount;
        mintedNFTAmount += 1;

        nftManager.mint(wRWA, _amount, TO);

        callTimes++;
    }

    function repay(uint256 _amount, uint256 _price) public {
        _amount = bound(_amount, 1e18, 500_000 * 1e18);
        _price = bound(_price, 1e6, 10_000_000);
        repayedAmount += _amount;
        nftManager.addProcessingAmount(wRWA, _amount);
        nftManager.repay(wRWA, _amount, _price);

        callTimes++;
    }
}

contract NFTManagerInvariantTest is Test {
    NFTManager private nftManager;
    Handler private handler;
    address public wRWA;

    function setUp() public  {
        wRWA = address(new ERC20Mock("wRWA", "wRWA", 18));
        // wRWA = makeAddr("wRWA");
        handler = new Handler();
        nftManager = new NFTManager(address(handler)); 
        handler.setNFTManager(nftManager);
        handler.setWRWA(wRWA);

        vm.startPrank(address(handler)); 
        for(uint256 i = 0; i < 40; i++) {
            nftManager.addBatch(wRWA, 3_000_000 * 1e18);
        }

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = Handler.mint.selector;
        selectors[1] = Handler.repay.selector;

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
        targetContract(address(handler));
    }

    // Invariants:  The total amount of user mint = the total amount calculated by batch Amount、 redeemBatchIdx and redeemAmountIdx
    function invariant_mintTotalAmount() view public {
        // get tempAmount
        uint256 tempAmount = handler.mintedTotalAmount();

        // total amount calculated by batch Amount、 redeemBatchIdx and redeemAmountIdx
        uint256[] memory batchAmount = nftManager.getBatchAmount(wRWA);
        (uint256 batchIdx, uint256 amountIdx) = nftManager.getUserRequestRedeemStatus(wRWA);
        uint256 totalAmount = 0;
        for(uint256 i = 0; i < batchIdx; i++) {
            totalAmount += batchAmount[i];
        }
        totalAmount += amountIdx;

        // check
        assertEq(tempAmount, totalAmount);

        if(handler.callTimes() == 30) {
            _testNFTVaultCalc();
        }
    }

    // Invariants: Number of times the user mints = nextTokenId in the contract
    function invariant_tokenId() view public {
        uint256 nextTokenId_fromHandler = handler.mintedNFTAmount();  // Number of times the user mints
        uint256 nextTokenId_fromNFTManager = nftManager.getNextTokenId();  // nextTokenId in the contract
        // check
        assertEq(nextTokenId_fromHandler, nextTokenId_fromNFTManager);

        if(handler.callTimes() == 30) {
            _testNFTVaultCalc();
        }
    }

    // Invariants: The total amount of official repayment = the total amount calculated by Batch Amount, processedBatchIdx, and processedAmountIdx
    function invariant_repayTotalAmount() view public {
        // The total amount calculated by Batch Amount, processedBatchIdx, and processedAmountIdx
        uint256 totalAmount;
        uint256[] memory batchAmount = nftManager.getBatchAmount(wRWA);
        (uint256 processedBatchIdx, uint256 processedAmountIdx) = nftManager.getProcessedStatus(wRWA);
        for(uint256 i = 0; i < processedBatchIdx; i++) {
            totalAmount += batchAmount[i];
        }
        totalAmount += processedAmountIdx;

        // check
        assertEq(totalAmount, handler.repayedAmount(), "invariant: repayTotalAmount");

        if(handler.callTimes() == 30) {
            _testNFTVaultCalc();
        }
    }

    function _testNFTVaultCalc() view internal {
        uint256 nextTokenId = nftManager.getNextTokenId();
        if(nextTokenId == 0) return;
        if(nftManager.getNFTTotalValue(0) == 0) return;

        // Calculated by getNFTTotalValue()
        uint256 nftAllValue = 0;
        uint256 unprocessedNFT = 0;
        for(uint256 i = 0; i < nextTokenId; i++) {
            uint256 nftValue = nftManager.getNFTTotalValue(i);
            if(nftValue != 0) {
                nftAllValue += nftValue;
            } else {
                unprocessedNFT = i;
                break;
            }
        }

        // Calculated by repayInfos
        uint256 batchIdx;
        uint256 amountIdx;
        if(unprocessedNFT == 0) {
            (, , batchIdx, amountIdx) = nftManager.getNFTRedeemInfo(nextTokenId - 1);
        } else {
            (, , batchIdx, amountIdx) = nftManager.getNFTRedeemInfo(unprocessedNFT - 1);
        }
        NFTManager.RepayInfo[][] memory repayInfos = nftManager.getRepayInfo(wRWA);
        uint256 processedValue = 0;
        for(uint256 i = 0; i < batchIdx; i++) {
            for(uint256 j = 0; j < repayInfos[i].length; j++) {
                processedValue += repayInfos[i][j].price * repayInfos[i][j].amount;
            }
        }

        uint256 tempAmountIdx;
        uint256 ii;
        for( ; tempAmountIdx + repayInfos[batchIdx][ii].amount <= amountIdx; ii++) {
            tempAmountIdx += repayInfos[batchIdx][ii].amount;
            processedValue += repayInfos[batchIdx][ii].amount * repayInfos[batchIdx][ii].price;
        }
        processedValue += repayInfos[batchIdx][ii].price * (amountIdx - tempAmountIdx);
        processedValue = processedValue / 10 ** 18;

        // Check (rough equality)
        assertApproxEqAbs(nftAllValue, processedValue, 50);
    }
}