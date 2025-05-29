// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IAzoth} from "./interfaces/IAzoth.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {INFTManager} from "./interfaces/INFTManager.sol";
import {IRWAVault} from "./interfaces/IRWAVault.sol";
import {IWrapRWA} from "./interfaces/IWrapRWA.sol";
import {ICurvePool} from "./interfaces/ICurvePool.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "./library/FixedPointMathLib.sol";

/// @custom:oz-upgrades-from src/misc/TempAzoth.sol:TempAzoth
contract Azoth is UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, IAzoth {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    // ===================== constant & immutable =======================
    uint256 private constant FEE_DENOMINATOR = 1_000_000;  
    uint256 private constant DELAY_TIME = 1 days;    // for timelock

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable  
    address public immutable factory;               // Factory Contract Address                      
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable  
    address public immutable nftManager;            // NFTManager Contract Address                                   

    // =============================== ERC-7201 =================================
    /// @dev keccak256(abi.encode(uint256(keccak256("AZOTH.storage.Azoth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AzothStorageLocation = 0xd7401a6cf1440e8507caa1dba74ad41933fbb7724fa29b58c7f6cc5cd0696f00;

    /// @custom:storage-location erc7201:AZOTH.storage.Azoth
    struct AzothStorage {
        address feeRecipient;                                   
        mapping(address wRWA => address) vaults;                // $wRWA address -> vault Contract Address
        mapping(bytes32 id => uint256) unlockTimestamps;        // action id -> unlock time of Action
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _factory, address _nftManager) {
        factory = _factory;
        nftManager = _nftManager;
    }

    /// @dev It is executed in TempAzoth.sol, so it will not be executed here
    function initialize(address _owner, address _feeRecipient) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __Pausable_init();
        _getAzothStorage().feeRecipient = _feeRecipient;
    }


    // ================================================================================================
    //                                  OWNER FUNCTION && NEW RWA                     
    // ================================================================================================
    /**
     * @notice used by the owner to add/support a new RWA asset. 
     *         Inside the function: 1) deploy the wRWA contract; 2) deploy the vault contract;
     * @param  _rwa          token address of RWA asset 
     * @param  _nameWRWA     the name of the wRWA token    (used when deploying wRWA)
     * @param  _symbolWRWA   the symbol of the wRWA token  (used when deploying wRWA)
     * @param  _stableCoin   address of tokens (stablecoins, such as USDT/USDC) used to interact with wRWA/RWA
     * @param  _mintFee      mint fee   (e.g. 450 => 0.045%)
     * @param  _redeemFee    redeem fee 
     * @dev    There is no check to see if the RWA asset is added repeatedly, manual attention is required
     */
    function newRWA(
        address _rwa, 
        string memory _nameWRWA, 
        string memory _symbolWRWA,
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) external onlyOwner whenNotPaused {
        _checkAddressNotZero(_rwa);     // _rwa cannot be address(0)
        if(_mintFee > FEE_DENOMINATOR || _redeemFee > FEE_DENOMINATOR) revert InvaildParam();  // fee not greater than the denominator (fee rate <= 100%)

        // [Factory Mode] Deploy $wRWA (ERC-20 standard contract)
        address wRWA = IFactory(factory).deployWRWA(address(this), _nameWRWA, _symbolWRWA, IERC20Metadata(_rwa).decimals());

        // [Factory Mode] Deploy Vault
        address vault = IFactory(factory).deployVault(address(this), _rwa, wRWA, _stableCoin, _mintFee, _redeemFee);
        _getAzothStorage().vaults[wRWA] = vault;     // set wRWA -> rwaVault

        emit LOG_NewRWA(_rwa, wRWA, vault);
    }


    // ================================================================================================
    //                               OWNER FUNCTION && TOKEN TRANSFER                     
    // ================================================================================================

    /**
     * @notice used by the owner to deposit $RWA and set the mint price. 
     *         The function is used when the official subscribes to RWA from the fund company and deposits RWA into the protocol for users to mint.
     * @param  _wRWA       wRWA token address corresponding to the RWA asset
     * @param  _amount     Amount of $RWA deposited 
     * @param  _mintPrice  Mint price (the mint price does not include fee, also known as the 'subscription price')
     * @dev  tip1: `_amount` and `_mintPrice` cannot be 0, and the RWA asset corresponding to `_wRWA` is supported.
     * @dev  tip2: `_mintPrice` is the price of RWA relative to stablecoin. e.g. 1RWA is worth 1USDT, then `_mintPrice` should be 1000000
     */
    function depositRWA(address _wRWA, uint256 _amount, uint256 _mintPrice) external onlyOwner whenNotPaused {
        _check2UintNotZero(_amount, _mintPrice);   // cannot be 0

        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);   // Check if the asset is supported

        IRWAVault(vault).setMintPrice(_mintPrice); 

        IERC20(IRWAVault(vault).RWA()).safeTransferFrom(msg.sender, vault, _amount);  // $RWA owner -> vault (need approve)
        INFTManager(nftManager).addBatch(_wRWA, _amount);   // Maintain batch info to serve redemption logic

        emit LOG_DepositRWA(_wRWA, _amount, _mintPrice, block.timestamp);
    }


    /**
     * @notice This function is used by the owner to withdraw $RWA. 
     *         The function is used for: the official withdrawal of RWA to repay by the fund company. 
     *         (This function is a sensitive function, the owner cannot call it directly, and needs to use a delay mechanism)
     * @param  _wRWA      wRWA token address corresponding to the RWA asset
     * @param  _amount    Withdraw Amount (withdraw from azoth)
     * @dev  tip1: The RWA assets corresponding to `_wRWA` are supported.
     * @dev  tip2: `_amount` is not 0, and `_amount` cannot be greater than the redemption amount requested by the user.
     */
    function withdrawRWA(address _wRWA, uint256 _amount) external onlyAzoth whenNotPaused {
        _checkUintNotZero(_amount);

        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);

        // Check that the amount cannot be greater than the redemption amount requested by the user.
        // (when a user request to redeem, the corresponding amount of $RWA will be transferred from the vault to the Azoth contract)
        address rwa = IRWAVault(vault).RWA();
        if(_amount > IERC20(rwa).balanceOf(address(this))) revert WithdrawTooMuch();

        // $RWA: azoth -> admin
        IERC20(rwa).safeTransfer(owner(), _amount);

        INFTManager(nftManager).addProcessingAmount(_wRWA, _amount);

        emit LOG_WithdrawRWA(_wRWA, owner(), _amount);
    }


    /**
     * @notice This function is used by the owner to deposit stablecoins and set the redeem price. 
     *         The function is used to: after repaying $RWA to the fund company, deposit stablecoins for users to withdraw previously requested redemptions.
     * @param  _wRWA         wRWA token address corresponding to the RWA asset
     * @param  _amount       The amount of RWA to be repaid
     * @param  _redeemPrice  Redeem price (the redeem price does not take into account the fee, also known as the 'repayment price')
     * @dev  tip1: Amount of stablecoins deposited = Amount of RWA repaid * redeem price
     * @dev  tip2: `_wRWA` corresponding RWA assets are supported, `_amount` and `_redeemPrice` are not 0
     */
    function repay(address _wRWA, uint256 _amount, uint256 _redeemPrice) external onlyOwner whenNotPaused {
        _check2UintNotZero(_amount, _redeemPrice);  // cannot be 0

        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);    // Check if the asset is supported

        // stablecoins  owner -> vault
        // The amount of stablecoins = the amount of RWA repaid * the redeem price. (Approve is required)
        uint256 stablecoinAmount = _amount.mulWadUp(_redeemPrice, IERC20Metadata(_wRWA).decimals());
        IERC20(IRWAVault(vault).stableCoin()).safeTransferFrom(msg.sender, vault, stablecoinAmount);

        IRWAVault(vault).setRedeemPrice(_redeemPrice);

        // 1. update processedBatchIdx, processedAmountIdx
        // 2. add repay info
        // 3. update processingAmount
        INFTManager(nftManager).repay(_wRWA, _amount, _redeemPrice);
        
        emit LOG_Repay(_wRWA, _amount, _redeemPrice, stablecoinAmount); 
    }


    /**
     * @notice This function is used by the owner to withdraw stablecoins. 
     *         The function is used for: the official withdraws stablecoins to repurchase $RWA. 
     *         (This function is a sensitive function, and the owner cannot call it directly, and needs to use a delay mechanism.)
     * @param  _wRWA       wRWA token address corresponding to the RWA asset
     * @param  _amount     The amount of stablecoins to withdraw (there is no limit on the amount of withdrawal)
     */
    function withdrawStablecoin(address _wRWA, uint256 _amount) external onlyAzoth whenNotPaused {
        _checkUintNotZero(_amount);

        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault); 

        // A portion of the stablecoins is for users to withdraw, and the official cannot withdraw this portion of the stablecoins
        address stablecoin = IRWAVault(vault).stableCoin();
        uint256 withdrawableStablecoinAmount = INFTManager(nftManager).getWithdrawableStablecoinAmount(_wRWA);
        if(_amount > IERC20(stablecoin).balanceOf(vault) - withdrawableStablecoinAmount) revert WithdrawTooMuch();

        // stablecoin  vault -> owner
        IRWAVault(vault).transferERC20(IRWAVault(vault).stableCoin(), owner(), _amount);

        emit LOG_WithdrawStablecoin(_wRWA, owner(), _amount);
    }

    /**
     * @notice Lock liquidity. After the owner adds liquidity to the Curve protocol and obtains LP Token, 
     *         owner calls this function to deposit the LP Token in the vault.
     * @param _wRWA     address of $wRWA 
     * @param _lpToken  address of LP Token
     * @param _amount   the amount of deposit
     * @dev   Check whether the LP Token is really the liquidity associated with the wRWA token
     */
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

    /**
     * @notice Unlock liquidity. The owner calls this function to withdraw LP Token through the timelock mechanism.
     * @param _wRWA     wRWA token address
     * @param _lpToken  LP Token address
     * @param _amount   the amount of withdrawal
     * @dev   Check whether the LP Token is really the liquidity associated with the wRWA token
     */
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


    // ================================================================================================
    //                                  TIMELOCK CONTROLLER                     
    // ================================================================================================
    /**
     * @notice This function is used by the owner to schedule an action to be performed (sensitive operation)
     * @param  _target     Target contract, that is, the contract address called by the action
     * @param  _data       calldata, including target function and parameter information
     * @param  _salt       When _target and _data are the same, make _salt different so that the same action can wait together
     * @dev    Delay by 1 day. After unlocking the time, owner can call executeAction() to execute it
     */
    function scheduleAction(address _target, bytes calldata _data, bytes32 _salt) external onlyOwner {
        AzothStorage storage azothStorageRef = _getAzothStorage();

        if(!(_target == address(this) || (_target == nftManager && bytes4(_data) == UUPSUpgradeable.upgradeToAndCall.selector))) revert ActionNotAllowed();
        
        bytes32 id = keccak256(abi.encode(_target, _data, _salt));  // Generate the ID for this action
        if(azothStorageRef.unlockTimestamps[id] != 0) revert ActionRepeat();  // Check if the operation has been scheduled
        azothStorageRef.unlockTimestamps[id] = block.timestamp + DELAY_TIME;  // Set the unlock time for this operation (current time plus 1 day)

        emit LOG_ScheduleAction(id, _target, _data, _salt, block.timestamp + DELAY_TIME);
    }

    /**
     * @notice When the action scheduled by the scheduleAction function has been unlocked (after one day), owner can call this function to execute the action.
     * @param  _target     target contract, which is the contract address called by the action
     * @param  _data       calldata, including target function and parameter information
     * @param  _salt       When _target and _data are the same, make _salt different so that the same action can wait together
     */
    function executeAction(address _target, bytes calldata _data, bytes32 _salt) external onlyOwner {
        AzothStorage storage azothStorageRef = _getAzothStorage();

        bytes32 id = keccak256(abi.encode(_target, _data, _salt));   // Generate Action ID
        uint256 unlockTime = azothStorageRef.unlockTimestamps[id];   // Get the unlock time for this action
        if(unlockTime == 0) revert ActionNotExist();                 // Requires action to exist
        if(unlockTime > block.timestamp) revert ActionWaiting();     // Check if unlocked

        // Set the unlock time to 0 and execute the operation
        delete azothStorageRef.unlockTimestamps[id]; 
        (bool success, bytes memory returnData) = _target.call(_data);
        if(!success) {
            assembly {
                let dataSize := mload(returnData)
                revert(add(returnData, 0x20), dataSize)
            }
        }

        emit LOG_ExecuteAction(id, _target, _data);
    }

    /**
     * @notice used by the owner to cancel an action.
     * @param  _id   action id
     */
    function cancelAction(bytes32 _id) external onlyOwner {
        AzothStorage storage azothStorageRef = _getAzothStorage();
        if(azothStorageRef.unlockTimestamps[_id] == 0 ) revert ActionNotExist();   // Requires action is Existing
        delete azothStorageRef.unlockTimestamps[_id];       // unlock time is set to 0

        emit LOG_CancelAction(_id);
    }

    // ================================================================================================
    //                                  OTHER OWNER FUNCTION && FEE                     
    // ================================================================================================
    /**
     * @notice This function is used by the owner to set the recipient of fees
     * @param  _newFeeRecipient address of new Recipient
     */
    function setFeeRecipient(address _newFeeRecipient) external onlyOwner whenNotPaused {
        _checkAddressNotZero(_newFeeRecipient);
        _getAzothStorage().feeRecipient = _newFeeRecipient;
        emit LOG_NewFeeRecipient(_newFeeRecipient);
    }

    /**
     * @notice This function is used by the owner to set the fee (mintfee and redeemfee) for a certain wRWA
     * @param  _wRWA            wRWA token address corresponding to the RWA asset
     * @param  _newMintFee      new mint fee
     * @param  _newRedeemFee    new redeem fee
     */
    function setFeePercent(address _wRWA, uint256 _newMintFee, uint256 _newRedeemFee) external onlyOwner whenNotPaused{
        if(_newMintFee > FEE_DENOMINATOR || _newRedeemFee > FEE_DENOMINATOR) revert InvaildParam();  // not greater than 1000000
        
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault); 

        IRWAVault(vault).setFee(_newMintFee, _newRedeemFee);   // set fee
        
        emit LOG_NewFeePercent(_wRWA, _newMintFee, _newRedeemFee); 
    }

    /**
     * @notice This function is used by the owner to set the blacklist of wRWA tokens. 
     *         Blacklisted users cannot transfer tokens (true -> false or false -> true)
     * @param  _wRWA      address of wRWA
     * @param  _user      user for setting
     */
    function setWRWABlackList(address _wRWA, address _user) external onlyOwner whenNotPaused{
        _checkRWAByVault(_getAzothStorage().vaults[_wRWA]);
        IWrapRWA(_wRWA).setBlackList(_user);    // Set blacklist
    }

 
    // ================================================================================================
    //                                        USER FUNCTION                     
    // ================================================================================================

    /**
     * @notice Users use stablecoins to mint $wRWA. (`_amountRWA` and `_amountStablecoin`, have and only one is 0)
     * @param  _wRWA               address of $wRWA token
     * @param  _amountWRWA         amount of $wRWA want to mint
     * @param  _amountStablecoin   amount of stablecoins used to mint
     * @dev Formula: amountStablecoin = _amountRWA * mintPrice * (1 + feePercent / FEE_DENOMINATOR)
     */
    function mint(address _wRWA, uint256 _amountWRWA, uint256 _amountStablecoin) external whenNotPaused {
        if((_amountWRWA == 0) == (_amountStablecoin == 0)) revert InvaildParam();  // Check if have and only one is 0

        AzothStorage storage azothStorage = _getAzothStorage();
        address vault = azothStorage.vaults[_wRWA];  
        _checkRWAByVault(vault);     // Check if the asset is supported

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
        if(_amountWRWA > IERC20(rwa).balanceOf(vault) - IERC20(_wRWA).totalSupply()) revert InsufficientMintAmount();  

        address stableCoin = IRWAVault(vault).stableCoin(); 
        IERC20(stableCoin).safeTransferFrom(msg.sender, vault, _amountStablecoin);  // stablecoin: user -> vault
        IRWAVault(vault).transferERC20(stableCoin, azothStorage.feeRecipient, fee); // fee: vault -> feeRecipient

        IWrapRWA(_wRWA).mint(msg.sender, _amountWRWA);   // mint $wRWA to users

        emit LOG_Mint(_wRWA, msg.sender, _amountWRWA, mintPrice, block.timestamp);
    }

    /**
     * @notice used for quick redemption, using `mintPrice` and `redeemFee` to calculate the redeemable stablecoin
     *         Condition: There are enough stablecoins in the vault
     * @param  _wRWA         address of $wRWA token
     * @param  _amountWRWA   amount of $wRWA to be redeemed
     */
    function quickRedeem(address _wRWA, uint256 _amountWRWA) external whenNotPaused {
        _checkUintNotZero(_amountWRWA);

        AzothStorage storage azothStorage = _getAzothStorage();
        address vault = azothStorage.vaults[_wRWA];
        _checkRWAByVault(vault);

        // burn $wRWA
        IWrapRWA(_wRWA).burn(msg.sender, _amountWRWA);

        // calc the amount of stablecoin returned, and fee
        address stablecoin = IRWAVault(vault).stableCoin();
        uint256 amountStablecoin = _amountWRWA.mulWad(IRWAVault(vault).mintPrice(), IERC20Metadata(_wRWA).decimals());
        uint256 withdrawableStablecoinAmount = INFTManager(nftManager).getWithdrawableStablecoinAmount(_wRWA);

        if(amountStablecoin > IERC20(stablecoin).balanceOf(vault) - withdrawableStablecoinAmount) revert VaultInsufficientFunds();
        uint256 fee = amountStablecoin.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR);

        IRWAVault(vault).transferERC20(stablecoin, msg.sender, amountStablecoin - fee);
        IRWAVault(vault).transferERC20(stablecoin, azothStorage.feeRecipient, fee);
        
        emit LOG_QuickRedeem(_wRWA, msg.sender, _amountWRWA, amountStablecoin - fee, block.timestamp);
    }


    /**
     * @notice Users request to redeem stablecoins, and mint NFTs are given to users as redemption vouchers.
     * @param  _wRWA        wRWA token address corresponding to the RWA asset
     * @param  _amount      The amount of $wRWA to be redeemed
     */
    function requestRedeem(address _wRWA, uint256 _amount) external whenNotPaused {
        _checkUintNotZero(_amount); 

        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault); 
        
        // burn the user's wRWA
        IWrapRWA(_wRWA).burn(msg.sender, _amount);

        // $RWA: vault -> azoth 
        // (used to record the total redemption amount of the user)
        IRWAVault(vault).transferERC20(IRWAVault(vault).RWA(), address(this), _amount);

        // mint redeem NFT to the user
        INFTManager(nftManager).mint(_wRWA, _amount, msg.sender);

        emit LOG_RequestRedeem(_wRWA, msg.sender, _amount, block.timestamp); 
    }

    /**
     * @notice Users use NFT to extract stablecoin
     * @param  _nftId      tokenId of NFT
     */
    function withdrawRedeem(uint256 _nftId) external whenNotPaused {
        (address wRWA, uint256 wrwaAmount, , ) = INFTManager(nftManager).getNFTRedeemInfo(_nftId);

        AzothStorage storage azothStorage = _getAzothStorage();
        address vault = azothStorage.vaults[wRWA];

        // burn NFT and calculate how many stablecoins can be withdraw
        uint256 stablecoinAmount = INFTManager(nftManager).burn(msg.sender, _nftId); 

        uint256 fee = stablecoinAmount.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR); // fee = stablecoinAmount * redeemFee / 1000000
        address stableCoin = IRWAVault(vault).stableCoin();
        IRWAVault(vault).transferERC20(stableCoin, azothStorage.feeRecipient, fee);
        IRWAVault(vault).transferERC20(stableCoin, msg.sender, stablecoinAmount - fee); 

        emit LOG_WithdrawRedeem(wRWA, _nftId, msg.sender, wrwaAmount, stablecoinAmount, block.timestamp);
    }

    // ============ override ============
    /// @notice Permission verification for contract upgrade: set it so that only Azoth can call it.
    ///         (this function is a sensitive function, the owner cannot call it directly, and needs to go through a delay mechanism)
    function _authorizeUpgrade(address _newImplementation) internal override onlyAzoth { }


    /// @notice Ownership transfer: Only Azoth can be called (this function is sensitive and cannot be directly called by the owner, requiring a delay mechanism)
    ///         The new owner needs to call acceptOwnership() to accept
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

    /// @notice this function is a sensitive function, the owner cannot call it directly, and needs to go through a delay mechanism
    function renounceOwnership() public override onlyAzoth {
        _transferOwnership(address(0));
    }


    // ========= PAUSE && UNPAUSE ==========
    /// @notice Pause the contract, only the owner can call it
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract, only the owner can call it
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ internal & private =============
    function _getAzothStorage() private pure returns (AzothStorage storage $) {
        assembly {
            $.slot := AzothStorageLocation
        }
    }

    function _checkAzoth() private view {
        if(msg.sender != address(this)) revert NotAzoth();
    }

    function _checkUintNotZero(uint256 _a) private pure {
        if (_a == 0) revert InvaildParam();
    }

    function _check2UintNotZero(uint256 _a, uint256 _b) private pure {
        if(_a == 0 || _b == 0) revert InvaildParam();
    }

    function _checkRWAByVault(address _vault) private pure {
        if(_vault == address(0)) revert RWANotExist();  // RWA does not exist / not supported
    }

    function _checkAddressNotZero(address _addr) private pure {
        if(_addr == address(0)) revert ZeroAddress();
    }

    function _checkLPToken(address _wRWA, address _lpToken) private view {
        if(ICurvePool(_lpToken).coins(0) != _wRWA &&  ICurvePool(_lpToken).coins(1) != _wRWA) revert InvaildLPToken();
    }

    // ================================================================================================
    //                                           GETTER                     
    // ================================================================================================

    /**
     * @notice Get the fee recipient address
     * @return address address of fee recipient
     */
    function getFeeRecipient() external view returns(address) {
        return _getAzothStorage().feeRecipient;
    }

    /**
     * @notice Get information about assets through wRWA address
     * @param  _wRWA    wRWA token address
     * @return rwa          address of RWA assert
     * @return vault        address of vault contract
     * @return stableCoin   Stablecoins that interact with underlying assets
     * @return mintPrice    mint price
     * @return redeemPrice  redeem price
     * @return mintFee      mint fee
     * @return redeemFee    redeem fee
     * @dev When wRWA does not exist, all returns are 0
     */
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
        if(vault == address(0)) return (address(0), address(0), address(0), 0, 0, 0, 0);
        rwa         = IRWAVault(vault).RWA();
        stableCoin  = IRWAVault(vault).stableCoin();
        mintPrice   = IRWAVault(vault).mintPrice();
        redeemPrice = IRWAVault(vault).redeemPrice();
        mintFee     = IRWAVault(vault).mintFee();
        redeemFee   = IRWAVault(vault).redeemFee();
    }

    /**
     * @notice Get the vault contract address
     * @param  _wRWA   wRWA address
     * @return address vault address
     * @dev If wRWA does not exist, it will return 0
     */
    function getVault(address _wRWA) external view returns(address) {
        return _getAzothStorage().vaults[_wRWA];
    }

    /**
     * @notice This function is used to check whether the redemption of a certain NFT has been officially processed. 
     *         true -> processed   false -> not processed
     * @param  _tokenId         tokenId of NFT
     */
    function isRedeemProcessed(uint256 _tokenId) external view returns(bool) {
        return INFTManager(nftManager).isRedeemProcessed(_tokenId);
    }

    /**
     * @notice This function is used to check how many stablecoins a certain NFT can redeem ( - fee )
     * @param  _tokenId         tokenId of NFT
     * @dev When the NFT has not been processed, it returns 0
     */
    function getNFTTotalValue(uint256 _tokenId) public view returns(uint256) {
        uint256 stablecoinAmount = INFTManager(nftManager).getNFTTotalValue(_tokenId);

        (address wRWA, , , ) = INFTManager(nftManager).getNFTRedeemInfo(_tokenId);
        address vault = _getAzothStorage().vaults[wRWA];
        _checkRWAByVault(vault);

        return stablecoinAmount - stablecoinAmount.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR);
    }

     /**
     * @notice Check if the user is in the blacklist
     * @param _wRWA  wRWA address
     * @param _user  user address
     * @return bool  True -> is a blacklisted user
     */
    function inWRWABlacklist(address _wRWA, address _user) external view returns(bool) {
        return IWrapRWA(_wRWA).blackList(_user);
    }

    /**
     * @notice Get the unlock timestamp of sensitive action
     * @param   _id  action Id
     * @return  uint256 unlock time of action
     * @dev Return 0 when the action does not exist
     */
    function getUnlockTimestamp(bytes32 _id) external view returns(uint256) {
        return _getAzothStorage().unlockTimestamps[_id];
    }

    /**
     * @notice Calculate the amount of stablecoins needed to mint a fixed amount of $wRWA
     * @param  _wRWA              address of $wRWA token 
     * @param  _amountWRWA        amount of $wRWA want to mint
     * @return amountStablecoin   amount of stablecoin needed
     * @dev Formula: amountStablecoin = _amountRWA * mintPrice * (1 + mintFee / FEE_DENOMINATOR)
     */
    function calcStablecoinByWRWA(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin) {
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        amountStablecoin  = _amountWRWA.mulWadUp( IRWAVault(vault).mintPrice(), IERC20Metadata(_wRWA).decimals());
        amountStablecoin += amountStablecoin.mulDivUp(IRWAVault(vault).mintFee(), FEE_DENOMINATOR);
    }

    /**
     * @notice  Calculate the amount of $wRWA that can be minted with a fixed amount of stablecoins
     * @param   _wRWA               address of $wRWA token
     * @param   _amountStablecoin   amount of stablecoins used to mint
     * @return  amountWRWA          amount of $wRWA can be minted
     * @dev Formula: amountWRWA * mintPrice * (1 + mintFee / FEE_DENOMINATOR) = amountStablecoin
     */
    function calcWRWAByStablecoin(address _wRWA, uint256 _amountStablecoin) external view returns(uint256 amountWRWA) {
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        amountWRWA = (_amountStablecoin * FEE_DENOMINATOR).divWad( 
            IRWAVault(vault).mintPrice() * (FEE_DENOMINATOR + IRWAVault(vault).mintFee()), IERC20Metadata(_wRWA).decimals()
        );
    }

    /**
     * @notice calculate the amount of stablecoins that can be redeemed through quickRedeem()
     * @param  _wRWA              address of $wRWA token
     * @param  _amountWRWA        amount of $wRWA to be redeemed
     * @return amountStablecoin   amount of stablecoin returned
     * @dev Formula: amountStablecoin = amountWRWA * mintPrice * (1 - redeemFee/FEE_DENOMINATOR)
     */
    function calcValueInQuickRedeem(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin) {
        address vault = _getAzothStorage().vaults[_wRWA];
        _checkRWAByVault(vault);
        amountStablecoin  = _amountWRWA.mulWad(IRWAVault(vault).mintPrice(), IERC20Metadata(_wRWA).decimals());
        amountStablecoin -= amountStablecoin.mulDivUp(IRWAVault(vault).redeemFee(), FEE_DENOMINATOR);  // subtract fee
    }

    // ================= Modifier ==================
    modifier onlyAzoth() {
        _checkAzoth();
        _;
    }
}