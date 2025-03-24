// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";


 * enumerability of all the token ids in the contract as well as all token ids owned by each
 * account.
 */
abstract contract ERC721Enumerable is ERC721, IERC721Enumerable {
    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721.balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721Enumerable.totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = ERC721.balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}
// @author: miinded.com

/////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////
//                                                                                    ///
//                                                                                    ///
//                                                                                    ///
//                                                                                    ///
//                                                                                    ///
//                                                                                    ///
//                                                                                    ///
//                                              .--==-:.                              ///
//                                 ..-=++=:     -==****.                              ///
//                               +#%@@@@#+-:.  -=+****-                               ///
//                               +#@@%##*+-::--=+****:                                ///
//                 .::           =#%@%##*=-:--+****+.                                 ///
//                 .:::.         -***++-::--+*****:                                   ///
//                  .::::.      .==*+=--=+****##*=-:.                                 ///
//                   ..:::::::.:*-+#%%%##***#%%%#%##*+=:.                             ///
//                   ..:--==++++++#%%%%###%@%@%%%%###++=-..:.                         ///
//                      .:-=++****#%%#######%%%%%%%%%%%%%#+*+-.                       ///
//                          :=*****###%%@@@@@@@@@@@@@%@@@%%%%*=.                      ///
//                        :-==*#%@@@@@@@@@@@@@@@@@@%###%@@@##**=                      ///
//                       ::=#@@@@@@@@@@@@@@@@@@@@@@####%@@%#+===                      ///
//                      .-%@@@@@@@@%%%##*#@@@@@@@@@#####@@%%@*=++-.                   ///
//                      :*%%@@@@@@@*=#%%****###%%%#**##%@@%%@%%%###*:                 ///
//                      .#*%%@@%+:.:=*%%#+*##*=-*#**###%@@%@@@%@%###*                 ///
//                       +*##%@-  ..===+++*+=++*######%%@%%@@@@@@@%#*                 ///
//                      .+*+**@*:.=+++*++*#+-#%@####%%%%%%@%%@@@@%#=.                 ///
//                    :--*+*##@@@%%%@####%%%:#%@%####@@%%@%#%%%%*                     ///
//                   -+*+*++##%@@@@@@%++#%%@*%%@#%%#%@@%@@%####%=                     ///
//                   -#####=+%%@@@@@@@###%%%@%*#%%@@%@@%@@@%###%=                     ///
//                    ###*#++#%@@@@@@@%%%%%%@@@%%@%@@@@%%@@@%###=                     ///
//                    :+++#**#%%@@@@@@%%%%%@@@@@@@@@@@@@@%@@@%#*-                     ///
//                       -%%%%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%%#-                     ///
//                        %@@#%@@@@@@@@@@%%%%%@@@@@@@@@@@@@@@@@#-            :-::==-::///
//                        -@@*@@@@@@@@@@%####%%@@@%%%@@@@@@%#**###+.  ..-: .=++*+*###*///
//                            +@@@@@@%%@%####%%@@%%%##%%%%#*###%#%#+=++#%%**+++###***+///
//                             %@@@++*#%*=++**#######%###########%#+++=#@@%#%*+++**#%%///
//                              -+*=+=-::::::--==+*#**+++=-++++**#*+++=*@@@@%%%%##*+++///
//                          :*=-==-:.   .....:::--==++++--#%****#%#++*++%@@@%@@@@@@%%%///
//                        --===-...:::----=============++%@@%%###%%*+*++#@@@@%@@@@@@@@///
//                 .::-*%*--=-.::------========++++======+*%%%%%%%@#+*#**%@@@@%@@@@@@@///
//       :.:-=+%%---:*%*+==-::-----=====+=++++++++++*++===+*%%%#***++#%#*#%@@@@@@@@@@@///
//    :**#%=+@%%==--*@#*+=::-=--=====+++*+*++++*#%#++**+++++*%%##*****@@##%@@@@@@@@@@@///
/////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////

contract MekaVerse is ERC721Enumerable, Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    uint256 public constant MAX_ELEMENTS = 8888;
    uint256 public constant PRICE = 0.2 ether;
    uint256 public constant START_AT = 1;

    address public constant creator1Address = 0xCaE02A17288a40E702fc24161d8DDAEF1D546c23;
    address public constant creator2Address = 0xDc7C0ca1b4C3b89D9Fe8a73aA25ebdC35aE25797;
    address public constant devAddress = 0x3c5ff56De82eCAf0dCE4063CAf42c756C5C29f71;

    bool private PAUSE = true;

    Counters.Counter private _tokenIdTracker;

    string public baseTokenURI;

    event PauseEvent(bool pause);
    event welcomeToMekaVerse(uint256 indexed id);

    constructor(string memory baseURI) ERC721("MekaVerse", "MEKA"){
        setBaseURI(baseURI);
    }

    modifier saleIsOpen {
        require(totalToken() <= MAX_ELEMENTS, "Soldout!");
        require(!PAUSE, "Sales not open");
        _;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function totalToken() public view returns (uint256) {
        return _tokenIdTracker.current();
    }

    function mint(uint256[] memory _tokensId, uint256 _timestamp, bytes memory _signature) public payable saleIsOpen {

        uint256 total = totalToken();
        require(_tokensId.length <= 2, "Max limit");
        require(total + _tokensId.length <= MAX_ELEMENTS, "Max limit");
        require(msg.value >= price(_tokensId.length), "Value below price");

        address wallet = _msgSender();

        address signerOwner = signatureWallet(wallet,_tokensId,_timestamp,_signature);
        require(signerOwner == owner(), "Not authorized to mint");

        require(block.timestamp >= _timestamp - 30, "Out of time");

        for(uint8 i = 0; i < _tokensId.length; i++){
            require(rawOwnerOf(_tokensId[i]) == address(0) && _tokensId[i] > 0 && _tokensId[i] <= MAX_ELEMENTS, "Token already minted");
            _mintAnElement(wallet, _tokensId[i]);
        }

    }

    function signatureWallet(address wallet, uint256[] memory _tokensId, uint256 _timestamp, bytes memory _signature) public view returns (address){

        return ECDSA.recover(keccak256(abi.encode(wallet, _tokensId, _timestamp)), _signature);

    }

    function _mintAnElement(address _to, uint256 _tokenId) private {

        _tokenIdTracker.increment();
        _safeMint(_to, _tokenId);

        emit welcomeToMekaVerse(_tokenId);
    }

    function price(uint256 _count) public pure returns (uint256) {
        return PRICE.mul(_count);
    }

    function walletOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function setPause(bool _pause) public onlyOwner{
        PAUSE = _pause;
        emit PauseEvent(PAUSE);
    }

    function withdrawAll() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0);
        _widthdraw(devAddress, balance.mul(15).div(100));
        _widthdraw(creator2Address, balance.mul(42).div(100));
        _widthdraw(creator1Address, address(this).balance);
    }

    function _widthdraw(address _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    function getUnsoldTokens(uint256 offset, uint256 limit) external view returns (uint256[] memory){

        uint256[] memory tokens = new uint256[](limit);

        for (uint256 i = 0; i < limit; i++) {
            uint256 key = i + offset;
            if(rawOwnerOf(key) == address(0)){
                tokens[i] = key;
            }
        }

        return tokens;
    }

    function mintUnsoldTokens(uint256[] memory _tokensId) public onlyOwner {

        require(PAUSE, "Pause is disable");

        for (uint256 i = 0; i < _tokensId.length; i++) {
            if(rawOwnerOf(_tokensId[i]) == address(0)){
                _mintAnElement(owner(), _tokensId[i]);
            }
        }
    }
}
