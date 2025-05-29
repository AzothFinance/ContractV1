//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface INFTManager is IERC721Metadata {
    struct RepayInfo {
        uint256 price;    // repay price
        uint256 amount;   // repay amount
    }

    function addBatch(address _rwa, uint256 _amount) external;
    function mint(address _rwa, uint256 _amount, address _to) external;
    function burn(address _from, uint256 _tokenId) external returns(uint256);
    function addProcessingAmount(address _wRWA, uint256 _amount) external;
    function repay(address _rwa, uint256 _amount, uint256 _redeemPirce) external;

    function getNextTokenId() external view returns(uint256);
    function getNFTRedeemInfo(uint256 _tokenId) external view returns(address, uint256, uint256, uint256);
    function getBatchAmount(address _wRWA) external view returns(uint256[] memory);
    function getUserRequestRedeemStatus(address _wRWA) external view returns(uint256, uint256);
    function getProcessedStatus(address _wRWA) external view returns(uint256, uint256);
    function getProcessingAmount(address _wRWA) external view returns(uint256);
    function getWithdrawableStablecoinAmount(address _wRWA) external view returns(uint256);
    function getRepayInfo(address _wRWA) external view returns(RepayInfo[][] memory);
    function isRedeemProcessed(uint256 _tokenId) external view returns(bool);
    function getNFTTotalValue(uint256 _tokenId) external view returns(uint256);
    function getOwnedNFT(address _user) external view returns(uint256[] memory tokenIds);
    function getOwnedNFTOfWRWA(address _user, address _wRWA) external view returns(uint256[] memory tokenIdsWRWA);
}