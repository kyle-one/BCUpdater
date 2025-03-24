// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract AccessLock is Ownable {
    mapping(address => bool) public isAdmin; // user => isAdmin? mapping

    /// @notice emitted when admin role is granted or revoked
    event AdminSet(address indexed user,bool isEnabled);

    /// @notice Grant or Revoke Admin Access
    /// @param user - Address of User
    /// @param isEnabled - Grant or Revoke?
    function setAdmin(address user, bool isEnabled) external onlyOwner {
        isAdmin[user] = isEnabled;
        emit AdminSet(user, isEnabled);
    }

    /// @notice reverts if caller is not admin or owner
    modifier onlyAdmin() {
        require(
            isAdmin[msg.sender] || msg.sender == owner(),
            "Caller does not have Admin/Owner access"
        );
        _;
    }
}

interface IMoonRatzWTF is IERC721 {
    /// @notice - Mint NFT
    /// @dev - callable only by admin
    /// @param recipient - mint to
    /// @param quantity - number of NFTs to mint
    function mint(address recipient, uint256 quantity) external;
}

/// @title MoonRatzWTF Mint
/// @author 0xhohenheim <contact@0xhohenheim.com>
/// @notice NFT Sale contract for minting MoonRatzWTF NFTs
contract SaleMoonRatzWTF is AccessLock, Pausable, ReentrancyGuard {
    IMoonRatzWTF public NFT;
    uint256 public limit;
    uint256 public userLimit;
    uint256 public count;
    mapping(address => uint256) public userCount;

    event Minted(address indexed user, uint256 quantity);
    event LimitUpdated(address indexed owner, uint256 limit);
    event UserLimitUpdated(address indexed owner, uint256 userLimit);

    constructor(
        IMoonRatzWTF _NFT,
        uint256 _limit,
        uint256 _userLimit
    ) {
        NFT = _NFT;
        _pause();
        setLimit(_limit);
        setUserLimit(_userLimit);
    }

    function setLimit(uint256 _limit) public onlyOwner {
        limit = _limit;
        emit LimitUpdated(owner(), limit);
    }

    function setUserLimit(uint256 _userLimit) public onlyOwner {
        userLimit = _userLimit;
        emit UserLimitUpdated(owner(), userLimit);
    }

    function _mint(uint256 quantity) private {
        NFT.mint(msg.sender, quantity);
        count = count + quantity;
        userCount[msg.sender] = userCount[msg.sender] + quantity;
        emit Minted(msg.sender, quantity);
    }

    function mint(uint256 quantity)
        external
        whenNotPaused
        nonReentrant
    {
        require((count + quantity) <= limit, "Sold out");
        require(
            ((userCount[msg.sender] + quantity) <= userLimit) ||
                msg.sender == owner(),
            "Wallet limit reached"
        );
        _mint(quantity);
    }

    function withdraw(address payable wallet, uint256 amount)
        external
        onlyOwner
    {
        wallet.transfer(amount);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}
