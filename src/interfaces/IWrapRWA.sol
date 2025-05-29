// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IWrapRWA is IERC20Metadata {
    // setter
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function setBlackList(address _user) external;

    // getter
    function azoth() external view returns(address);
    function blackList(address _user) external view returns(bool);
}