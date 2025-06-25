// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IAzoth} from "src/interfaces/IAzoth.sol";
import {IFactory} from "src/interfaces/IFactory.sol";
import {INFTManager} from "src/interfaces/INFTManager.sol";
import {IRWAVault} from "src/interfaces/IRWAVault.sol";
import {IWrapRWA} from "src/interfaces/IWrapRWA.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {Errors} from "src/Errors.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "src/library/FixedPointMathLib.sol";

contract Azoth is UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, IAzoth {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    //====================================================================================================
    //                                            Variables
    //====================================================================================================

    /// @notice Denominator for fee calculations. (e.g. 450 => 0.045%) 
    uint256 private constant FEE_DENOMINATOR = 1_000_000; 

    /// @notice Delay period for TimeLock
    uint256 private constant DELAY_TIME = 1 days;

    /// @notice the address of Factory Contract
    address public immutable factory;

    /// @notice the address of NFTManager Contract              
    address public immutable nftManager;

    /// @custom:storage-location erc7201:AZOTH.storage.Azoth
    struct AzothStorage {
        /// @notice the address that receives the fee
        address feeRecipient;

        /// @notice the address of the vault contract corresponds to wRWA                      
        mapping(address wRWA => address) vaults;

        /// @notice unlock time for action
        mapping(bytes32 actionId => uint256) unlockTimestamps;
    }                             

    //====================================================================================================
    //                                            Upgradability
    //====================================================================================================

    // keccak256(abi.encode(uint256(keccak256("AZOTH.storage.Azoth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant AzothStorageLocation = 
        0xd7401a6cf1440e8507caa1dba74ad41933fbb7724fa29b58c7f6cc5cd0696f00;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _getAzothStorage() private pure returns (AzothStorage storage $) {
        assembly {
            $.slot := AzothStorageLocation
        }
    }

    //====================================================================================================
    //                                            INIT
    //====================================================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _factory, address _nftManager) {
        factory = _factory;
        nftManager = _nftManager;
    }

    function initialize(address _owner, address _feeRecipient) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __Pausable_init();
        _getAzothStorage().feeRecipient = _feeRecipient;
    }

    //====================================================================================================
    //                                            Official Affairs
    //====================================================================================================

    /// @inheritdoc IAzoth
    function newRWA(
        address _rwa, 
        string memory _nameWRWA, 
        string memory _symbolWRWA,
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) external onlyOwner whenNotPaused {
        _checkAddressNotZero(_rwa);
        if(_mintFee > FEE_DENOMINATOR || _redeemFee > FEE_DENOMINATOR) revert Errors.InvaildParam();

        // Deploy $wRWA token
        address wRWA = IFactory(factory).deployWRWA(address(this), _nameWRWA, _symbolWRWA, IERC20Metadata(_rwa).decimals());
        // Deploy Vault contract
        address vault = IFactory(factory).deployVault(address(this), _rwa, wRWA, _stableCoin, _mintFee, _redeemFee);

        _getAzothStorage().vaults[wRWA] = vault;
        emit LOG_NewRWA(_rwa, wRWA, vault);
    }

    /// @inheritdoc IAzoth
    function depositRWA(address _wRWA, uint256 _amount, uint256 _mintPrice) external onlyOwner whenNotPaused {
        _check2UintNotZero(_amount, _mintPrice);
        address vault = _getAzothStorage().vaults[_wRWA];
        // Check if the asset is supported
        _checkRWAByVault(vault);

        // $RWA: owner -> vault (need approve)
        address rwa = IRWAVault(vault).RWA();
        IERC20(rwa).safeTransferFrom(msg.sender, vault, _amount);

        IRWAVault(vault).setMintPrice(_mintPrice); 
        // Record the batch amount info, which is used in the redemption logic
        INFTManager(nftManager).addBatch(_wRWA, _amount);

        emit LOG_DepositRWA(_wRWA, _amount, _mintPrice, block.timestamp);
    }

    /// @inheritdoc IAzoth
    function withdrawRWA(address _wRWA, uint256 _amount) external onlyAzoth whenNotPaused {
        _checkUintNotZero(_amount);
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);

        // the amount cannot be greater than the redemption amount requested by the user.
        // (when a user request to redeem, the corresponding amount of $RWA will be transferred from the vault to the Azoth contract)
        address rwa = IRWAVault(vault).RWA();
        if(_amount > IERC20(rwa).balanceOf(address(this))) revert Errors.WithdrawTooMuch();

        // $RWA: azoth -> owner
        IERC20(rwa).safeTransfer(owner(), _amount);

        INFTManager(nftManager).addProcessingAmount(_wRWA, _amount);

        emit LOG_WithdrawRWA(_wRWA, owner(), _amount);
    }

    /// @inheritdoc IAzoth
    function repay(address _wRWA, uint256 _amount, uint256 _redeemPrice) external onlyOwner whenNotPaused {
        _check2UintNotZero(_amount, _redeemPrice);
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);

        // stablecoin: owner -> vault
        // The amount of stablecoins = the amount of RWA repaid * the redeem price. (Approve is required)
        uint256 stablecoinAmount = _amount.mulWadUp(_redeemPrice, IERC20Metadata(_wRWA).decimals());
        IERC20(IRWAVault(vault).stableCoin()).safeTransferFrom(msg.sender, vault, stablecoinAmount);
        IRWAVault(vault).setRedeemPrice(_redeemPrice);

        // Maintain historical repayment information (amount and price) for calculate the total value of a redeemNFT
        INFTManager(nftManager).repay(_wRWA, _amount, _redeemPrice);

        emit LOG_Repay(_wRWA, _amount, _redeemPrice, stablecoinAmount); 
    }

    /// @inheritdoc IAzoth
    function withdrawStablecoin(address _wRWA, uint256 _amount) external onlyAzoth whenNotPaused {
        _checkUintNotZero(_amount);
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault); 

        // NOTE: A portion of the stablecoins is for users to withdraw, and the official cannot withdraw this portion of the stablecoins
        address stablecoin = IRWAVault(vault).stableCoin();
        uint256 withdrawableStablecoinAmount = INFTManager(nftManager).getWithdrawableStablecoinAmount(_wRWA);
        if(_amount > IERC20(stablecoin).balanceOf(vault) - withdrawableStablecoinAmount) revert Errors.WithdrawTooMuch();

        // stablecoin: vault -> owner
        IRWAVault(vault).transferERC20(IRWAVault(vault).stableCoin(), owner(), _amount);

        emit LOG_WithdrawStablecoin(_wRWA, owner(), _amount);
    }

    /// @inheritdoc IAzoth
    function lockLP(address _wRWA, address _lpToken, uint256 _amount) external onlyOwner whenNotPaused {
        _checkUintNotZero(_amount);
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        // Check if lpToken is valid
        _checkLPToken(_wRWA, _lpToken);

        // $LPToken   owner -> vault
        IERC20(_lpToken).safeTransferFrom(msg.sender, vault, _amount);
        emit LOG_LockLP(_wRWA, _lpToken, _amount);
    }

    /// @inheritdoc IAzoth
    function unlockLP(address _wRWA, address _lpToken, uint256 _amount) external onlyAzoth whenNotPaused {
        _checkUintNotZero(_amount);
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        // Check if lpToken is valid
        _checkLPToken(_wRWA, _lpToken);

        // $LPToken   vault -> owner
        IRWAVault(vault).transferERC20(_lpToken, owner(), _amount);
        emit LOG_UnlockLP(_wRWA, _lpToken, _amount);
    }


    //====================================================================================================
    //                                            User Action
    //====================================================================================================

    /// @inheritdoc IAzoth
    function mint(address _wRWA, uint256 _amountWRWA, uint256 _amountStablecoin) external whenNotPaused {
        // Check if have and only one is 0
        if((_amountWRWA == 0) == (_amountStablecoin == 0)) revert Errors.InvaildParam();

        AzothStorage storage $ = _getAzothStorage();
        address vault = $.vaults[_wRWA];  
        _checkRWAByVault(vault);

        uint8 decimal = IERC20Metadata(_wRWA).decimals();
        uint256 mintPrice = IRWAVault(vault).mintPrice();
        uint256 mintFee   = IRWAVault(vault).mintFee();
        uint256 fee;

        if(_amountWRWA != 0) {
            // Direction A: $wRWA fixed, calc stablecoin
            _amountStablecoin = _amountWRWA.mulWadUp(mintPrice, decimal);  
            fee = _amountStablecoin.mulDivUp(mintFee, FEE_DENOMINATOR);
            _amountStablecoin += fee;
        } else {
            // Direction B: stablecoin fixed, calc $wRWA
            _amountWRWA = (_amountStablecoin * FEE_DENOMINATOR).divWad(mintPrice * (FEE_DENOMINATOR + mintFee), decimal );
            fee = _amountWRWA.mulWad(mintPrice * mintFee / FEE_DENOMINATOR , decimal);
        }

        // check: amountRWA > total RWA - minted RWA
        address rwa = IRWAVault(vault).RWA();
        if(_amountWRWA > IERC20(rwa).balanceOf(vault) - IERC20(_wRWA).totalSupply()) revert Errors.InsufficientMintAmount();  

        address stableCoin = IRWAVault(vault).stableCoin(); 
        IERC20(stableCoin).safeTransferFrom(msg.sender, vault, _amountStablecoin);  // stablecoin: user -> vault
        IRWAVault(vault).transferERC20(stableCoin, $.feeRecipient, fee); // fee: vault -> feeRecipient

        IWrapRWA(_wRWA).mint(msg.sender, _amountWRWA);   // mint $wRWA to users

        emit LOG_Mint(_wRWA, msg.sender, _amountWRWA, mintPrice, block.timestamp);
    }

    /// @inheritdoc IAzoth
    function quickRedeem(address _wRWA, uint256 _amountWRWA) external whenNotPaused {
        _checkUintNotZero(_amountWRWA);

        AzothStorage storage $ = _getAzothStorage();
        address vault = $.vaults[_wRWA];
        _checkRWAByVault(vault); 

        // burn $wRWA
        IWrapRWA(_wRWA).burn(msg.sender, _amountWRWA);

        // calc the amount of stablecoin returned, and fee
        address stablecoin = IRWAVault(vault).stableCoin();
        uint256 amountStablecoin = _amountWRWA.mulWad(IRWAVault(vault).mintPrice(), IERC20Metadata(_wRWA).decimals());

        // Check if the vault has enough stablecoins
        // NOTE: A portion of the stablecoins is for users to withdraw, and quickRedeem cannot use this portion of the stablecoins
        uint256 withdrawableStablecoinAmount = INFTManager(nftManager).getWithdrawableStablecoinAmount(_wRWA);
        if(amountStablecoin > IERC20(stablecoin).balanceOf(vault) - withdrawableStablecoinAmount) revert Errors.VaultInsufficientFunds();
        uint256 fee = amountStablecoin.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR);

        IRWAVault(vault).transferERC20(stablecoin, msg.sender, amountStablecoin - fee);
        IRWAVault(vault).transferERC20(stablecoin, $.feeRecipient, fee);
        
        emit LOG_QuickRedeem(_wRWA, msg.sender, _amountWRWA, amountStablecoin - fee, block.timestamp);
    }

    /// @inheritdoc IAzoth
    function requestRedeem(address _wRWA, uint256 _amount) external whenNotPaused {
        _checkUintNotZero(_amount);
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        
        // burn the user's wRWA
        IWrapRWA(_wRWA).burn(msg.sender, _amount);

        // Transfer the corresponding amount of RWA from the vault contract to the Azoth contract. 
        // (used to record the total redemption amount of the user)
        IRWAVault(vault).transferERC20(IRWAVault(vault).RWA(), address(this), _amount);

        // mint redeem NFT to user
        INFTManager(nftManager).mint(_wRWA, _amount, msg.sender);

        emit LOG_RequestRedeem(_wRWA, msg.sender, _amount, block.timestamp);
    }

    /// @inheritdoc IAzoth
    function withdrawRedeem(uint256 _nftId) external whenNotPaused {
        (address wRWA, uint256 wrwaAmount, , ) = INFTManager(nftManager).getNFTRedeemInfo(_nftId);

        AzothStorage storage $ = _getAzothStorage();
        address vault = $.vaults[wRWA];

        // Burn NFT and calculate how many stablecoins can be withdraw
        uint256 stablecoinAmount = INFTManager(nftManager).burn(msg.sender, _nftId); 

        address stableCoin = IRWAVault(vault).stableCoin();
        uint256 fee = stablecoinAmount.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR); // usdtAmount * redeemFee / 1000000
        IRWAVault(vault).transferERC20(stableCoin, $.feeRecipient, fee);
        IRWAVault(vault).transferERC20(stableCoin, msg.sender, stablecoinAmount - fee); 

        emit LOG_WithdrawRedeem(wRWA, _nftId, msg.sender, wrwaAmount, stablecoinAmount, block.timestamp);
    }


    //====================================================================================================
    //                                        Timelock Controller
    //====================================================================================================
    /// @inheritdoc IAzoth
    function scheduleAction(address _target, bytes calldata _data, bytes32 _salt) external onlyOwner {
        AzothStorage storage $ = _getAzothStorage();

        if( !(
            _target == address(this) || 
            (_target == nftManager && bytes4(_data) == UUPSUpgradeable.upgradeToAndCall.selector)
        )) revert Errors.ActionNotAllowed();

        bytes32 id = keccak256(abi.encode(_target, _data, _salt));
        if($.unlockTimestamps[id] != 0) revert Errors.ActionRepeat();
        // set unlock time
        $.unlockTimestamps[id] = block.timestamp + DELAY_TIME;

        emit LOG_ScheduleAction(id, _target, _data, _salt, block.timestamp + DELAY_TIME);
    }

    /// @inheritdoc IAzoth
    function executeAction(address _target, bytes calldata _data, bytes32 _salt) external onlyOwner {
        AzothStorage storage $ = _getAzothStorage();

        bytes32 id = keccak256(abi.encode(_target, _data, _salt));
        uint256 unlockTime = $.unlockTimestamps[id];
        // Check if the action exists
        if(unlockTime == 0) revert Errors.ActionNotExist();
        // Check if unlocked
        if(unlockTime > block.timestamp) revert Errors.ActionWaiting();

        // Set the unlock time to 0 and execute the operation
        delete $.unlockTimestamps[id]; 
        (bool success, bytes memory returnData) = _target.call(_data);
        if(!success) {
            assembly {
                let dataSize := mload(returnData)
                revert(add(returnData, 0x20), dataSize)
            }
        }

        emit LOG_ExecuteAction(id, _target, _data);
    }

    /// @inheritdoc IAzoth
    function cancelAction(bytes32 _id) external onlyOwner {
        AzothStorage storage $ = _getAzothStorage();
        if($.unlockTimestamps[_id] == 0 ) revert Errors.ActionNotExist();
        // unlock time set to 0
        delete $.unlockTimestamps[_id];

        emit LOG_CancelAction(_id);
    }


    //====================================================================================================
    //                                            Setters
    //====================================================================================================

    /// @inheritdoc IAzoth
    function setFeeRecipient(address _newFeeRecipient) external onlyOwner whenNotPaused {
        _checkAddressNotZero(_newFeeRecipient);
        _getAzothStorage().feeRecipient = _newFeeRecipient;
        emit LOG_NewFeeRecipient(_newFeeRecipient);
    }

    /// @inheritdoc IAzoth
    function setFeePercent(address _wRWA, uint256 _newMintFee, uint256 _newRedeemFee) external onlyOwner whenNotPaused{
        // Check
        if(_newMintFee > FEE_DENOMINATOR || _newRedeemFee > FEE_DENOMINATOR) revert Errors.InvaildParam();
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault); 

        IRWAVault(vault).setFee(_newMintFee, _newRedeemFee);
        emit LOG_NewFeePercent(_wRWA, _newMintFee, _newRedeemFee); 
    }

    /// @inheritdoc IAzoth
    function setWRWABlackList(address _wRWA, address _user) external onlyOwner whenNotPaused{
        _checkRWAByVault(_getAzothStorage().vaults[_wRWA]);
        IWrapRWA(_wRWA).setBlackList(_user);   // true -> false or false -> true
        emit LOG_BlacklistUpdate(_wRWA, _user, IWrapRWA(_wRWA).isBlacklisted(_user));
    }

    /// @inheritdoc IAzoth
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IAzoth
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Permission verification for contract upgrade: Call by TimeLock.
    function _authorizeUpgrade(address _newImplementation) internal override onlyAzoth { }

    /// @notice Ownership transfer. Call by TimeLock.
    /// @notice The new owner needs to call acceptOwnership() to accept.
    /// @param newOwner The address of new owner
    /// @dev In the parent contract, _getOwnable2StepStorage() is private, so it cannot be used directly.
    function transferOwnership(address newOwner) public override onlyAzoth {
        Ownable2StepStorage storage $;
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable2Step")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 Ownable2StepStorageLocation = 0x237e158222e3e6968b72b9db0d8043aacf074ad9f650f0d1606b4d82ee432c00;
        assembly {
            $.slot := Ownable2StepStorageLocation
        }
        $._pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /// @notice Renounce the Ownership. Call by TimeLock.
    function renounceOwnership() public override onlyAzoth {
        _transferOwnership(address(0));
    }


    //====================================================================================================
    //                                            Checker
    //====================================================================================================

    function _checkAzoth() private view {
        if(msg.sender != address(this)) revert Errors.NotAzoth();
    }

    modifier onlyAzoth() {
        _checkAzoth();
        _;
    }

    function _checkUintNotZero(uint256 _a) private pure {
        if (_a == 0) revert Errors.InvaildParam();
    }

    function _check2UintNotZero(uint256 _a, uint256 _b) private pure {
        if(_a == 0 || _b == 0) revert Errors.InvaildParam();
    }

    function _checkRWAByVault(address _vault) private pure {
        if(_vault == address(0)) revert Errors.RWANotExist();  // RWA does not exist / not supported
    }

    function _checkAddressNotZero(address _addr) private pure {
        if(_addr == address(0)) revert Errors.ZeroAddress();
    }

    function _checkLPToken(address _wRWA, address _lpToken) private view {
        if(ICurvePool(_lpToken).coins(0) != _wRWA &&  ICurvePool(_lpToken).coins(1) != _wRWA) revert Errors.InvaildLPToken();
    }


    //====================================================================================================
    //                                            View
    //====================================================================================================

    /// @inheritdoc IAzoth
    function getFeeRecipient() external view returns(address) {
        return _getAzothStorage().feeRecipient;
    }

    /// @inheritdoc IAzoth
    function getRWAInfo(address _wRWA) external view returns( 
        address rwa,
        address vault, 
        address stableCoin,
        uint256 mintPrice, 
        uint256 redeemPrice, 
        uint256 mintFee,
        uint256 redeemFee
    ) {
        vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        rwa         = IRWAVault(vault).RWA();
        stableCoin  = IRWAVault(vault).stableCoin();
        mintPrice   = IRWAVault(vault).mintPrice();
        redeemPrice = IRWAVault(vault).redeemPrice();
        mintFee     = IRWAVault(vault).mintFee();
        redeemFee   = IRWAVault(vault).redeemFee();
    }

    /// @inheritdoc IAzoth
    function getVault(address _wRWA) external view returns(address) {
        return _getAzothStorage().vaults[_wRWA];
    }

    /// @inheritdoc IAzoth
    function isRedeemProcessed(uint256 _tokenId) external view returns(bool) {
        return INFTManager(nftManager).isRedeemProcessed(_tokenId);
    }

    /// @inheritdoc IAzoth
    function getNFTTotalValue(uint256 _tokenId) external view returns(uint256) {
        uint256 stablecoinAmount = INFTManager(nftManager).getNFTTotalValue(_tokenId);

        (address wRWA, , , ) = INFTManager(nftManager).getNFTRedeemInfo(_tokenId);
        uint256 redeemFee = IRWAVault(_getAzothStorage().vaults[wRWA]).redeemFee();

        return stablecoinAmount - stablecoinAmount.mulDivUp(redeemFee, FEE_DENOMINATOR);
    }

    /// @inheritdoc IAzoth
    function inWRWABlacklist(address _wRWA, address _user) external view returns(bool) {
        return IWrapRWA(_wRWA).isBlacklisted(_user);
    }

    /// @inheritdoc IAzoth
    function getUnlockTimestamp(bytes32 _id) external view returns(uint256) {
        return _getAzothStorage().unlockTimestamps[_id];
    }

    /// @inheritdoc IAzoth
    function calcStablecoinByWRWA(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin) {
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        // Formula: amountStablecoin = _amountRWA * mintPrice * (1 + mintFee / FEE_DENOMINATOR)
        amountStablecoin  = _amountWRWA.mulWadUp( IRWAVault(vault).mintPrice(), IERC20Metadata(_wRWA).decimals());
        amountStablecoin += amountStablecoin.mulDivUp(IRWAVault(vault).mintFee(), FEE_DENOMINATOR);
    }

    /// @inheritdoc IAzoth
    function calcWRWAByStablecoin(address _wRWA, uint256 _amountStablecoin) external view returns(uint256 amountWRWA) {
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        // Formula: amountWRWA * mintPrice * (1 + mintFee / FEE_DENOMINATOR) = amountStablecoin
        amountWRWA = (_amountStablecoin * FEE_DENOMINATOR).divWad( 
            IRWAVault(vault).mintPrice() * (FEE_DENOMINATOR + IRWAVault(vault).mintFee()), IERC20Metadata(_wRWA).decimals()
        );
    }

    /// @inheritdoc IAzoth
    function calcValueInQuickRedeem(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin) {
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        // Formula: amountStablecoin = amountWRWA * mintPrice * (1 - redeemFee / FEE_DENOMINATOR)
        amountStablecoin  = _amountWRWA.mulWad(IRWAVault(vault).mintPrice(), IERC20Metadata(_wRWA).decimals());
        amountStablecoin -= amountStablecoin.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR);  // subtract fee
    }
}