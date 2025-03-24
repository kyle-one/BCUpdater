// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
* @title ERC1155 token for The Nifty Portal
* @author NFTNick.eth
*/

////////////////////////////////////////////////////////////////////////////
//                                                                        //
//    ________   ___  ________ _________    ___    ___                    //
//   |\   ___  \|\  \|\  _____\\___   ___\ |\  \  /  /|                   //
//   \ \  \\ \  \ \  \ \  \__/\|___ \  \_| \ \  \/  / /                   //   
//    \ \  \\ \  \ \  \ \   __\    \ \  \   \ \    / /                    //   
//     \ \  \\ \  \ \  \ \  \_|     \ \  \   \/  /  /                     //  
//      \ \__\\ \__\ \__\ \__\       \ \__\__/  / /                       //  
//       \|__| \|__|\|__|\|__|        \|__|\___/ /                        //     
//                                        \|___|/                         //
//    ________  ________  ________  _________  ________  ___              //
//    |\   __  \|\   __  \|\   __  \|\___   ___\\   __  \|\  \            //
//    \ \  \|\  \ \  \|\  \ \  \|\  \|___ \  \_\ \  \|\  \ \  \           //
//     \ \   ____\ \  \\\  \ \   _  _\   \ \  \ \ \   __  \ \  \          //
//      \ \  \___|\ \  \\\  \ \  \\  \|   \ \  \ \ \  \ \  \ \  \____     //
//       \ \__\    \ \_______\ \__\\ _\    \ \__\ \ \__\ \__\ \_______\   //
//        \|__|     \|_______|\|__|\|__|    \|__|  \|__|\|__|\|_______|   //
//                                                                        //
////////////////////////////////////////////////////////////////////////////


import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


abstract contract OffchainBouncer is AccessControl, Ownable, EIP712 {
  bytes32 public constant BOUNCER_ROLE = keccak256("BOUNCER_ROLE");

  struct NFTVoucher {
    address minter;
    uint mintLimit;
    uint256 start;
    bytes signature;
  }

  /// @notice Used to define who's capable of generating the whitelist. 
  function addBouncer(address bouncer_) external onlyOwner {
    _setupRole(BOUNCER_ROLE, payable(bouncer_));
  }

  /// @notice Returns a hash of the given NFTVoucher, prepared using EIP712 typed data hashing rules.
  /// @param voucher An NFTVoucher to hash.
  function _hash(NFTVoucher calldata voucher) internal view returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(
      keccak256("NFTVoucher(address minter,uint mintLimit,uint256 start)"),
        voucher.minter,
        voucher.mintLimit,
        voucher.start
      )
    ));
  }

  /// @notice Verifies the signature for a given NFTVoucher, returning the address of the signer.
  /// @dev Will revert if the signature is invalid. Does not verify that the signer is authorized to mint NFTs.
  /// @param voucher An NFTVoucher describing an unminted NFT.
  function _verify(NFTVoucher calldata voucher) internal view returns (address) {
    bytes32 digest = _hash(voucher);
    return ECDSA.recover(digest, voucher.signature);
  }

  /// @notice Used for signing the voucher being generated
  function getChainID() external view returns (uint256) {
    uint256 id;
    assembly {
      id := chainid()
    }
    return id;
  }
}

library OpenSeaGasFreeListing {
  /**
  @notice Returns whether the operator is an OpenSea proxy for the owner, thus
  allowing it to list without the token owner paying gas.
  @dev ERC{721,1155}.isApprovedForAll should be overriden to also check if
  this function returns true.
    */
  function isApprovedForAll(address owner, address operator) internal view returns (bool) {
    OSProxy registry;
    assembly {
      switch chainid()
      case 1 {
        // mainnet
        registry := 0xa5409ec958c83c3f309868babaca7c86dcb077c1
      }
      case 4 {
        // rinkeby
        registry := 0xf57b2c51ded3a29e6891aba85459d600256cf317
      }
    }

    return address(registry) != address(0) && address(registry.proxies(owner)) == operator;
  }
}

contract OwnableDelegateProxy { }

contract OSProxy {
  mapping(address => OwnableDelegateProxy) public proxies;
}

