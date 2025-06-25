//SPDX-License-Identifier: MIX
pragma solidity ^0.8.20;

interface IAzoth {

    //============================================= EVENT ================================================
    event  LOG_NewRWA(address indexed rwa, address wRWA, address rwaVault);
    event  LOG_DepositRWA(address indexed wRWA, uint256 amount, uint256 mintPrice, uint256 timestamp);
    event  LOG_WithdrawRWA(address indexed wRWA, address to, uint256 amount);
    event  LOG_Repay(address indexed wRWA, uint256 amountRWA, uint256 redeemPrice, uint256 amountStablecoin);
    event  LOG_WithdrawStablecoin(address indexed wRWA, address to, uint256 amount);

    event  LOG_LockLP(address indexed wRWA, address lpToken, uint256 amount);
    event  LOG_UnlockLP(address indexed wRWA, address lpToken, uint256 amount);

    event  LOG_ScheduleAction(bytes32 id, address target, bytes data, bytes32 salt, uint256 unlockTimestamp);
    event  LOG_ExecuteAction(bytes32 id, address target, bytes data);
    event  LOG_CancelAction(bytes32 id);

    event  LOG_BlacklistUpdate(address indexed wRWA, address user, bool isBlacklisted);

    event  LOG_NewFeeRecipient(address newFeeRecipient);
    event  LOG_NewFeePercent(address indexed wRWA, uint256 newMintFee, uint256 newRedeemFee);

    event  LOG_Mint(address indexed wRWA, address user, uint256 amountWRWA, uint256 mintPirce, uint256 timestamp);
    event  LOG_RequestRedeem(address indexed wRWA, address user, uint256 amountStablecoin, uint256 timestamp);
    event  LOG_WithdrawRedeem(address indexed wRWA, uint256 nftId, address user, uint256 amountWRWA, uint256 amountStablecoin, uint256 timestamp);


    //====================================================================================================
    //                                            Official Affairs
    //====================================================================================================

    /// @notice Add/Support a new RWA asset. Only owner calls.
    /// @notice In function: 1) deploy the wRWA Token; 2) deploy the vault contract;
    /// @param _rwa          The address of RWA asset 
    /// @param _nameWRWA     The name of the wRWA token    (used when deploying wRWA)
    /// @param _symbolWRWA   The symbol of the wRWA token  (used when deploying wRWA)
    /// @param _stableCoin   The address of stablecoin that interact with RWA/wRWA
    /// @param _mintFee      The fee when user mint
    /// @param _redeemFee    The fee when user redeem
    /// @dev Note: There is no check if the RWA asset is added repeatedly, manual attention is required
    function newRWA(
        address _rwa, 
        string memory _nameWRWA, 
        string memory _symbolWRWA,
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) external;

    /// @notice Deposit $RWA and set the mint price. Only owner calls.
    /// @notice Used when the official subscribes to RWA from the fund company and deposits RWA for users to mint.
    /// @param  _wRWA       The address of wRWA corresponding to the RWA asset
    /// @param  _amount     The amount of $RWA deposited 
    /// @param  _mintPrice  The mint price  (e.g. 1RWA is worth 1USDT, then `_mintPrice` = 1000000)
    function depositRWA(address _wRWA, uint256 _amount, uint256 _mintPrice) external;

    /// @notice Withdraw $RWA for repayment to fund company. Call by TimeLock.
    /// @param  _wRWA      The address of wRWA corresponding to the RWA asset
    /// @param  _amount    The amount of withdrawal
    function withdrawRWA(address _wRWA, uint256 _amount) external;

    /// @notice Deposit stablecoins and set the redeem price. Only owner calls.
    /// @notice Used When repaying $RWA to the fund company, deposit stablecoins for users to withdraw previously requested redemptions.
    /// @notice Amount of stablecoins deposited = Amount of RWA repaid * redeem price.
    /// @param  _wRWA         The address of wRWA corresponding to the RWA asset
    /// @param  _amount       The amount of RWA to be repaid
    /// @param  _redeemPrice  Redeem price
    function repay(address _wRWA, uint256 _amount, uint256 _redeemPrice) external;

