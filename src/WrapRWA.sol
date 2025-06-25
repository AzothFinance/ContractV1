// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWrapRWA} from "src/interfaces/IWrapRWA.sol";
import {Errors} from "src/Errors.sol";

contract WrapRWA is ERC20, IWrapRWA {

    address public immutable azoth;
    uint8 private immutable _decimals;
    mapping(address user => bool) public isBlacklisted;

    constructor(
        address _azoth, 
        string memory _name, 
        string memory _symbol, 
        uint8 __decimals
    ) ERC20(_name, _symbol) {
        azoth = _azoth;
        _decimals = __decimals;
    }

    // ========================== Self Define ==========================
    function mint(address _to, uint256 _amount) external onlyAzoth {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyAzoth {
        _burn(_from, _amount);
    }

    function setBlackList(address _user) external onlyAzoth {
        isBlacklisted[_user] = !isBlacklisted[_user];
    }

    // =========================== Override ===========================
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        if(isBlacklisted[from] || isBlacklisted[to]) revert Errors.Blacklisted();   // blacklist check
        super._update(from, to, amount);
    }

    // =========================== Checker ============================
    function _checkAzoth() private view {
        if(msg.sender != azoth) revert Errors.NotAzoth();
    }

    modifier onlyAzoth {
        _checkAzoth();
        _;
    }
}