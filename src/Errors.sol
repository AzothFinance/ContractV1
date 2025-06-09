//SPDX-License-Identifier: MIX
pragma solidity ^0.8.20;

library Errors {
    error  ZeroAddress();
    error  RWANotExist();
    error  InvaildParam();
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

    error Blacklisted();

    error NextRound();
    error NotNFTOwner();
    error InsufficientRedeemAmount();
    error NotYetProcessed();
    error RepayTooMuch();
}