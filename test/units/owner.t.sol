// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console, Vm} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.sol";

import {Azoth} from "../../src/Azoth.sol";
import {NFTManager} from "../../src/NFTManager.sol";
import {ERC20Mock} from "../../src/mock/ERC20Mock.sol";

import {IAzoth} from "../../src/interfaces/IAzoth.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "../../src/library/FixedPointMathLib.sol";

contract OwnerTest is BaseTest {
    using FixedPointMathLib for uint256;

    // ================================================================================================
    //                                  Test For newRWA()                     
    // ================================================================================================
    function test_newRWA() public {
        do_newRWA();

        // check wRWA & Vault deploy
        assertTrue(wrwaAddr != address(0), "SetUp: Deploy wRWA in newRWA()");
        assertTrue(vaultAddr != address(0), "SetUp: Deploy vault in newRWA()");

        // check wRWA init
        assertEq(wrwaContract.azoth(),     azothAddr,                "SetUp: wRWA init azoth");
        assertEq(wrwaContract.name(),      "Azoth Wrapped RWA",      "SetUp: wRWA init name");
        assertEq(wrwaContract.symbol(),    "azWRWA",                 "SetUp: wRWA init symbol");
        assertEq(wrwaContract.decimals(),  RWA_Contract.decimals(),  "SetUp: wRWA init decimal");

        // check Vault init
        assertEq(vaultContract.azoth(),      azothAddr,  "SetUp: vault init azoth");
        assertEq(vaultContract.RWA(),        RWA_Addr,   "SetUp: Vault init RWA");
        assertEq(vaultContract.wRWA(),       wrwaAddr,   "SetUp: Vault init wRWA");
        assertEq(vaultContract.stableCoin(), USDT_Addr,  "SetUp: Vault init StableCoin");
        assertEq(vaultContract.mintFee(),    MINT_FEE,   "SetUp: Vault init mint fee");
        assertEq(vaultContract.redeemFee(),  REDEEM_FEE, "SetUp: Vault init redeem fee");
    }

    function test_RevertWhenRWAIsZero_newRWA() public {
        vm.expectRevert(IAzoth.ZeroAddress.selector);
        vm.prank(OWNER);
        azothContract.newRWA(address(0), "Azoth Wrapped RWA", "awRWA", USDT_Addr, MINT_FEE, REDEEM_FEE);
    }

    function test_RevertWhenFeeTooBig_newRWA() public {
        vm.expectRevert(IAzoth.InvaildParam.selector);
        vm.prank(OWNER);
        azothContract.newRWA(RWA_Addr, "Azoth Wrapped RWA", "awRWA", USDT_Addr, FEE_DENOMINATOR + 1, REDEEM_FEE);

        vm.expectRevert(IAzoth.InvaildParam.selector);
        vm.prank(OWNER);
        azothContract.newRWA(RWA_Addr, "Azoth Wrapped RWA", "awRWA", USDT_Addr, MINT_FEE, FEE_DENOMINATOR + 1);

        vm.expectRevert(IAzoth.InvaildParam.selector);
        vm.prank(OWNER);
        azothContract.newRWA(RWA_Addr, "Azoth Wrapped RWA", "awRWA", USDT_Addr, FEE_DENOMINATOR + 1, FEE_DENOMINATOR + 1);
    }


    // ================================================================================================
    //                                  Test For depositRWA()                     
    // ================================================================================================
    function test_depositRWA() public {
        before_depositRWA();

        uint256 ownerRWA_Before = RWA_Contract.balanceOf(OWNER);
        uint256 vaultRWA_Before = RWA_Contract.balanceOf(vaultAddr);

        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, AMOUNT_DEPOSIT_RWA, MINT_PRICE);

        // check mintPrice and BalanceOf
        assertEq(vaultContract.mintPrice(), MINT_PRICE, "depositRWA: Mint Price");
        assertEq(RWA_Contract.balanceOf(OWNER),     ownerRWA_Before - AMOUNT_DEPOSIT_RWA, "depositRWA: Owner RWA Balance");
        assertEq(RWA_Contract.balanceOf(vaultAddr), vaultRWA_Before + AMOUNT_DEPOSIT_RWA, "depositRWA: Vault RWA Balance");

        uint256[] memory batchAmount = nftManagerContract.getBatchAmount(wrwaAddr);
        assertEq(batchAmount.length, 1, "depositRWA: Batch Length");
        assertEq(batchAmount[0], AMOUNT_DEPOSIT_RWA, "depositRWA: Batch Amount");
    }

    function test_RevertWhenParamIsZero_depositRWA() public {
        before_depositRWA();

        vm.expectRevert(IAzoth.InvaildParam.selector);  // amount is 0
        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, 0, MINT_PRICE); 

        vm.expectRevert(IAzoth.InvaildParam.selector);  // price is 0
        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, AMOUNT_DEPOSIT_RWA, 0);

        vm.expectRevert(IAzoth.InvaildParam.selector);  // amount and price are 0
        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, 0, 0);
    }

    function test_RevertWhenRWANotExists_depositRWA() public {
        before_depositRWA();

        vm.expectRevert(IAzoth.RWANotExist.selector);
        vm.prank(OWNER);
        azothContract.depositRWA(DEADBEEF, AMOUNT_DEPOSIT_RWA, MINT_PRICE);
    }


    // ================================================================================================
    //                                  Test For withdrawRWA()                     
    // ================================================================================================
    function test_withdrawRWA() public {
        before_withdrawRWA();

        uint256 azothRWA_Before = RWA_Contract.balanceOf(azothAddr);
        uint256 ownerRWA_Before = RWA_Contract.balanceOf(OWNER);
        uint256 processingAmount_Before = nftManagerContract.getProcessingAmount(wrwaAddr);

        do_timelockAction(
            azothAddr,
            abi.encodeCall(Azoth.withdrawRWA, (wrwaAddr, AMOUNT_WITHDRAW_RWA)),
            _getSaltAndUpdate()
        );

        uint256 processingAmount_After = nftManagerContract.getProcessingAmount(wrwaAddr);
        assertEq(RWA_Contract.balanceOf(azothAddr), azothRWA_Before - AMOUNT_WITHDRAW_RWA, "withdrawRWA: Azoth RWA");
        assertEq(RWA_Contract.balanceOf(OWNER),     ownerRWA_Before + AMOUNT_WITHDRAW_RWA, "withdrawRWA: Owner RWA");
        assertEq(processingAmount_After,    processingAmount_Before + AMOUNT_WITHDRAW_RWA, "withdrawRWA: processingAmount");
    }

    function test_RevertWhenAmounIsZero_withdrawRWA() public {
        before_withdrawRWA();

        do_timelockAction_ExecuteFail(
            azothAddr,
            abi.encodeCall(Azoth.withdrawRWA, (wrwaAddr, 0)),
            _getSaltAndUpdate(),
            IAzoth.InvaildParam.selector
        );
    }

    function test_RevertWhenRWANotExist_withdrawRWA() public {
        before_withdrawRWA();

        do_timelockAction_ExecuteFail(
            azothAddr,
            abi.encodeCall(Azoth.withdrawRWA, (DEADBEEF, AMOUNT_WITHDRAW_RWA)),
            _getSaltAndUpdate(),
            IAzoth.RWANotExist.selector
        );
    }

    function test_RevertWhenWithdrawTooMuch_withdrawRWA() public {
        before_withdrawRWA();

        do_timelockAction_ExecuteFail(
            azothAddr,
            abi.encodeCall(Azoth.withdrawRWA, (wrwaAddr, AMOUNT_WITHDRAW_RWA + 1)),
            _getSaltAndUpdate(),
            IAzoth.WithdrawTooMuch.selector
        );
    }


    // ================================================================================================
    //                                  Test For repay()                     
    // ================================================================================================
    function test_repay() public {
        before_repay();

        uint256 ownerUSDT_Before = USDT_Contract.balanceOf(OWNER);
        uint256 vaultUSDT_Before = USDT_Contract.balanceOf(vaultAddr);
        uint256 processingAmount_Before = nftManagerContract.getProcessingAmount(wrwaAddr);
        (uint256 processedBatchIdx_Before, uint256 processedAmountIdx_Before) = nftManagerContract.getProcessedStatus(wrwaAddr);

        vm.prank(OWNER);
        azothContract.repay(wrwaAddr, AMOUNT_REPAY_RWA, REDEEM_PRICE);

        assertEq(USDT_Contract.balanceOf(OWNER),     ownerUSDT_Before - AMOUNT_REPAY_RWA_USDT, "repay: OWNER USDT");
        assertEq(USDT_Contract.balanceOf(vaultAddr), vaultUSDT_Before + AMOUNT_REPAY_RWA_USDT, "repay: Vault USDT");
        assertEq(vaultContract.redeemPrice(), REDEEM_PRICE, "repay: Redeem Price");

        uint256 processingAmount_After = nftManagerContract.getProcessingAmount(wrwaAddr);
        (uint256 processedBatchIdx_After, uint256 processedAmountIdx_After) = nftManagerContract.getProcessedStatus(wrwaAddr); 
        assertEq(processingAmount_After,   processingAmount_Before - AMOUNT_REPAY_RWA, "repay: processingAmount");
        assertEq(processedBatchIdx_After,  processedBatchIdx_Before, "repay: processed Batch Idx");
        assertEq(processedAmountIdx_After, processedAmountIdx_Before + AMOUNT_REPAY_RWA, "repayRWA: processed Amount Idx");
        
        NFTManager.RepayInfo[][] memory redeemPriceInfos = nftManagerContract.getRepayInfo(wrwaAddr);
        assertEq(redeemPriceInfos.length,       1,                "repay: redeemPriceInfo length");
        assertEq(redeemPriceInfos[0].length,    1,                "repay: redeemPriceInfo[] length");
        assertEq(redeemPriceInfos[0][0].price,  REDEEM_PRICE,     "repay: redeem price info");
        assertEq(redeemPriceInfos[0][0].amount, AMOUNT_REPAY_RWA, "repay: redeem amount info");
    }

    function test_RevertWhenParamIsZero_repay() public {
        before_repay();

        vm.expectRevert(IAzoth.InvaildParam.selector);      // amount is 0
        vm.prank(OWNER);
        azothContract.repay(wrwaAddr, 0, REDEEM_PRICE);

        vm.expectRevert(IAzoth.InvaildParam.selector);      // price is 0
        vm.prank(OWNER);
        azothContract.repay(wrwaAddr, AMOUNT_REPAY_RWA, 0);

        vm.expectRevert(IAzoth.InvaildParam.selector);      // amount and price are 0
        vm.prank(OWNER);
        azothContract.repay(wrwaAddr, 0, 0);
    }

    function test_RevertWhenRWANotExist_repay() public {
        before_withdrawRWA();

        vm.expectRevert(IAzoth.RWANotExist.selector);
        vm.prank(OWNER);
        azothContract.repay(DEADBEEF, AMOUNT_REPAY_RWA, REDEEM_PRICE);
    }


    // ================================================================================================
    //                                  Test For withdrawUSDT()                     
    // ================================================================================================
    function test_withdrawStablecoin() public {
        before_withdrawStablecoin();

        uint256 vaultUSDT_Before = USDT_Contract.balanceOf(vaultAddr);
        uint256 ownerUSDT_Before = USDT_Contract.balanceOf(OWNER);

        do_timelockAction(
            azothAddr,
            abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, AMOUNT_WITHDRAW_USDT)),
            _getSaltAndUpdate()
        );

        assertEq(USDT_Contract.balanceOf(vaultAddr), vaultUSDT_Before - AMOUNT_WITHDRAW_USDT, "withdrawStablecoin: Vault USDT");
        assertEq(USDT_Contract.balanceOf(OWNER),     ownerUSDT_Before + AMOUNT_WITHDRAW_USDT, "withdrawStablecoin: owner USDT");
    }

    function  test_RevertWhenAmountIsZero_withdrawStablecoin() public {
        before_withdrawStablecoin();

        do_timelockAction_ExecuteFail(
            azothAddr,
            abi.encodeCall(Azoth.withdrawStablecoin, (wrwaAddr, 0)),
            _getSaltAndUpdate(),
            IAzoth.InvaildParam.selector
        );
    }

    function test_RevertWhenRWANotExist_withdrawStablecoin() public {
        before_withdrawStablecoin();

        do_timelockAction_ExecuteFail(
            azothAddr,
            abi.encodeCall(Azoth.withdrawStablecoin, (DEADBEEF, AMOUNT_WITHDRAW_USDT)),
            _getSaltAndUpdate(),
            IAzoth.RWANotExist.selector
        );
    }

    // ================================================================================================
    //                                  Test For setFeeRecipient()                     
    // ================================================================================================
    function test_setFeeRecipient() public {
        address recipient_Before = azothContract.getFeeRecipient();

        vm.prank(OWNER);
        azothContract.setFeeRecipient(address(0x88888));

        assertTrue(recipient_Before != azothContract.getFeeRecipient(), "setFeeRecipient: no new");
        assertTrue(azothContract.getFeeRecipient() == address(0x88888), "setFeeRecipient: no set");
    }

    function test_RevertWhenAddressIsZero_setFeeRecipient() public {
        vm.expectRevert(IAzoth.ZeroAddress.selector);
        vm.prank(OWNER);
        azothContract.setFeeRecipient(address(0));
    }

    // ================================================================================================
    //                                  Test For setFeePercent()                    
    // ================================================================================================
    function test_setFeePercent() public {
        do_newRWA();

        uint256 before_mintFee = vaultContract.mintFee();
        uint256 before_redeemFee = vaultContract.redeemFee();

        vm.prank(OWNER);
        azothContract.setFeePercent(wrwaAddr, 1000, 1000);
        
        assertTrue(before_mintFee != vaultContract.mintFee());
        assertTrue(before_redeemFee != vaultContract.redeemFee());
        assertEq(vaultContract.mintFee(), 1000, "setFeePercent: mintFee no new");
        assertEq(vaultContract.redeemFee(), 1000, "setFeePercent: redeemFee no new");
    }

    function test_RevertWhenTooBig_setFeePercent() public {
        do_newRWA();

        vm.expectRevert(IAzoth.InvaildParam.selector);
        vm.prank(OWNER);
        azothContract.setFeePercent(wrwaAddr, FEE_DENOMINATOR + 1, REDEEM_FEE);

        vm.expectRevert(IAzoth.InvaildParam.selector);
        vm.prank(OWNER);
        azothContract.setFeePercent(wrwaAddr, MINT_FEE, FEE_DENOMINATOR + 1);

        vm.expectRevert(IAzoth.InvaildParam.selector);
        vm.prank(OWNER);
        azothContract.setFeePercent(wrwaAddr, FEE_DENOMINATOR + 1, FEE_DENOMINATOR + 1);
    }

    function test_RevertWhenRWANotExist_setFeePercent() public {
        do_newRWA();

        vm.expectRevert(IAzoth.RWANotExist.selector);
        vm.prank(OWNER);
        azothContract.setFeePercent(DEADBEEF, 1000, 1000);
    }
}