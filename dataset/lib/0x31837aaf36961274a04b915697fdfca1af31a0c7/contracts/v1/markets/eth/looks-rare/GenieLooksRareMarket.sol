// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";


import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


abstract contract Recoverable is Ownable {
    function recoverEther() external onlyOwner {
        SendUtils._returnAllEth();
    }
}



library SendUtils {
    using Address for address payable;

    function _returnAllEth() internal {
        // NOTE: This works on the assumption that the whole balance of the contract consists of
        // the ether sent by the caller.
        // (1) This is never 100% true because anyone can send ether to it with selfdestruct or by using
        // its address as the coinbase when mining a block. Anyone doing that is doing it to their own
        // disavantage though so we're going to disregard these possibilities.
        // (2) For this to be safe we must ensure that no ether is stored in the contract long-term.
        // It's best if it has no receive function and all payable functions should ensure that they
        // use the whole balance or send back the remainder.
        if (address(this).balance > 0)
            payable(msg.sender).sendValue(address(this).balance);
    }
}

abstract contract ArbitraryCall is Ownable {
    using Address for address payable;

    event ArbitraryCallReturn(bytes returndata);

    /// Performs an external call to the specified address with the specified arguments.
    /// This function is meant to allow the owner of the contract to reap benefits of being
    /// a frequent customer of OpenSea. For example, to collect an airdrop.
    ///
    /// @dev This function would be a big security liability in a contract holding significant amounts
    /// of funds or being whilelisted to perform privileged actions in other contracts. Currently
    /// this is not the case and it's very important to ensure that it stays that way.
    /// This function gives the owner the ability to freely impersonate the contract. If the owner contract
    /// gets compromised, the attacker will have the same power.
    function arbitraryCall(address payable targetContract, bytes calldata encodedArguments) public payable onlyOwner returns (bytes memory) {
        // NOTE: If the contract has no receive() function and the target contract tries to send ether
        // back to msg.sender, the transaction will fail.
        bytes memory returndata = targetContract.functionCallWithValue(encodedArguments, msg.value);

        SendUtils._returnAllEth();
        emit ArbitraryCallReturn(returndata);
        return returndata;
    }
}

interface ILooksRareExchange {

    struct MakerOrder {
        bool isOrderAsk; // true --> ask / false --> bid
        address signer; // signer of the maker order
        address collection; // collection address
        uint256 price; // price (used as )
        uint256 tokenId; // id of the token
        uint256 amount; // amount of tokens to sell/purchase (must be 1 for ERC721, 1+ for ERC1155)
        address strategy; // strategy for trade execution (e.g., DutchAuction, StandardSaleForFixedPrice)
        address currency; // currency (e.g., WETH)
        uint256 nonce; // order nonce (must be unique unless new maker order is meant to override existing one e.g., lower ask price)
        uint256 startTime; // startTime in timestamp
        uint256 endTime; // endTime in timestamp
        uint256 minPercentageToAsk; // slippage protection (9000 --> 90% of the final price must return to ask)
        bytes params; // additional parameters
        uint8 v; // v: parameter (27 or 28)
        bytes32 r; // r: parameter
        bytes32 s; // s: parameter
    }

    struct TakerOrder {
        bool isOrderAsk; // true --> ask / false --> bid
        address taker; // msg.sender
        uint256 price; // final price for the purchase
        uint256 tokenId;
        uint256 minPercentageToAsk; // // slippage protection (9000 --> 90% of the final price must return to ask)
        bytes params; // other params (e.g., tokenId)
    }

    function matchAskWithTakerBidUsingETHAndWETH(
        TakerOrder calldata takerBid,
        MakerOrder calldata makerAsk
    ) external payable;
}

contract GenieLooksRareMarket is Recoverable, ArbitraryCall {

    address public constant LOOKSRARE_EXCHANGE = 0x59728544B08AB483533076417FbBB2fD0B17CE3a;
    bytes4 public constant IID_IERC1155 = type(IERC1155).interfaceId;
    bytes4 public constant IID_IERC721 = type(IERC721).interfaceId;

    function buyAssetsForEth(
        ILooksRareExchange.TakerOrder[] calldata takerOrders,
        ILooksRareExchange.MakerOrder[] calldata makerOrders,
        address recipient
    ) external payable {
        for (uint256 i = 0; i < takerOrders.length; i++) {
            _buyAssetForEth(takerOrders[i], makerOrders[i], recipient);
        }
        SendUtils._returnAllEth();
    }

    function _buyAssetForEth(
        ILooksRareExchange.TakerOrder calldata takerOrder,
        ILooksRareExchange.MakerOrder calldata makerOrder,
        address recipient
    ) internal {
        try ILooksRareExchange(LOOKSRARE_EXCHANGE).matchAskWithTakerBidUsingETHAndWETH{value: takerOrder.price}(
            takerOrder,
            makerOrder
        ) {
            if (IERC165(makerOrder.collection).supportsInterface(IID_IERC721)) {
                IERC721(makerOrder.collection).transferFrom(address(this), recipient, makerOrder.tokenId);
            } else if (IERC165(makerOrder.collection).supportsInterface(IID_IERC1155)) {
                IERC1155(makerOrder.collection).safeTransferFrom(address(this), recipient, makerOrder.tokenId, makerOrder.amount, "0x");
            } else {
                revert("Unsupported interface");
            }
        } catch {}
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}