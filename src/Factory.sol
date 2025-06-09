// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WrapRWA}  from "src/WrapRWA.sol";
import {RWAVault} from "src/RWAVault.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

contract Factory is IFactory {
    function deployWRWA(
        address _azoth, 
        string memory _name, 
        string memory _symbol, 
        uint8 _decimal
    ) external returns(address) {
        return 
            address(
                new WrapRWA(
                    _azoth,                                      
                    _name,      
                    _symbol,   
                    _decimal
                )
            );
    }

    function deployVault(
        address _azoth, 
        address _rwa, 
        address _wRWA,
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) external returns(address) {
        return 
            address(
                new RWAVault(
                    _azoth,
                    _rwa,
                    _wRWA,
                    _stableCoin,
                    _mintFee,
                    _redeemFee
                )
            );
    }
}