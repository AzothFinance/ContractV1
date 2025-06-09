// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWrapRWA {
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function setBlackList(address _user) external;

    function azoth() external view returns(address);
    function isBlacklisted(address _user) external view returns(bool);
}