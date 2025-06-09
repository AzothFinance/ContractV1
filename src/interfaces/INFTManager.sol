//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface INFTManager {

    /// @notice info of single repaymemt
    struct RepayInfo {
        uint256 price;    // The price of repayment
        uint256 amount;   // The amount of repayment
    }
    
    event LOG_MintRedeemNFT(address indexed wrwa, address to, uint256 tokenId);

    //====================================================================================================
    //                                            Azoth Affairs
    //====================================================================================================

    /// @notice Add batch info(amount). Call by `depositRWA` function in Azoth contract.
    /// @param  _wRWA      The address of wRWA
    /// @param  _amount    The amount of batch
    function addBatch(address _wRWA, uint256 _amount) external;

    /// @notice Increase the amount of redemption being processed. Call by `withdrawRWA` function in Azoth contract.
    /// @param _wRWA   The address of wRWA
    /// @param _amount The amount increased
    function addProcessingAmount(address _wRWA, uint256 _amount) external;

    /// @notice Mint NFT tokens when request for redemption. Call by `mint` function in Azoth contract.
    /// @param  _wRWA     The address of wRWA
    /// @param  _amount   The amount of wRWA request for redemption
    /// @param  _to       NFT Recipient
    function mint(address _wRWA, uint256 _amount, address _to) external;

    /// @notice Burn NFT when user request redeem. Call by `requestRedeem` function in Azoth Contract.
    /// @param  _from         The address of NFT owner
    /// @param  _tokenId      The tokenId of NFT
    /// @return uint256  The amount of stablecoin that can be withdrawn
    function burn(address _from, uint256 _tokenId) external returns(uint256);

    /// @notice Update processed status and record repaymemt data. Call by `repay` function in Azoth contract.
    /// @param  _wRWA        The address of wRWA
    /// @param  _amount      The amount of wRWA processed
    /// @param  _repayPrice  The price of repayment
    /// @dev In the loop, there was no check for whether batchAmount exceeded the limit, as the number of replays was less than or equal to
    ///      the number of user redemption requests, and it was ensured that the redemption requests did not exceed the limit
    function repay(address _wRWA, uint256 _amount, uint256 _repayPrice) external;


    //====================================================================================================
    //                                            View
    //====================================================================================================

    function getNextTokenId() external view returns(uint256);
    function getNFTRedeemInfo(uint256 _tokenId) external view returns(address, uint256, uint256, uint256);
    function getBatchAmount(address _wRWA) external view returns(uint256[] memory);
    function getUserRequestRedeemStatus(address _wRWA) external view returns(uint256, uint256);
    function getProcessedStatus(address _wRWA) external view returns(uint256, uint256);
    function getProcessingAmount(address _wRWA) external view returns(uint256);
    function getWithdrawableStablecoinAmount(address _wRWA) external view returns(uint256);
    function getRepayInfo(address _wRWA) external view returns(RepayInfo[][] memory);

    /// @notice Check if the redemption of a certain NFT has been processed. 
    /// @notice True ->processed   false ->unprocessed
    /// @param  _tokenId   The tokenId of NFT
    function isRedeemProcessed(uint256 _tokenId) external view returns(bool);

    /// @notice Check how many stablecoin can be redeemed for a certain NFT
    /// @param  _tokenId    The tokenId of NFT
    /// @dev When the NFT is not processed, return 0
    function getNFTTotalValue(uint256 _tokenId) external view returns(uint256);

    /// @notice Get all NFTs owned by the user
    /// @param  _user   The address of user
    /// @return tokenIds  The tokenId of NFTs
    function getOwnedNFT(address _user) external view returns(uint256[] memory tokenIds);

    /// @notice Get all NFTs owned by the user in a certain wRWA asset.
    /// @param  _user    The address of user
    /// @param  _wRWA    The address of wRWA
    /// @return tokenIdsWRWA  The tokenId of NFTs
    function getOwnedNFTOfWRWA(address _user, address _wRWA) external view returns(uint256[] memory tokenIdsWRWA);
}