// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm } from "forge-std/Test.sol";
import {Upgrades, UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {TempAzoth} from "../src/misc/TempAzoth.sol";
import {Azoth} from "../src/Azoth.sol";
import {Factory} from "../src/Factory.sol";
import {NFTManager} from "../src/NFTManager.sol";

import {IAzoth} from "../src/interfaces/IAzoth.sol";
import {IRWAVault} from "../src/interfaces/IRWAVault.sol";
import {IWrapRWA} from "../src/interfaces/IWrapRWA.sol";

import {WrapRWA} from "../src/WrapRWA.sol";
import {RWAVault} from "../src/RWAVault.sol";
import {ERC20Mock} from "../src/mock/ERC20Mock.sol";

import {FixedPointMathLib} from "../src/library/FixedPointMathLib.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract BaseTest is Test {
    using FixedPointMathLib for uint256;

    // ==================== Fee ======================
    uint256 constant FEE_DENOMINATOR = 1_000_000;
    uint256 constant MINT_FEE = 450;
    uint256 constant REDEEM_FEE = 450;
    
    // ================== Mint & Redeem Price ================
    uint256 constant MINT_PRICE = 1_000_000;
    uint256 constant REDEEM_PRICE = 1_200_000;

    // ==================== Amount ========================
    uint256 constant  AMOUNT_DEPOSIT_RWA = 3_000_000 * 1e18;        // depositRWA     (RWA/wRWA amount)
    uint256 constant  AMOUNT_MINT = 1_000_000 *1e18;                // mint           (RWA/wRWA amount)
    uint256 constant  AMOUNT_REQUESR_REDEEM = 500_000 * 1e18;       // requestRedeem  (RWA/wRWA amount)
    uint256 constant  AMOUNT_WITHDRAW_RWA = AMOUNT_REQUESR_REDEEM;  // withdrawRWA    (RWA/wRWA amount)
    uint256 immutable AMOUNT_REPAY_RWA = AMOUNT_REQUESR_REDEEM;     // repayRWA       (RWA/wRWA amount)
    uint256 immutable AMOUNT_REPAY_RWA_USDT = AMOUNT_REPAY_RWA.mulWad(REDEEM_PRICE, DECIMAL);  // repayRWA USDT
    uint256 immutable AMOUNT_WITHDRAW_USDT = AMOUNT_MINT.mulWad(MINT_PRICE, DECIMAL);          // withdrawUSDT (StableCoin amount)

    // ================= Mock RWA & StableCoin ====================
    ERC20Mock  immutable RWA_Contract   = new ERC20Mock("Mock RWA Token", "MRT", DECIMAL);
    ERC20Mock immutable USDT_Contract  = new ERC20Mock("Mock USDT", "USDT", 6);

    address  immutable RWA_Addr  = address(RWA_Contract);
    address  immutable USDT_Addr = address(USDT_Contract);

    // ================= Main Contract ====================
    Azoth internal azothContract;
    Factory internal factoryContract;
    NFTManager internal nftManagerContract;

    address internal azothAddr;
    address internal factoryAddr;
    address internal nftManagerAddr;

    // ================= wRWA & Vault ====================
    WrapRWA  internal wrwaContract;
    RWAVault internal vaultContract;

    address internal wrwaAddr;
    address internal vaultAddr;

    // ================ Role =================
    address internal OWNER;
    address internal USER;
    address internal FEE_RECIPIENT;
    address internal DEADBEEF;

    // ======================= Other =======================
    bool  constant IS_STABLE_POOL = true;
    uint8 constant DECIMAL = 18;
    uint256 internal nonce;


   
    function setUp() public virtual {
        // configure role
        OWNER = makeAddr("Owner");
        USER = makeAddr("User");
        FEE_RECIPIENT = makeAddr("Fee Recipient");
        DEADBEEF = makeAddr("Dead Beef Addr");

        // deploy contract
        vm.startPrank(OWNER);

        // 1. Deploy Factory 
        factoryContract = new Factory();
        factoryAddr = address(factoryContract);

        // 2. Deploy Azoth and temp Azoth imple
        TempAzoth tempazothImple = new TempAzoth();
        azothAddr = UnsafeUpgrades.deployUUPSProxy(
            address(tempazothImple),
            abi.encodeCall(Azoth.initialize, (OWNER, FEE_RECIPIENT))
        );
        azothContract = Azoth(azothAddr);

        // 3. Deploy NFTManager
        NFTManager nftManager = new NFTManager(azothAddr);
        nftManagerAddr = UnsafeUpgrades.deployUUPSProxy(
            address(nftManager),
            ""
        );
        nftManagerContract = NFTManager(nftManagerAddr);
        
        // 4. upgrade Azoth
        Azoth azothImple = new Azoth(factoryAddr, nftManagerAddr);
        UnsafeUpgrades.upgradeProxy(
            azothAddr,
            address(azothImple),
            ""
        );

        vm.stopPrank();

        // Lable Address
        vm.label(azothAddr, "Azoth");
        vm.label(factoryAddr, "Factory");
        vm.label(nftManagerAddr, "NFT Manager");
    }

    function do_newRWA() internal {
        vm.recordLogs();    // listen event

        vm.prank(OWNER);
        azothContract.newRWA(RWA_Addr, "Azoth Wrapped RWA", "azWRWA", USDT_Addr, MINT_FEE, REDEEM_FEE);

        // get wRWA and vault from the last event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (wrwaAddr, vaultAddr) = abi.decode(logs[logs.length - 1].data, (address, address));

        wrwaContract = WrapRWA(wrwaAddr);
        vaultContract = RWAVault(vaultAddr);

        vm.label(wrwaAddr, "wRWA");
        vm.label(vaultAddr, "Vault");
    }

    function before_depositRWA() internal {
        do_newRWA();

        // mint $RWA to OWNER, and OWNER approve $RWA to Azoth
        RWA_Contract.mint(OWNER, AMOUNT_DEPOSIT_RWA);
        vm.prank(OWNER);
        RWA_Contract.approve(azothAddr, AMOUNT_DEPOSIT_RWA); 
    }

    function before_mint() internal {
        // depositRWA()
        before_depositRWA();
        vm.prank(OWNER);
        azothContract.depositRWA(wrwaAddr, AMOUNT_DEPOSIT_RWA, MINT_PRICE);

        // mint $USDT to USER, and USER approve $USDT to Azoth
        uint256 usdtAmountNeed = azothContract.calcStablecoinByWRWA(wrwaAddr, AMOUNT_MINT);
        USDT_Contract.mint(USER, usdtAmountNeed); 
        vm.prank(USER);
        USDT_Contract.approve(azothAddr, usdtAmountNeed);
    }

    function before_withdrawStablecoin() internal {
        // mint()
        before_mint();
        vm.prank(USER);
        azothContract.mint(wrwaAddr, AMOUNT_MINT, 0);
    }

    function before_requestRedeem() internal {
        // mint()
        before_mint();
        vm.prank(USER);
        azothContract.mint(wrwaAddr, AMOUNT_MINT, 0);
    }

    function before_withdrawRWA() internal {
        // requestRedeem()
        before_requestRedeem();
        vm.prank(USER);
        azothContract.requestRedeem(wrwaAddr, AMOUNT_REQUESR_REDEEM);
    }

    function before_repay() internal {
        // withdrawRWA()
        before_withdrawRWA();
        do_timelockAction(
            azothAddr,
            abi.encodeCall(Azoth.withdrawRWA, (wrwaAddr, AMOUNT_WITHDRAW_RWA)),
            _getSaltAndUpdate()
        );

        // mint USDT to OWNER, and OWNER approve USDT to Azoth 
        USDT_Contract.mint(OWNER, AMOUNT_REPAY_RWA_USDT);
        vm.prank(OWNER);
        USDT_Contract.approve(azothAddr, AMOUNT_REPAY_RWA_USDT);
    }

    function before_withdrawRedeem() internal {
        // repay()
        before_repay();
        vm.prank(OWNER);
        azothContract.repay(wrwaAddr, AMOUNT_REPAY_RWA, REDEEM_PRICE);
    }

    // ========================= Timelock ==================================
    
    function do_timelockAction(address _target, bytes memory _data, bytes32 _salt) internal {
        // 1. schedule an action
        vm.prank(OWNER);
        azothContract.scheduleAction(_target, _data, _salt);

        // 2. time plus 1 days
        vm.warp(block.timestamp + 1 days);

        // 3. execute this action
        vm.prank(OWNER);
        azothContract.executeAction(_target, _data, _salt);
    }

    function do_timelockAction_ExecuteFail(address _target, bytes memory _data, bytes32 _salt, bytes4 _errorSelector) internal {
        // 1. schedule an action
        vm.prank(OWNER);
        azothContract.scheduleAction(_target, _data, _salt);

        // 2. time plus 1 days
        vm.warp(block.timestamp + 1 days);

        // 3. execute this action, and expect a error
        vm.expectRevert(_errorSelector);
        vm.prank(OWNER);
        azothContract.executeAction(_target, _data, _salt);
    }

    function _getSaltAndUpdate() internal returns(bytes32) {
        return keccak256(abi.encode(nonce++));
    }
}