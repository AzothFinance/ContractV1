// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrapRWA is ERC20 {
    error NotAzoth();
    error InBlackList();

    modifier onlyAzoth {
        _checkAzoth();
        _;
    }
    
    address public immutable azoth;
    uint8 private immutable decimal;
    mapping(address => bool) public blackList;

    constructor(address _azoth, string memory _name, string memory _symbol, uint8 _decimal) ERC20(_name, _symbol) {
        azoth = _azoth;
        decimal = _decimal;
    }

    // ================ self define ================
    function mint(address _to, uint256 _amount) external onlyAzoth {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyAzoth {
        _burn(_from, _amount);
    }

    function setBlackList(address _user) external onlyAzoth {
        blackList[_user] = !blackList[_user];
    }

    // ================= override ====================
    function decimals() public view override returns (uint8) {
        return decimal;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        if(blackList[owner]) revert InBlackList();  // add blacklist check
        _transfer(owner, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if(blackList[from]) revert InBlackList();   // add blacklist check
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    // ============= private ============
    function _checkAzoth() private view {
        if(msg.sender != azoth) revert NotAzoth();
    }
}