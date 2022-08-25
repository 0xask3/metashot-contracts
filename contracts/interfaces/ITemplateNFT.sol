// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ITemplateNFT {
    // ------ View functions ------
    /**
        Recommended royalty for tokenId sale.
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);

    // ------ Admin functions ------
    function setRoyaltyReceiver(uint256 tokenId, address receiver) external;

    function setRoyaltyFee(uint256 fee) external;
}