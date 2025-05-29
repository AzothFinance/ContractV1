// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRWAVault {
    function transferERC20(address _erc20, address _to, uint256 _amount) external;
    function setMintPrice(uint256 _mintPrice) external;
    function setRedeemPrice(uint256 _redeemPrice) external;
    function setFee(uint256 _newMintFee, uint256 _newRedeemFee) external;

    function azoth() external view returns(address);
    function RWA() external view returns(address);
    function wRWA() external view returns(address);
    function stableCoin() external view returns(address);
    function mintPrice() external view returns(uint256);
    function redeemPrice() external view returns(uint256);
    function mintFee() external view returns(uint256);
    function redeemFee() external view returns(uint256);
}