// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IToken {
    struct UserAmount {
        address to;
        uint96 amount;
    }
    function airdrop(UserAmount[] calldata airdropData) external;
}

contract FairAuction is Ownable {

    modifier directOnly {
        require(msg.sender == tx.origin);
        _;
    }

    struct BidData {
        uint240 currentBid;
        bool mintClaimed;
        bool refundClaimed;
    }

    mapping(address => BidData) public userToBidData;

    // Auction settings
    bool public auctionOpen;
    uint256 public auctionSupply;
    uint256 public finalPrice;

    // Starting bid settings
    uint256 public baseBid;
    uint256 public startingBidMultiplier;
    uint256 public minBalanceToIncrement;

    // Secondary address
    address public secondaryAddress;
    uint256 public secondaryPercentage;

    // Token contract address
    IToken public token;

    event Bid(address indexed user, uint256 bidAmount, uint256 currentBid, uint256 totalBid);
    event AuctionClaimAndRefund(address indexed user, uint256 mint, uint256 refund);
    event AuctionClaim(address indexed user, uint256 mint);
    event AuctionRefund(address indexed user, uint256 refund);
    
    constructor() { 
        auctionSupply = 2888;
        baseBid = 0.04 ether;
        startingBidMultiplier = 0.01 ether;
        minBalanceToIncrement = 30 ether;
    }

    function bid() external payable directOnly {
        require(auctionOpen, "Auction is not live");

        // Bid must have value and be multiplier of 0.01 ETH
        require(msg.value > 0 && msg.value % 0.01 ether == 0, "Bid is not multiplier of 0.01 ETH");

        // First time bidder must bid higher than starting bid 
        if (userToBidData[msg.sender].currentBid == 0) {
            require (msg.value >= getStartingBid(), "Bid is lower than starting bid");
        }
        
        // Update existing bid
        emit Bid(msg.sender, msg.value, userToBidData[msg.sender].currentBid += uint240(msg.value), address(this).balance);
    }

    // Owner functions
    

    function setAuctionOpen(bool _status) external onlyOwner {
        auctionOpen = _status;
    }

    function setAuctionSupply(uint256 _supply) external onlyOwner {
        auctionSupply = _supply;
    }

    function setFinalPrice(uint256 _price) external onlyOwner {
        finalPrice = _price;
    }

    function setBaseBid(uint256 _value) external onlyOwner {
        baseBid = _value;
    }

    function setMinBalanceToIncrement(uint256 _value) external onlyOwner {
        minBalanceToIncrement = _value;
    }

    function setStartingBidMultiplier(uint256 _value) external onlyOwner {
        startingBidMultiplier = _value;
    }


    function setTokenAddress(address _address) external onlyOwner {
        token = IToken(_address);
    }

    function setSecondaryAddress(address _address) external onlyOwner {
        secondaryAddress = _address;
    }

    function setSecondaryPercentage(uint256 _percentage) external onlyOwner {
        secondaryPercentage = _percentage;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(secondaryAddress != address(0), "Secondary address is not set");
        require(secondaryPercentage > 0, "Secondary percentage is not set");
        _sendETH(msg.sender, (100 - secondaryPercentage) * amount / 100);
        _sendETH(secondaryAddress, (secondaryPercentage) * amount / 100);
    }

    function deposit() external onlyOwner payable { }

    function adminProcessAuctionClaimAndRefund(address[] calldata users) external onlyOwner {
        unchecked {
            require(!auctionOpen, "Auction is still live");
            require(address(token) != address(0), "Token address is not set");
            require(finalPrice > 0, "Final price is not set");
            uint256 len = users.length;
            for (uint256 i = 0; i < len; ++i) {
                address userAddress = users[i];
                // Fetch amount of mint and refund
                uint256 amountToMint = getAmountToMint(userAddress);
                uint256 amountToRefund = getAmountToRefund(userAddress);
                require (amountToMint > 0 || amountToRefund > 0, "User doesn't have any mint or refund");

                // Set user mint and refund to true
                BidData memory bidData = userToBidData[userAddress];
                bidData.mintClaimed = true;
                bidData.refundClaimed = true;
                userToBidData[userAddress] = bidData;

                // Process
                if (amountToMint > 0) {
                    IToken.UserAmount[] memory airdropData = new IToken.UserAmount[](1);
                    airdropData[0] = IToken.UserAmount(userAddress, uint96(amountToMint));
                    token.airdrop(airdropData);
                }
                _sendETH(userAddress, amountToRefund);

                emit AuctionClaimAndRefund(userAddress, amountToMint, amountToRefund);
            }
        }
    }

    function adminProcessAuctionClaim(address[] calldata users) external onlyOwner {
        unchecked {
            require(!auctionOpen, "Auction is still live");
            require(address(token) != address(0), "Token address is not set");
            require(finalPrice > 0, "Final price is not set");
            uint256 len = users.length;
            for (uint256 i = 0; i < len; ++i) {
                address userAddress = users[i];
                // Fetch amount of mint
                uint256 amountToMint = getAmountToMint(userAddress);

                // Set user mint to true
                BidData memory bidData = userToBidData[userAddress];
                bidData.mintClaimed = true;
                userToBidData[userAddress] = bidData;

                // Process
                if (amountToMint > 0) {
                    IToken.UserAmount[] memory airdropData = new IToken.UserAmount[](1);
                    airdropData[0] = IToken.UserAmount(userAddress, uint96(amountToMint));
                    token.airdrop(airdropData);
                }

                emit AuctionClaim(userAddress, amountToMint);
            }
        }
    }

    function adminProcessAuctionRefund(address[] calldata users) external onlyOwner {
        unchecked {
            require(!auctionOpen, "Auction is still live");
            require(address(token) != address(0), "Token address is not set");
            require(finalPrice > 0, "Final price is not set");

            uint256 len = users.length;
            for (uint256 i = 0; i < len; ++i) {
                address userAddress = users[i];
                // Fetch amount of refund
                uint256 amountToRefund = getAmountToRefund(userAddress);

                // Set user refund to true
                BidData memory bidData = userToBidData[userAddress];
                bidData.refundClaimed = true;
                userToBidData[userAddress] = bidData;

                // Process
                _sendETH(userAddress, amountToRefund);

                emit AuctionRefund(userAddress, amountToRefund);
            }
        }
    }

    // View functions
    function getAmountToMint(address user) public view returns (uint256) {
        uint256 _finalPrice = finalPrice;
        require (_finalPrice > 0, "Final price is not set");
        BidData memory bidData = userToBidData[user];
        return bidData.mintClaimed ? 0 : bidData.currentBid / _finalPrice;
    }

    function getAmountToRefund(address user) public view returns (uint256) {
        uint256 _finalPrice = finalPrice;
        require (_finalPrice > 0, "Final price is not set");
        BidData memory bidData = userToBidData[user];
        return bidData.refundClaimed ? 0 : bidData.currentBid % _finalPrice;
    }

    function getStartingBid() public view returns (uint256) {
        return baseBid + (address(this).balance / minBalanceToIncrement) * startingBidMultiplier;
    }

    // Internal functions
    function _sendETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{ value: _amount }("");
        require(success, "Transfer failed");
    }    

}