abstract contract ERC1155Bouncer is OffchainBouncer, ERC1155, ERC1155Supply, ERC1155Burnable, Pausable {
  string name_;
  string symbol_; 

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }    

  /**
  * @notice change the base URI for the NFT
  *
  * @param baseURI the new NFT uri base
  */
  function setURI(string memory baseURI) external onlyOwner {
    _setURI(baseURI);
  }

  /**
  * @notice returns the metadata uri for a given id
  *
  * @param _id the NFT to return metadata for
  */
  function uri(uint256 _id) public view override returns (string memory) {
    require(exists(_id), "URI: nonexistent token");

    return string(abi.encodePacked(super.uri(_id), Strings.toString(_id), ".json"));
  }

  // Required overrides
  function supportsInterface(bytes4 interfaceId) public view virtual override (AccessControl, ERC1155) returns (bool) {
    return ERC1155.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
  } 

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal virtual override(ERC1155, ERC1155Supply) {
      super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
  }

  /**
   * OpenSea gas-free listings.
   */

  function isApprovedForAll(address owner, address operator) public view override returns (bool) {
    return OpenSeaGasFreeListing.isApprovedForAll(owner, operator) || super.isApprovedForAll(owner, operator);
  }
}
contract PortalNft is ERC1155Bouncer {
  uint public activelyMintingNft = 0;
  uint256 public maxSupply = 7777;
  uint256 public mintPrice = 0.069 ether; // 420
  uint public publicMintLimit = 3;

  uint256 public publicMintTime = 1642431600;

  // Bouncer that only let's in pre-approved members
  string private constant SIGNING_DOMAIN = "TheNifty";
  string private constant SIGNATURE_VERSION = "1";

  // Caps on mints
  mapping(uint256 => mapping(address => uint256)) public premintTxs;
  mapping(uint256 => mapping(address => uint256)) public publicTxs;

  event Printed(uint256 indexed index, address indexed account, uint256 amount);

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _uri
  ) ERC1155(_uri) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
    name_ = _name;
    symbol_ = _symbol;

    // Send community & team NFTs to The Nifty NFT wallet
    _mint(0xb75D95FB8bC0FC8e156a8fd1d9669be94160c11F, 0, 100, "");
  }

  /**
  * @notice withdraw balance
  *
  * @param _addr the address we are sending the CAYYYYYYUSH to
  */
  function withdraw(address _addr) external onlyOwner {
    uint256 balance = address(this).balance;
    payable(_addr).transfer(balance);
  }


  /**
  * @notice edit the mint price
  *
  * @param _mintPrice the new price in wei
  */
  function setPrice(uint256 _mintPrice) external onlyOwner {
    mintPrice = _mintPrice;
  }

  /**
  * @notice edit windows
  *
  * @param _publicMintTime UNIX timestamp for burn window opening time
  * @param _publicMintLimit The max number of NFTs public minters can mint per txn
  * @param _maxSupply The total number of NFTs that can be minted
  */
  function editMintSettings(
      uint256 _publicMintTime,
      uint256 _publicMintLimit,
      uint256 _maxSupply
  ) external onlyOwner {
      publicMintTime = _publicMintTime;
      publicMintLimit = _publicMintLimit;
      maxSupply = _maxSupply;
  }

  /**
  * @notice change the mint phase
  *
  * @param _tokenId the new token that we're minting
  */
  function setMintingToken(uint _tokenId) external onlyOwner {
    activelyMintingNft = _tokenId;
  }

  /**
  * @notice early minting
  *
  * @param voucher the voucher used to claim
  * @param numberOfTokens how many they'd like to mint
  */
  function voucherMint(NFTVoucher calldata voucher, uint numberOfTokens) external payable whenNotPaused {
    require(premintTxs[activelyMintingNft][msg.sender] < 1 , "wallet mint limit");
    address signer = _verify(voucher);
    require(hasRole(BOUNCER_ROLE, signer), "signature invalid");
    require(numberOfTokens <= voucher.mintLimit, "invalid mint count");
    require(msg.sender == voucher.minter, "invalid voucher");
    require(totalSupply(activelyMintingNft) + numberOfTokens <= maxSupply, "supply exceeded");
    require(block.timestamp >= voucher.start, "invalid mint time");
    
    premintTxs[activelyMintingNft][msg.sender] += 1;
    _issuePortalPasses(numberOfTokens);
  }

  /**
  * @notice special minting method only for contract owner
  *
  * @param addr the address these should be minted to
  * @param numberOfTokens how many to mint
  */
  function ownerMint(address addr, uint numberOfTokens) external onlyOwner {
    require(totalSupply(0) + numberOfTokens <= maxSupply, "Max supply reached");
    _mint(addr, 0, numberOfTokens, "");
    emit Printed(0, addr, numberOfTokens);
  }

  /**
  * @notice public mint phase
  *
  * @param numberOfTokens how many to mint
  */
  function publicMint(uint numberOfTokens) external payable whenNotPaused {
    require(block.timestamp >= publicMintTime, "public mint closed");
    require(publicTxs[activelyMintingNft][msg.sender] < 1 , "wallet mint limit");
    require(numberOfTokens > 0 && numberOfTokens <= publicMintLimit, "exceeds max nfts per txn");

    // Limited transactions per wallet on public mint
    publicTxs[activelyMintingNft][msg.sender] += 1;
    _issuePortalPasses(numberOfTokens);
  }

  /**
  * @notice global function for issuing the portal passes (the core minting function)
  *
  * @param amount the amount of tokens to mint
  */
  function _issuePortalPasses(uint256 amount) private {
    require(totalSupply(0) + amount <= maxSupply, "Purchase: Max supply reached");
    require(msg.value == amount * mintPrice, "Purchase: Incorrect payment");

    _mint(msg.sender, 0, amount, "");
    emit Printed(0, msg.sender, amount);
  }
}
