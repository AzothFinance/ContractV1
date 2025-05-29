// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {
    function deployWRWA(
        address _azoth,
        string memory _name,
        string memory _symbol,
        uint8 _decimal 
    ) external returns(address);
    
    function deployVault(
        address _azoth, 
        address _rwa, 
        address _wRWA,
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) external returns(address);
}