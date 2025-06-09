// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRWAVault} from "src/interfaces/IRWAVault.sol";
import {BaseTest} from "test/BaseTest.sol";
import {FixedPointMathLib} from "src/library/FixedPointMathLib.sol";
import {NFTManager} from "src/NFTManager.sol";
import {Azoth} from "src/Azoth.sol";
import {IAzoth} from "src/interfaces/IAzoth.sol";
import {Errors} from "src/Errors.sol";

contract UserTest is BaseTest {
    using FixedPointMathLib for uint256;
    
    // ================================================================================================
    //                                  Test For mint()                     
    // ================================================================================================

    function test_mint() public {
        before_mint();

        uint256 before_VaultUSDT = USDT_Contract.balanceOf(vaultAddr);
        uint256 before_FeeReUSDT = USDT_Contract.balanceOf(FEE_RECIPIENT);
        uint256 before_UserWRWA  = wrwaContract.balanceOf(USER);

        vm.prank(USER);
        azothContract.mint(wrwaAddr, AMOUNT_MINT, 0);

        uint256 vaultGetUSDT = AMOUNT_MINT.mulWad(MINT_PRICE, DECIMAL);
        uint256 fee = AMOUNT_MINT.mulWad(MINT_PRICE, DECIMAL) * MINT_FEE / FEE_DENOMINATOR;

        assertEq(USDT_Contract.balanceOf(vaultAddr), before_VaultUSDT + vaultGetUSDT, "Mint: Vault USDT Amount");
        assertEq(USDT_Contract.balanceOf(FEE_RECIPIENT), before_FeeReUSDT + fee, "Mint: Fee");
        assertEq(wrwaContract.balanceOf(USER), before_UserWRWA + AMOUNT_MINT, "Mint: User WRWA Amount");
    }

    function test_RevertWhenAmountIsZero_mint() public {
        before_mint();

        vm.expectRevert(Errors.InvaildParam.selector);
        vm.prank(USER);
        azothContract.mint(wrwaAddr, 0, 0);
    }

    function test_RevertWhenRWANotExists_mint() public {
        before_mint();

        vm.expectRevert(Errors.RWANotExist.selector);
        vm.prank(USER);
        azothContract.mint(DEADBEEF, AMOUNT_MINT, 0);
    }

    function test_RevertWhenMintTooMuch_mint() public {
        before_mint();

        vm.expectRevert(Errors.InsufficientMintAmount.selector);
        vm.prank(USER);
        azothContract.mint(wrwaAddr, AMOUNT_DEPOSIT_RWA + 1, 0);
    }

    // ================================================================================================
    //                                  Test For quickRedeem()                     
    // ================================================================================================
    function test_quickredeem() public {
       before_requestRedeem();

        uint256 before_UserWRWA = wrwaContract.balanceOf(USER);
        uint256 before_wRWASupply = wrwaContract.totalSupply();
        uint256 before_UserUSDT = USDT_Contract.balanceOf(USER);

        vm.prank(USER);
        azothContract.quickRedeem(wrwaAddr, AMOUNT_REQUESR_REDEEM);

        uint256 value = AMOUNT_REQUESR_REDEEM.mulWad(MINT_PRICE, DECIMAL);
        uint256 netValue = value - value.mulDivUp(REDEEM_FEE, FEE_DENOMINATOR);

        // Check token balance
        assertEq(wrwaContract.balanceOf(USER), before_UserWRWA - AMOUNT_REQUESR_REDEEM, "quickRedeem: User WRWA Amount");
        assertEq(wrwaContract.totalSupply(), before_wRWASupply - AMOUNT_REQUESR_REDEEM, "quickRedeem: WRWA Supply");
        assertEq(USDT_Contract.balanceOf(USER), before_UserUSDT + netValue, "quickRedeem: user usdt");
    }

    // ================================================================================================
    //                                  Test For requestRedeem()                     
    // ================================================================================================

    function test_requestRedeem() public {
        before_requestRedeem();
        
        uint256 before_UserWRWA = wrwaContract.balanceOf(USER);
        uint256 before_wRWASupply = wrwaContract.totalSupply();
        uint256 before_AzothRWA = RWA_Contract.balanceOf(azothAddr);

        vm.prank(USER);
        azothContract.requestRedeem(wrwaAddr, AMOUNT_REQUESR_REDEEM);

        // Check token balance
        assertEq(wrwaContract.balanceOf(USER), before_UserWRWA - AMOUNT_REQUESR_REDEEM, "requestRedeem: User WRWA Amount");
        assertEq(wrwaContract.totalSupply(), before_wRWASupply - AMOUNT_REQUESR_REDEEM, "requestRedeem: WRWA Supply");
        assertEq(RWA_Contract.balanceOf(azothAddr), before_AzothRWA + AMOUNT_REQUESR_REDEEM, "requestRedeem: Azoth RWA");

        // Check NFT
        assertEq(nftManagerContract.balanceOf(USER), 1, "requestRedeem: User NFT Amount");
        assertEq(nftManagerContract.ownerOf(0), USER, "requestRedeem: NFT Owner");

        // Check NFT Redeem Info
        (address nftWRWA, uint256 amount, uint256 batchIdx, uint256 amountIdx) = nftManagerContract.getNFTRedeemInfo(0);
        assertEq(nftWRWA, wrwaAddr, "requestRedeem: NFT Info(RWA)");
        assertEq(amount, AMOUNT_REQUESR_REDEEM, "requestRedeem: NFT Info(Amount)");
        assertEq(batchIdx, 0, "requestRedeem: NFT Info(BatchIdx)");
        assertEq(amountIdx, AMOUNT_REQUESR_REDEEM, "requestRedeem: NFT Info(AmountIdx)");

        // Check RWA Redeem Info
        (uint256 redeemBatchIdx, uint256 redeemAmountIdx) = nftManagerContract.getUserRequestRedeemStatus(wrwaAddr);
        assertEq(redeemBatchIdx, 0, "requestRedeem: Redeem Info(BatchIdx)");
        assertEq(redeemAmountIdx, AMOUNT_REQUESR_REDEEM, "requestRedeem: Redeem Info(AmountIdx)");
    }

    function test_RevertWhenAmountIsZero_requestRedeem() public {
        before_requestRedeem();

        vm.expectRevert(Errors.InvaildParam.selector);
        vm.prank(USER);
        azothContract.requestRedeem(wrwaAddr,  0);
    }

    function test_RevertWhenRWANotExist_requestRedeem() public {
        before_requestRedeem();

        vm.expectRevert(Errors.RWANotExist.selector);
        vm.prank(USER);
        azothContract.requestRedeem(DEADBEEF, AMOUNT_REQUESR_REDEEM);
    }

    // ================================================================================================
    //                                  Test For requestRedeem()                     
    // ================================================================================================

    function test_withdrawRedeem() public {
        before_withdrawRedeem();

        uint256 before_VaultUSDT = USDT_Contract.balanceOf(vaultAddr);
        uint256 before_UserUSDT  = USDT_Contract.balanceOf(USER);
        uint256 before_feeUSDT   = USDT_Contract.balanceOf(FEE_RECIPIENT);

        vm.prank(USER);
        azothContract.withdrawRedeem(0);

        uint256 fee = AMOUNT_REPAY_RWA_USDT * REDEEM_FEE / FEE_DENOMINATOR;
        assertEq(USDT_Contract.balanceOf(vaultAddr), before_VaultUSDT - AMOUNT_REPAY_RWA_USDT, "withdrawRedeem: Vault USDT");
        assertEq(USDT_Contract.balanceOf(USER), before_UserUSDT + AMOUNT_REPAY_RWA_USDT - fee, "withdrawRedeem: USER USDT");
        assertEq(USDT_Contract.balanceOf(FEE_RECIPIENT), before_feeUSDT + fee, "withdrawRedeem: Fee USDT");
        
        // check nft be burn
        vm.expectRevert( abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 0) );
        nftManagerContract.ownerOf(0);
    }

    function test_RevertWhenNotOwner_withdrawRedeem() public {
        before_withdrawRedeem();

        vm.expectRevert(Errors.NotNFTOwner.selector);
        vm.prank(DEADBEEF);
        azothContract.withdrawRedeem(0);
    }
}

