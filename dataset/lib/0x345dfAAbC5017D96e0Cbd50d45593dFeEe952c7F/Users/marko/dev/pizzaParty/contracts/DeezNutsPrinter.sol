pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";


contract OwnableDelegateProxy {}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

abstract contract ERC721Tradable is ERC721Enumerable, Ownable {
    using Strings for string;
    using SafeMath for uint256;

    address proxyRegistryAddress;
    uint256 public MAX_SUPPLY;
    address factoryAddress;
    uint256 private _currentTokenId = 0;

    constructor(
        string memory _name,
        string memory _symbol,
        address _proxyRegistryAddress
    ) ERC721(_name, _symbol) {
        MAX_SUPPLY = 10000;
        proxyRegistryAddress = _proxyRegistryAddress;
    }

    // todo ipfs hash might be removed

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mintTo(address _to) public onlyOwner {
        require(totalSupply() <= MAX_SUPPLY, "Purchase would exceed max supply");
        uint256 newTokenId = _getNextTokenId();
        _mint(_to, newTokenId);
        _incrementTokenId();
    }


    function factoryMint(address _to) public {
        require(factoryAddress == _msgSender(), "Ownable: caller is not the factory!");
        uint256 newTokenId = _getNextTokenId();
        _mint(_to, newTokenId);
        _incrementTokenId();
    }

    function setFactoryAddress(address _factoryAddress) public onlyOwner {
        factoryAddress = _factoryAddress;
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId.add(1);
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    function baseTokenURI() virtual public pure returns (string memory);

    function tokenURI(uint256 _tokenId) override public pure returns (string memory) {
        return string(abi.encodePacked(baseTokenURI(), uint2str(_tokenId), ".json"));
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        override
        public
        view
        returns (bool)
    {
        // Whitelist OpenSea proxy contract for easy trading.
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        if (address(proxyRegistry.proxies(owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

     /**
     * @dev override transfer to prevent transfer of calimed tokens
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev override transfer to prevent transfer of calimed tokens
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev override transfer to prevent transfer of calimed tokens
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }
    
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function burn(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == _msgSender());
        _burn(_tokenId); 
    }
}

contract DeezNuts is ERC721Tradable{
  constructor(address _proxyRegistryAddress) ERC721Tradable("Deez Nuts", "NTS", _proxyRegistryAddress) {  }

  function baseTokenURI() override public pure returns (string memory) {
        return "https://storage.googleapis.com/deeznutsnft/final/Nut";
  }

}

contract DeezNutsPrinter is Ownable {
    using Strings for string;
    using SafeMath for uint256;

    address public nftAddress;
    uint256 public MAX_SUPPLY;
    uint256 public mintPrice;
    bool public public_minting;


    constructor(address _nftAddress) {
        MAX_SUPPLY = 10000;
        mintPrice = 69000000000000000; // 0.069 ETH
        nftAddress = _nftAddress;
        public_minting = false;
    }

    function name() external pure returns (string memory) {
        return "Deez Nuts Factory";
    }

    function symbol() external pure returns (string memory) {
        return "NTS";
    }

    function mint(uint256 amount, address _toAddress) external payable {
        require(public_minting, "Public minting isn't allowed yet");
        require(mintPrice.mul(amount) <= msg.value, "Ether value sent is not correct");
        require(amount <= 100, "Too many mints! Max is 100.");

        DeezNuts deezNuts = DeezNuts(nftAddress);
        uint256 currentSupply = deezNuts.totalSupply();

        uint256 balanceOfMinter = deezNuts.balanceOf(_msgSender());
        require(balanceOfMinter + amount <= 101, "Minting would exceed 10 mints for user");

        require(currentSupply + amount <= MAX_SUPPLY, "Purchase would exceed max supply");
        
        for (uint256 i = 0; i < amount; i++) {
            deezNuts.factoryMint(_toAddress);
        }
    }

    function presaleMint(uint256 amount, address _toAddress) external payable {
        require(mintPrice.mul(amount) <= msg.value, "Ether value sent is not correct");
        require(amount <= 10, "Too many mints! Max is 10.");

        DeezNuts deezNuts = DeezNuts(nftAddress);
        uint256 currentSupply = deezNuts.totalSupply();

        uint256 balanceOfMinter = deezNuts.balanceOf(_msgSender());
        require(balanceOfMinter + amount <= 10, "Minting would exceed 10 mints for user");
        
        require(currentSupply >= 100, "Private sale still in progress");
        require(currentSupply + amount <= MAX_SUPPLY, "Purchase would exceed max supply");
        
        for (uint256 i = 0; i < amount; i++) {
            deezNuts.factoryMint(_toAddress);
        }

    }

    function privateMint(uint256 amount, address _toAddress) external onlyOwner {
        DeezNuts deezNuts = DeezNuts(nftAddress);
        uint256 currentSupply = deezNuts.totalSupply();
        require(currentSupply + amount <= 100, "Purchase would exceed allocated private sale");

        for (uint256 i = 0; i < amount; i++) {
            deezNuts.factoryMint(_toAddress);
        }

    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        uint256 amount069 = balance.mul(69).div(1000);
        uint256 amount022 = balance.mul(22).div(1000);
        uint256 amount4545 = balance.mul(4545).div(10000);
        
        address wallet069 = 0x8eB97Fca1b0B22807C5d44da43D6C116E74e4DB1;
        address wallet022 = 0xB7FdE283dEE1f7484365f3b06E0f3E1D61304CC4;
        address wallet4545 = 0x82815C90D40073Ad14e1D0cB5bccbf8883862483;
        address wallet45451 = 0x274a5F5Ea6a2E0D184800FE891C4Aa5bCc715347;

        payable(wallet069).transfer(amount069);
        payable(wallet022).transfer(amount022);
        payable(wallet4545).transfer(amount4545);
        payable(wallet45451).transfer(amount4545);
    }

    function setPublicMinting(bool isEnabled) public onlyOwner {
        public_minting = isEnabled;
    }

}