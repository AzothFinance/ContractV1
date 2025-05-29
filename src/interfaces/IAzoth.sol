//SPDX-License-Identifier: MIX
pragma solidity ^0.8.20;

interface IAzoth {
    // ==================================== EVENT ======================================
    event  LOG_NewRWA(address indexed rwa, address wRWA, address rwaVault);
    event  LOG_DepositRWA(address indexed wRWA, uint256 amount, uint256 mintPrice, uint256 timestamp);
    event  LOG_WithdrawRWA(address indexed wRWA, address to, uint256 amount);
    event  LOG_Repay(address indexed wRWA, uint256 amount, uint256 redeemPrice, uint256 rwaRepayAmount);
    event  LOG_WithdrawStablecoin(address indexed wRWA, address to, uint256 amount);

    event  LOG_NewFeeRecipient(address newFeeRecipient);
    event  LOG_NewFeePercent(address indexed wRWA, uint256 newMintFee, uint256 newRedeemFee);

    event  LOG_Mint(address indexed wRWA, address user, uint256 amountWRWA, uint256 mintPirce, uint256 timestamp);
    event  LOG_QuickRedeem(address indexed wRWA, address user, uint256 amountWRWA, uint256 amountStablecoin, uint256 timestamp);
    event  LOG_RequestRedeem(address indexed wRWA, address user, uint256 amountStablecoin, uint256 timestamp);
    event  LOG_WithdrawRedeem(address indexed wRWA, uint256 nftId, address user, uint256 amountWRWA, uint256 amountStablecoin, uint256 timestamp);

    event  LOG_ScheduleAction(bytes32 id, address target, bytes data, bytes32 salt, uint256 unlockTimestamp);
    event  LOG_ExecuteAction(bytes32 id, address target, bytes data);
    event  LOG_CancelAction(bytes32 id);

    event  LOG_LockLP(address indexed wRWA, address lpToken, uint256 amount);
    event  LOG_UnlockLP(address indexed wRWA, address lpToken, uint256 amount);

    // ====================================== ERROR =====================================
    error  ZeroAddress();
    error  RWANotExist();
    error  InvaildParam();
    error  RWAAlreadyExist(); 
    error  WithdrawTooMuch();
    error  InsufficientMintAmount();
    error  InvaildLPToken();
    error  ApplicationExpired();
    error  VaultInsufficientFunds();

    error  NotAzoth();
    error  ActionNotAllowed();
    error  ActionRepeat();
    error  ActionNotExist();
    error  ActionWaiting();
    error  ActionExecuteFail();

    // ====================================== FUNCTION ====================================
    function newRWA(
        address _rwa, 
        string memory _nameWRWA, 
        string memory _symbolWRWA,
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) external;
    function depositRWA(address _wRWA, uint256 _amount, uint256 _mintPrice) external;
    function withdrawRWA(address _wRWA, uint256 _amount) external;
    function repay(address _wRWA, uint256 _amount, uint256 _redeemPrice) external;
    function withdrawStablecoin(address _wRWA, uint256 _amount) external;

    function setFeeRecipient(address _newFeeRecipient) external;
    function setFeePercent(address _wRWA, uint256 _newMintFee, uint256 _newRedeemFee) external;
    function setWRWABlackList(address _wRWA, address _user) external;

    function pause() external;
    function unpause() external;

    function mint(address _wRWA, uint256 _amountRWA, uint256 _amountStablecoin) external;
    function requestRedeem(address _wRWA, uint256 _amount) external;
    function withdrawRedeem(uint256 _nftId) external;

    function getRWAInfo(address _wRWA) external view returns( 
        address rwa, 
        address vault,
        address stableCoin,
        uint256 mintPrice, 
        uint256 redeemPrice, 
        uint256 mintFee,
        uint256 redeemFee
    );
    function getVault(address _wRWA) external view returns(address);
    function inWRWABlacklist(address _wRWA, address _user) external view returns(bool);

    function calcStablecoinByWRWA(address _wRWA, uint256 _amountWRWA) external view returns(uint256 amountStablecoin);
    function calcWRWAByStablecoin(address _wRWA, uint256 _amountStablecoin) external view returns(uint256 amountWRWA);
}
