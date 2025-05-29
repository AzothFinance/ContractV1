// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RWAVault {
    using SafeERC20 for IERC20;

    error NotAzoth();
    modifier onlyAzoth {
        _checkAzoth();
        _;
    }

    address public immutable azoth;      // Azoth (proxy contract)
    address public immutable RWA;        // RWA assert     
    address public immutable wRWA;       // wRWA address
    address public immutable stableCoin; // Stablecoins that interact with underlying assets
    
    uint256 public mintPrice;            // mint price
    uint256 public redeemPrice;          // redeem price
    uint256 public mintFee;              // mint fee   (e.g. 450 => 0.045%)
    uint256 public redeemFee;            // redeem fee

    constructor(
        address _azoth, 
        address _rwa, 
        address _wRWA, 
        address _stableCoin, 
        uint256 _mintFee,
        uint256 _redeemFee
    ) {
        azoth = _azoth;
        RWA = _rwa;
        wRWA = _wRWA;
        stableCoin = _stableCoin;
        mintFee = _mintFee;
        redeemFee = _redeemFee;
    }

    function transferERC20(address _erc20, address _to, uint256 _amount) external onlyAzoth {
        IERC20(_erc20).safeTransfer(_to, _amount);
    }

    function setMintPrice(uint256 _mintPrice) external onlyAzoth {
        mintPrice = _mintPrice;
    }

    function setRedeemPrice(uint256 _redeemPrice) external onlyAzoth {
        redeemPrice = _redeemPrice;
    }

    function setFee(uint256 _newMintFee, uint256 _newRedeemFee) external onlyAzoth {
        mintFee = _newMintFee;
        redeemFee = _newRedeemFee;
    }

    function _checkAzoth() private view {
        if(msg.sender != azoth) revert NotAzoth();
    }
}