    /// @notice Withdraw stablecoins for repurchase $RWA. Call by TimeLock.
    /// @param  _wRWA       The address of wRWA corresponding to the RWA asset
    /// @param  _amount     The amount of stablecoin to withdraw
    function withdrawStablecoin(address _wRWA, uint256 _amount) external;

    /// @notice Deposit LP token for lock liquidity. Only owner calls.
    /// @notice Used after the owner adds liquidity to the Curve Pool and obtains LP Token. 
    /// @param _wRWA     The address of wRWA 
    /// @param _lpToken  The address of LP Token
    /// @param _amount   The amount of LP Token to deposit
    /// @dev Check whether the LP Token is really the liquidity associated with the wRWA token.
    function lockLP(address _wRWA, address _lpToken, uint256 _amount) external;

    /// @notice Withdraw LP Token for unlock liquidity. Call by TimeLock.
    /// @param _wRWA     The address of wRWA
    /// @param _lpToken  The address of LP Token
    /// @param _amount   The amount of LP Token to withdraw
    /// @dev Check whether the LP Token is really the liquidity associated with the wRWA token.
    function unlockLP(address _wRWA, address _lpToken, uint256 _amount) external;


    //====================================================================================================
    //                                        Timelock Controller
    //====================================================================================================

    /// @notice Schedule an action to be performed. Only owner calls.
    /// @notice Delay by 1 day. After unlock, owner can call executeAction() to execute it.
    /// @param _target  The address of the contract to call
    /// @param _data    The calldata, including function selector and args
    /// @param _salt    Salt value. Make it different so that the same action can wait together
    function scheduleAction(address _target, bytes calldata _data, bytes32 _salt) external;

    /// @notice Execute an unlocked action. Only owner calls.
    /// @param _target  The address of the contract to call
    /// @param _data    The calldata, including function selector and args
    /// @param _salt    Salt value. Make it different so that the same action can wait together
    function executeAction(address _target, bytes calldata _data, bytes32 _salt) external;

    /// @notice Cancel an scheduled action. Only owner calls.
    /// @param  _id   action id
    function cancelAction(bytes32 _id) external;


    //====================================================================================================
    //                                            Setters
    //====================================================================================================

    /// @notice Set the recipient of fee. Only owner calls.
    /// @param  _newFeeRecipient The address of new Recipient
    function setFeeRecipient(address _newFeeRecipient) external;

    /// @notice Set mintFee and redeemFee for a wRWA. Only owner calls.
    /// @param  _wRWA            The address of wRWA token
    /// @param  _newMintFee      New mintFee
    /// @param  _newRedeemFee    New redeemFee
    function setFeePercent(address _wRWA, uint256 _newMintFee, uint256 _newRedeemFee) external;

    /// @notice Set the blacklist of wRWA tokens. Only owner calls. (true -> false or false -> true)
    /// @notice Blacklisted users cannot transfer tokens. 
    /// @param  _wRWA   The address of wRWA token
    /// @param  _user   User for setting
    function setWRWABlackList(address _wRWA, address _user) external;

    /// @notice Pause the contract. Only owner calls.
    function pause() external;
    
    /// @notice Unpause the contract. Only owner calls.
    function unpause() external;


    //====================================================================================================
    //                                            User Action
    //====================================================================================================

    /// @notice Users use stablecoin to mint $wRWA.
    /// @notice `_amountRWA` and `_amountStablecoin`, have and only one is 0.
    /// @param  _wRWA               The address of $wRWA token
    /// @param  _amountWRWA         The amount of $wRWA want to mint
    /// @param  _amountStablecoin   The amount of stablecoins used to mint
    /// @dev Formula: amountStablecoin = _amountRWA * mintPrice * (1 + feePercent / FEE_DENOMINATOR)
    function mint(address _wRWA, uint256 _amountWRWA, uint256 _amountStablecoin) external;

