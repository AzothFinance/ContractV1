// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// Temporary Azoth. The purpose is to allow the nftmanager variable in the contract to be stored as an immutable type later.
contract TempAzoth is UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable{
    // ========================= ERC-7201 =============================
    /// @dev keccak256(abi.encode(uint256(keccak256("AZOTH.storage.Azoth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AzothStorageLocation = 0xd7401a6cf1440e8507caa1dba74ad41933fbb7724fa29b58c7f6cc5cd0696f00;

    /// @custom:storage-location erc7201:AZOTH.storage.Azoth
    struct AzothStorage {
        address feeRecipient;
        mapping(address => address) rwaVault;
        mapping(bytes32 id => uint256) unlockTimestamps;
    }
    
    function initialize(address _owner, address _feeRecipient) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __Pausable_init();
        _getAzothStorage().feeRecipient = _feeRecipient;
    }

    function _getAzothStorage() private pure returns (AzothStorage storage $) {
        assembly {
            $.slot := AzothStorageLocation
        }
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner { }
}