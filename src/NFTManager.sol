// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {INFTManager} from "src/interfaces/INFTManager.sol";
import {Errors} from "src/Errors.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {FixedPointMathLib} from "src/library/FixedPointMathLib.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract NFTManager is ERC721EnumerableUpgradeable, UUPSUpgradeable, INFTManager {
    using Strings for uint256;
    using FixedPointMathLib for uint256;

    //====================================================================================================
    //                                            Variables
    //====================================================================================================

    /// @notice The address of Azoth Contract
    address public immutable azoth;

    // redeem info of NFT
    struct NFTRedeemInfo {
        address wRWA;             // The address of wRWA to redeem
        uint256 amount;           // The amount of wRWA to redeem
        uint256 batchIdx;         // Batch index
        uint256 amountIdx;        // Amount index within a certain batch
    }

    // In INFTManager.sol: 
    // struct RepayInfo {
    //     uint256 price;    // The price of repayment
    //     uint256 amount;   // The amount of repayment
    // }

    // redeem and repay status of wRWA assets
    struct WRWARedeemInfo {
        uint256[] batchAmount;                 // Batch amount (maintained when officially deposited into RWA)
        uint256 redeemBatchIdx;                // User request redeem status: BatchIdx
        uint256 redeemAmountIdx;               // User request redeem status: AmountIdx
        uint256 processedBatchIdx;             // Official repay status: BatchIdx
        uint256 processedAmountIdx;            // Official repay status: AmountIdx
        RepayInfo[][] repayInfos;              // Repay history data
        uint256 processingAmount;              // amount of official being processed
        uint256 withdrawableStablecoinAmount;  // amount of stablecoins available for users to withdrawRedeem
    }


    //====================================================================================================
    //                                            Upgradability
    //====================================================================================================

    // keccak256(abi.encode(uint256(keccak256("AZOTH.storage.NFTManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NFTManagerStorageLocation = 
        0x980c83754224d51d8374ad9970317aaf24ad04850ecf2b771ca42610c8b64700;
    
    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _getNFTManagerStorage() private pure returns (NFTManagerStorage storage $) {
        assembly {
            $.slot := NFTManagerStorageLocation
        }
    }

    /// @custom:storage-location erc7201:AZOTH.storage.NFTManager
    struct NFTManagerStorage {
        /// @notice The next tokenId of NFT to mint
        uint256 nextTokenId;
        /// @notice The redeem info of NFT
        mapping(uint256 tokenId => NFTRedeemInfo) nftRedeemInfos;
        /// @notice The redeem info of asset
        mapping(address wRWA => WRWARedeemInfo) wrwaRedeemInfos;
    }

    /// @notice Permission verification for contract upgrade: Call by TimeLock in Azoth.
    function _authorizeUpgrade(address _newImplementation) internal override onlyAzoth{ }

    
    //====================================================================================================
    //                                            INIT
    //====================================================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _azoth) {
        azoth = _azoth;
    }

    function initialize() public initializer {
        __ERC721_init("AzothRedeemNFT", "Azoth-RD-NFT");
        __UUPSUpgradeable_init();                      
    }

    //====================================================================================================
    //                                            Azoth Affairs
    //====================================================================================================

    /// @notice Add batch info(amount). Call by `depositRWA` function in Azoth contract.
    /// @param  _wRWA      The address of wRWA
    /// @param  _amount    The amount of batch
    function addBatch(address _wRWA, uint256 _amount) external onlyAzoth {
        WRWARedeemInfo storage $ = _getNFTManagerStorage().wrwaRedeemInfos[_wRWA];
        $.batchAmount.push(_amount);
        $.repayInfos.push();
    }

    
    /// @notice Increase the amount of redemption being processed. Call by `withdrawRWA` function in Azoth contract.
    /// @param _wRWA   The address of wRWA
    /// @param _amount The amount increased
    function addProcessingAmount(address _wRWA, uint256 _amount) external onlyAzoth {
        _getNFTManagerStorage().wrwaRedeemInfos[_wRWA].processingAmount += _amount;
    }

    /// @notice Mint NFT tokens when request for redemption. Call by `mint` function in Azoth contract.
    /// @param  _wRWA     The address of wRWA
    /// @param  _amount   The amount of wRWA request for redemption
    /// @param  _to       NFT Recipient
    function mint(address _wRWA, uint256 _amount, address _to) external onlyAzoth {
        NFTManagerStorage storage $ = _getNFTManagerStorage();

        // get redemption data for wRWA assets
        uint256[] storage batchAmount = $.wrwaRedeemInfos[_wRWA].batchAmount;
        uint256 batchIdx = $.wrwaRedeemInfos[_wRWA].redeemBatchIdx;
        uint256 amountIdx = $.wrwaRedeemInfos[_wRWA].redeemAmountIdx;
        
        uint256 amount = _amount;
        while(amount > batchAmount[batchIdx] - amountIdx){
            amount -= batchAmount[batchIdx] - amountIdx;
            batchIdx += 1;
            if( batchIdx >= batchAmount.length) revert Errors.InsufficientRedeemAmount();
            amountIdx = 0;
        }
        amountIdx = amountIdx + amount;

        // mint NFT to user
        uint256 nextTokenId = $.nextTokenId++;
        _safeMint(_to, nextTokenId);

        // Record the redeem data of a single NFT
        $.nftRedeemInfos[nextTokenId] = NFTRedeemInfo({
            wRWA:      _wRWA,
            amount:    _amount,
            batchIdx:  batchIdx,
            amountIdx: amountIdx
        });

        // Update RWA global redeem data
        $.wrwaRedeemInfos[_wRWA].redeemBatchIdx = batchIdx;
        $.wrwaRedeemInfos[_wRWA].redeemAmountIdx = amountIdx;

        emit LOG_MintRedeemNFT(_wRWA, _to, nextTokenId);
    }


    /// @notice Burn NFT when user request redeem. Call by `requestRedeem` function in Azoth Contract.
    /// @param  _from         The address of NFT owner
    /// @param  _tokenId      The tokenId of NFT
    /// @return uint256  The amount of stablecoin that can be withdrawn
    function burn(address _from, uint256 _tokenId) external onlyAzoth returns(uint256) {
        // Check ownership of NFT
        if(_ownerOf(_tokenId) != _from) revert Errors.NotNFTOwner();

        _burn(_tokenId);   // burn NFT

        uint256 amountWithdraw = _calcNFTTotalValue(_tokenId); 

        // upgrade withdrawableStablecoinAmount
        address wRWA = _getNFTManagerStorage().nftRedeemInfos[_tokenId].wRWA;
        _getNFTManagerStorage().wrwaRedeemInfos[wRWA].withdrawableStablecoinAmount -= amountWithdraw;

        return amountWithdraw;
    }


    /// @notice Update processed status and record repaymemt data. Call by `repay` function in Azoth contract.
    /// @param  _wRWA        The address of wRWA
    /// @param  _amount      The amount of wRWA processed
    /// @param  _repayPrice  The price of repayment
    /// @dev In the loop, there was no check for whether batchAmount exceeded the limit, as the number of replays was less than or equal to
    ///      the number of user redemption requests, and it was ensured that the redemption requests did not exceed the limit
    function repay(address _wRWA, uint256 _amount, uint256 _repayPrice) external onlyAzoth {
        WRWARedeemInfo storage wrwaRedeemInfo = _getNFTManagerStorage().wrwaRedeemInfos[_wRWA];

        // Check that the amount to be repaid cannot be greater than the amount being processed, and update
        if(_amount > wrwaRedeemInfo.processingAmount) revert Errors.RepayTooMuch();
        wrwaRedeemInfo.processingAmount -= _amount;

        uint256[] storage batchAmount = wrwaRedeemInfo.batchAmount;
        uint256 processedBatchIdx = wrwaRedeemInfo.processedBatchIdx;
        uint256 processedAmountIdx = wrwaRedeemInfo.processedAmountIdx;
        uint256 amount = _amount;

        uint256 batchRemaining = batchAmount[processedBatchIdx] - processedAmountIdx;
        while(amount > batchRemaining) {
            if(batchRemaining != 0) { // When repay() was called last time, if amount is equal to batchRemaining, then this repay() will result in batchRemaining=0
                amount -= batchRemaining;
                wrwaRedeemInfo.repayInfos[processedBatchIdx].push(
                    RepayInfo(_repayPrice, batchRemaining)
                );
            }
            processedBatchIdx += 1;
            processedAmountIdx = 0;
            batchRemaining = batchAmount[processedBatchIdx];
        }
        wrwaRedeemInfo.processedBatchIdx = processedBatchIdx;
        wrwaRedeemInfo.processedAmountIdx = processedAmountIdx + amount;
        wrwaRedeemInfo.repayInfos[processedBatchIdx].push(
            RepayInfo(_repayPrice, amount)
        );

        // upgrade withdrawableStablecoinAmount
        wrwaRedeemInfo.withdrawableStablecoinAmount += _amount.mulWadUp(_repayPrice, IERC20Metadata(_wRWA).decimals());
    }


    //====================================================================================================
    //                                            View
    //====================================================================================================

    function getNextTokenId() external view returns(uint256) {
        return _getNFTManagerStorage().nextTokenId;
    }

    function getNFTRedeemInfo(uint256 _tokenId) external view returns(address, uint256, uint256, uint256) {
        NFTRedeemInfo memory nftRedeemInfo = _getNFTManagerStorage().nftRedeemInfos[_tokenId];
        return (
            nftRedeemInfo.wRWA, 
            nftRedeemInfo.amount, 
            nftRedeemInfo.batchIdx,
            nftRedeemInfo.amountIdx
        );
    }

    function getBatchAmount(address _wRWA) external view returns(uint256[] memory) {
        return _getNFTManagerStorage().wrwaRedeemInfos[_wRWA].batchAmount;
    }

    function getUserRequestRedeemStatus(address _wRWA) external view returns(uint256, uint256) {
        WRWARedeemInfo storage wrwaRedeemInfo = _getNFTManagerStorage().wrwaRedeemInfos[_wRWA];
        return (wrwaRedeemInfo.redeemBatchIdx, wrwaRedeemInfo.redeemAmountIdx);
    }

    function getProcessedStatus(address _wRWA) external view returns(uint256, uint256) {
        WRWARedeemInfo storage wrwaRedeemInfo = _getNFTManagerStorage().wrwaRedeemInfos[_wRWA];
        return (wrwaRedeemInfo.processedBatchIdx, wrwaRedeemInfo.processedAmountIdx);
    }

    function getProcessingAmount(address _wRWA) external view returns(uint256) {
        return _getNFTManagerStorage().wrwaRedeemInfos[_wRWA].processingAmount;
    }

    function getWithdrawableStablecoinAmount(address _wRWA) external view returns(uint256) {
        return _getNFTManagerStorage().wrwaRedeemInfos[_wRWA].withdrawableStablecoinAmount;
    }

    function getRepayInfo(address _wRWA) external view returns(RepayInfo[][] memory) {
        return _getNFTManagerStorage().wrwaRedeemInfos[_wRWA].repayInfos;
    }


    /// @inheritdoc INFTManager
    function isRedeemProcessed(uint256 _tokenId) external view returns(bool) {
        NFTRedeemInfo storage nftRedeemInfo = _getNFTManagerStorage().nftRedeemInfos[_tokenId];
        address wRWA = nftRedeemInfo.wRWA;
        uint256 nftBatchIdx = nftRedeemInfo.batchIdx;

        WRWARedeemInfo storage wrwaRedeemInfo = _getNFTManagerStorage().wrwaRedeemInfos[wRWA];
        uint256 processedBatchIdx = wrwaRedeemInfo.processedBatchIdx;

        return nftBatchIdx < processedBatchIdx || 
            (nftBatchIdx == processedBatchIdx && nftRedeemInfo.amountIdx <= wrwaRedeemInfo.processedAmountIdx);
    }

    /// @inheritdoc INFTManager
    function getNFTTotalValue(uint256 _tokenId) external view returns(uint256) {
        return _calcNFTTotalValue(_tokenId);
    }

    /// @inheritdoc INFTManager
    function getOwnedNFT(address _user) external view returns(uint256[] memory tokenIds) {
        uint256 amount = balanceOf(_user);
        tokenIds = new uint256[](amount);

        for(uint256 i = 0; i < amount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_user, i);
        }
    }

    /// @inheritdoc INFTManager
    function getOwnedNFTOfWRWA(address _user, address _wRWA) external view returns(uint256[] memory tokenIdsWRWA) {
        NFTManagerStorage storage nftManagerStorage = _getNFTManagerStorage();
        uint256 amount = balanceOf(_user);
        uint256[] memory tokenIds = new uint256[](amount);

        uint256 j = 0;
        for(uint256 i = 0; i < amount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_user, i);
            if(nftManagerStorage.nftRedeemInfos[tokenId].wRWA == _wRWA) {
                tokenIds[j] = tokenId;
                j++;
            }
        }

        tokenIdsWRWA = new uint256[](j);
        for(uint256 i = 0; i < j; i++) {
            tokenIdsWRWA[i] = tokenIds[i];
        }
    }

    //====================================================================================================
    //                                            Other
    //====================================================================================================

    function _checkAzoth() private view {
        if(msg.sender != azoth) revert Errors.NotAzoth();
    }

    modifier onlyAzoth() {
        _checkAzoth();
        _; 
    }

    function _calcNFTTotalValue(uint256 _tokenId) private view returns(uint256) {
        // get redeem data for this NFT
        NFTRedeemInfo storage nftRedeemInfo = _getNFTManagerStorage().nftRedeemInfos[_tokenId];
        address wRWA = nftRedeemInfo.wRWA;
        uint256 nftRedeemAmount = nftRedeemInfo.amount;
        uint256 nftBatchIdx = nftRedeemInfo.batchIdx;
        uint256 nftAmountIdx = nftRedeemInfo.amountIdx;

        // get processed BatchIdx and processed AmountIdx
        WRWARedeemInfo storage wrwaRedeemInfo = _getNFTManagerStorage().wrwaRedeemInfos[wRWA];
        uint256 processedBatchIdx = wrwaRedeemInfo.processedBatchIdx;
        uint256 processedAmountIdx = wrwaRedeemInfo.processedAmountIdx;

        // Check if redeem can be withdrawn (return 0, indicating that the request of redeem for the NFT has not been processed)
        if(nftBatchIdx > processedBatchIdx || (nftBatchIdx == processedBatchIdx && nftAmountIdx > processedAmountIdx)) revert Errors.NotYetProcessed();

        // Location of price data at the end of redeem range
        uint256[] storage batchAmount = wrwaRedeemInfo.batchAmount;
        RepayInfo[][] storage repayInfo = wrwaRedeemInfo.repayInfos;
        uint256 priceIdx = 0;
        uint256 tempAmountIdx = 0;
        while(tempAmountIdx + repayInfo[nftBatchIdx][priceIdx].amount < nftAmountIdx) {
            tempAmountIdx += repayInfo[nftBatchIdx][priceIdx].amount;
            priceIdx += 1;
        }

        // Calculate the amount of stablecoin that can be withdrewn
        uint8 decimals = IERC20Metadata(wRWA).decimals();
        uint256 batchIdx = nftBatchIdx;
        uint256 totalValue;
        while(nftRedeemAmount > nftAmountIdx - tempAmountIdx) {
            totalValue += (nftAmountIdx - tempAmountIdx).mulWad(repayInfo[batchIdx][priceIdx].price, decimals);
            nftRedeemAmount -= nftAmountIdx - tempAmountIdx;
            // Adjust nftAmountIdx and tempAmountIdx
            if(priceIdx != 0) {
                priceIdx -= 1;
                nftAmountIdx = tempAmountIdx;
                tempAmountIdx -= repayInfo[batchIdx][priceIdx].amount;
            } else {
                batchIdx -= 1;
                priceIdx = repayInfo[batchIdx].length - 1;
                tempAmountIdx = batchAmount[batchIdx] - repayInfo[batchIdx][priceIdx].amount;
                nftAmountIdx = batchAmount[batchIdx];
            }
        }
        totalValue += nftRedeemAmount.mulWad(repayInfo[batchIdx][priceIdx].price, decimals);
        return totalValue;
    }


    //====================================================================================================
    //                                            NFT Image
    //====================================================================================================

    /// @notice Get the image data of the NFT
    /// @param tokenId  The tokenId of NFT
    function tokenURI(uint256 tokenId) public view override returns(string memory) {
        _requireOwned(tokenId);

        NFTRedeemInfo memory redeemInfo = _getNFTManagerStorage().nftRedeemInfos[tokenId]; 

        return 
            _render(
                tokenId,
                IERC20Metadata(redeemInfo.wRWA).symbol(),
                redeemInfo.amount / (10 ** IERC20Metadata(redeemInfo.wRWA).decimals()),
                redeemInfo.batchIdx,
                redeemInfo.amountIdx
            );
    }

    function _render(uint256 _tokenId, string memory _symbol, uint256 _amount, uint256 _epoch, uint256 _location) internal pure returns(string memory) {
        string memory image = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' viewBox='0 0 655.7 657.01'>",
            "<defs><style>.cls-1 {fill: #b28a4f;}",
            ".cls-1 {fill: #b28a4f;}",
            ".cls-1, .cls-2, .cls-3 {font-family: OPPOSans-M, OPPOSans;}",
            ".cls-4, .cls-5, .cls-3 {fill: #f2bf54;}",
            ".cls-6 {isolation: isolate;}",
            ".cls-7 {fill: #1a1a1a;}",
            ".cls-7, .cls-8, .cls-9 {stroke-width: 0px;}",
            ".cls-8 {fill: none;}",
            ".cls-9 {fill: #333;}",
            ".cls-2 {fill: #939393;}",
            ".cls-10 {filter: url(#outer-glow-1); mix-blend-mode: lighten; stroke: #e8c380; stroke-miterlimit: 10;}",
            ".cls-11 {clip-path: url(#clippath);}",
            ".cls-5 {font-family: OPPOSans-H, OPPOSans; font-size: 110px;}",
            ".cls-3 {font-size: 80px;}",
            ".cls-12 {letter-spacing: -.02em;}</style></defs>",
            "<clipPath id='clippath'><rect class='cls-8' x='13.8' y='14.46' width='628.39' height='628.39' rx='12' ry='12'/></clipPath>",
            "<filter id='outer-glow-1' filterUnits='userSpaceOnUse'>",
            "<feOffset dx='0' dy='0'/>",
            "<feGaussianBlur result='blur' stdDeviation='6'/>",
            "<feFlood flood-color='#ffe6c5' flood-opacity='.47'/>",
            "<feComposite in2='blur' operator='in'/>",
            "<feComposite in='SourceGraphic'/></filter>",
            "<g class='cls-6'><g id='_layer_1' data-name='layer 1'><rect class='cls-7' width='656' height='657.31'/>",
            "<g class='cls-11'><path class='cls-9' d='m596.96,322.6c-69.88-7.57-123.59,20.45-161.25,79.34-13.85,21.67-32.04,37.6-56.7,45.1-40.95,12.45-77.39,3.42-106.26-27.83-29.54-31.98-35.7-70.06-18.92-110.22,15.99-38.33,46.75-59.08,87.76-60.54,47.42-1.71,89.35-15.14,122.31-49.74,45.9-48.21,60.48-105.58,37.96-168.45-22.95-64.08-70-102.72-138.67-109.31-69.64-6.71-123.53,22.4-158.32,82.33C129.02,133.77,54.87,265.23-20.2,396.14c-15.87,27.59-25.82,56.58-25.57,88.68-.12,72.99,49.19,138.54,118.83,157.95,71.96,19.96,146.42-9.4,185.6-73.3,31.49-51.21,91.91-66.71,142.51-36.44,15.32,9.22,26.3,22.46,35.95,37.47,33.26,51.45,80.68,78.67,142.14,78.49,84.71-.31,157.28-69.7,161.31-152.7,4.27-88.56-57.74-164.42-143.61-173.7Zm-20.75,246.75c-44.07,0-79.71-35.7-79.71-79.77s35.64-79.71,79.71-79.71,79.71,35.7,79.71,79.71-35.7,79.77-79.71,79.77Z'/></g>",
            "<rect class='cls-10' x='14.46' y='14.46' width='628.39' height='628.39' rx='12' ry='12'/>",
            "<text class='cls-3' transform='translate(600 344.82)' text-anchor='end'><tspan x='0' y='0'>", _amount.toString(), "</tspan></text>",
            "<text class='cls-1' transform='translate(32.81 591.37)'><tspan x='0' y='0'>EPOCH:</tspan></text>",
            "<text class='cls-1' transform='translate(32.81 563.89)'><tspan x='0' y='0'>ID:</tspan></text>",
            "<text class='cls-2' transform='translate(57.85 563.89)'><tspan x='0' y='0'>", _tokenId.toString(), "</tspan></text>",
            "<text class='cls-2' transform='translate(97.88 591.37)'><tspan x='0' y='0'>", _epoch.toString(), "</tspan></text>",
            "<text class='cls-2' transform='translate(123.5 619.66)'><tspan x='0' y='0'>", _location.toString(), "</tspan></text>",
            "<text class='cls-1' transform='translate(32.81 619.66)'><tspan x='0' y='0'>LOCATION:</tspan></text>",
            "<text class='cls-5' transform='translate(600 228.3)' text-anchor='end'><tspan x='0' y='0'>", _symbol, "</tspan></text>",
            "<path class='cls-4' d='m53.24,39.21c-3.08-.33-5.45.9-7.11,3.5-.61.96-1.41,1.66-2.5,1.99-1.81.55-3.41.15-4.69-1.23-1.3-1.41-1.57-3.09-.83-4.86.71-1.69,2.06-2.61,3.87-2.67,2.09-.08,3.94-.67,5.39-2.19,2.02-2.13,2.67-4.66,1.67-7.43-1.01-2.83-3.09-4.53-6.12-4.82-3.07-.3-5.45.99-6.98,3.63-3.35,5.76-6.62,11.55-9.93,17.33-.7,1.22-1.14,2.5-1.13,3.91,0,3.22,2.17,6.11,5.24,6.97,3.17.88,6.46-.41,8.19-3.23,1.39-2.26,4.05-2.94,6.29-1.61.68.41,1.16.99,1.59,1.65,1.47,2.27,3.56,3.47,6.27,3.46,3.74-.01,6.94-3.07,7.11-6.74.19-3.91-2.55-7.25-6.33-7.66Zm-.92,10.88c-1.94,0-3.52-1.57-3.52-3.52s1.57-3.52,3.52-3.52,3.52,1.57,3.52,3.52-1.57,3.52-3.52,3.52Z'/>"
            "</g></g></svg>"
        );

        string memory description = string.concat(
            "ID:", _tokenId.toString(),
            " token:", _symbol,
            " amount:", _amount.toString(),
            " epoch:", _epoch.toString(),
            " location:", _location.toString()
        );

        string memory json = string.concat(
            '{"name":"Azoth RedeemNFT",',
            '"description":"',
            description,
            '",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '"}'
        );

        return 
            string.concat(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            );
    }
}