    /// @notice User request to redeem stablecoins, and mint NFT to user as Redemption Certificate.
    /// @param  _wRWA    The address of $wRWA
    /// @param  _amount  The amount of $wRWA to be redeemed
    function requestRedeem(address _wRWA, uint256 _amount) external;

    /// @notice User use NFT to withdraw stablecoin
    /// @param  _nftId   The tokenId of NFT
    function withdrawRedeem(uint256 _nftId) external;

    //====================================================================================================
    //                                            View
    //====================================================================================================

    /// @notice Get the fee recipient address
    /// @return address address of fee recipient
    function getFeeRecipient() external view returns(address);

    /// @notice Get asset info through wRWA address.
    /// @param  _wRWA    The address of wRWA
    /// @return rwa          The address of RWA assert
    /// @return vault        The address of vault contract
    /// @return stableCoin   The address of stablecoin that interact with RWA/wRWA
    /// @return mintPrice    Mint price
    /// @return redeemPrice  Redeem price
    /// @return mintFee      Mint fee
    /// @return redeemFee    Redeem fee
    /// @dev When asset does not exist, will revert.
    function getRWAInfo(address _wRWA) external view returns( 
        address rwa,
        address vault, 
        address stableCoin,
        uint256 mintPrice, 
        uint256 redeemPrice, 
        uint256 mintFee,
        uint256 redeemFee
    );

    /// @notice Get the vault contract address
    /// @param  _wRWA   The address of wRWA
    /// @return address The address of vault contract
    /// @dev If wRWA does not exist, it will return 0
    function getVault(address _wRWA) external view returns(address);

    /// @notice Check whether the redemption of a certain NFT has been officially processed. 
    /// @notice true -> processed   false -> not processed
    /// @param  _tokenId  The tokenId of NFT
    function isRedeemProcessed(uint256 _tokenId) external view returns(bool);

    /// @notice Check how many stablecoins a certain NFT can redeem (subtract fees)
    /// @param  _tokenId   The tokenId of NFT
    /// @dev When the NFT has not been processed, it returns 0
    function getNFTTotalValue(uint256 _tokenId) external view returns(uint256);

    /// @notice Check if the user is in the blacklist
    /// @param _wRWA  The address of wRWA
    /// @param _user  The address of user
    /// @return bool  true -> blacklisted
    function inWRWABlacklist(address _wRWA, address _user) external view returns(bool);

    /// @notice Get the unlock timestamp of action
    /// @param   _id  The action Id
    /// @return  uint256 The unlock timestamp of action
    /// @dev Return 0 when the action does not exist
    function getUnlockTimestamp(bytes32 _id) external view returns(uint256);

    /// @notice Calculate the amount of stablecoins needed to mint a fixed amount of $wRWA
    /// @param  _wRWA              The address of $wRWA token 
    /// @param  _amountWRWA        The amount of $wRWA want to mint
    /// @return amountStablecoin   The amount of stablecoin needed
    /// @dev Formula: amountStablecoin = _amountRWA * mintPrice * (1 + mintFee / FEE_DENOMINATOR)
    function calcStablecoinByWRWA(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin);

    /// @notice  Calculate the amount of $wRWA that can be minted with a fixed amount of stablecoins
    /// @param   _wRWA               The address of $wRWA token
    /// @param   _amountStablecoin   The amount of stablecoins used to mint
    /// @return  amountWRWA          The amount of $wRWA can be minted
    /// @dev Formula: amountWRWA * mintPrice * (1 + mintFee / FEE_DENOMINATOR) = amountStablecoin
    function calcWRWAByStablecoin(address _wRWA, uint256 _amountStablecoin) external view returns(uint256 amountWRWA);

    /// @notice calculate the amount of stablecoins that can be redeemed through quickRedeem()
    /// @param  _wRWA              The address of $wRWA token
    /// @param  _amountWRWA        The amount of $wRWA to be redeemed
    /// @return amountStablecoin   The amount of stablecoin returned
    /// @dev Formula: amountStablecoin = amountWRWA * mintPrice * (1 - redeemFee/FEE_DENOMINATOR)
    function calcValueInQuickRedeem(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin);
}