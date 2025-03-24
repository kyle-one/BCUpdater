// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts/access/Ownable.sol";


contract Operator is Ownable {
    address public operator;

    event OperatorChanged(address operator);

    modifier onlyOperator() {
        if (operator != _msgSender()) revert OnlyOperatorError();
        _;
    }

    constructor(address _operator) {
        if (_operator == address(0)) revert OperatorZeroAddressCheck();
        operator = _operator;
    }

    /**
     * @notice change operator
     */
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert OperatorZeroAddressCheck();

        operator = _operator;
        emit OperatorChanged(_operator);
    }
}


interface IBAYCSewerPass {
    function mintSewerPass(
        address to,
        uint256 mintdata
    ) external returns (uint256);
}



interface WarmInterface {
    function ownerOf(
        address contractAddress,
        uint256 tokenId
    ) external view returns (address);
}

interface DelegateCashInterface {
    function checkDelegateForToken(
        address delegate,
        address vault,
        address contract_,
        uint256 tokenId
    ) external view returns (bool);
}

contract YugaVerify {
    address public immutable WARM_WALLET_CONTRACT;
    address public immutable DELEGATE_CASH_CONTRACT;

    constructor(address _warmWalletContract, address _delegateCashContract) {
        if (
            _warmWalletContract == address(0) ||
            _delegateCashContract == address(0)
        ) revert ZeroAddressCheck();
        WARM_WALLET_CONTRACT = _warmWalletContract;
        DELEGATE_CASH_CONTRACT = _delegateCashContract;
    }

    /**
     * @notice verify contract token based claim using warm wallet and delegate cash
     * @param tokenContract the smart contract address of the token
     * @param tokenId the tokenId
     */
    function verifyTokenOwner(
        address tokenContract,
        uint256 tokenId
    ) internal view returns (bool) {
        address tokenOwner = IERC721(tokenContract).ownerOf(tokenId);

        // 1. check contract token owner
        // 2. check warm wallet delegation - ownerOf()
        //      all delegation
        //      is a mapping of token owner's wallet to hot wallet
        //      coldWalletToHotWallet[owner].walletAddress
        // 3. check delegate.cash delegation - checkDelegateForToken()
        //      checks three forms of delegation all, contract, and contract/token id
        return (msg.sender == tokenOwner ||
            msg.sender ==
            WarmInterface(WARM_WALLET_CONTRACT).ownerOf(
                tokenContract,
                tokenId
            ) ||
            DelegateCashInterface(DELEGATE_CASH_CONTRACT).checkDelegateForToken(
                    msg.sender,
                    tokenOwner,
                    tokenContract,
                    tokenId
                ));
    }
}

//      |||||\          |||||\               |||||\           |||||\
//      ||||| |         ||||| |              ||||| |          ||||| |
//       \__|||||\  |||||\___\|               \__|||||\   |||||\___\|
//          ||||| | ||||| |                      ||||| |  ||||| |
//           \__|||||\___\|       Y u g a         \__|||||\___\|
//              ||||| |             L a b s          ||||| |
//          |||||\___\|          Sewer Pass      |||||\___\|
//          ||||| |                 Claim        ||||| |
//           \__|||||||||||\                      \__|||||||||||\
//              ||||||||||| |                        ||||||||||| |
//               \_________\|                         \_________\|

error ClaimIsNotActive();
error TokenAlreadyClaimed();
error UnauthorizedOwner();

/**
 * @title BAYC Sewer Pass Claim Smart Contract
 */
contract BAYCSewerPassClaim is Operator, YugaVerify, ReentrancyGuard {
    uint64 constant TIER_FOUR = 4;
    uint64 constant TIER_THREE = 3;
    uint64 constant TIER_TWO = 2;
    uint64 constant TIER_ONE = 1;
    uint256 constant NO_DOGGO = 10000;
    address public immutable BAYC_CONTRACT;
    address public immutable MAYC_CONTRACT;
    address public immutable BAKC_CONTRACT;
    bool public claimIsActive;
    mapping(uint256 => bool) public baycClaimed;
    mapping(uint256 => bool) public maycClaimed;
    mapping(uint256 => bool) public bakcClaimed;
    IBAYCSewerPass public immutable sewerPassContract;

    event SewerPassMinted(
        uint256 indexed sewerPassTokenId,
        uint256 indexed tier,
        uint256 indexed baycMaycTokenId,
        uint256 bakcTokenId
    );

    modifier claimable() {
        if (!claimIsActive) revert ClaimIsNotActive();
        _;
    }

    constructor(
        address _baycContract,
        address _maycContract,
        address _bakcContract,
        address _warmContract,
        address _delegateCashContract,
        address _sewerPassContract,
        address _operator
    ) Operator(_operator) YugaVerify(_warmContract, _delegateCashContract) {
        BAYC_CONTRACT = _baycContract;
        MAYC_CONTRACT = _maycContract;
        BAKC_CONTRACT = _bakcContract;
        sewerPassContract = IBAYCSewerPass(_sewerPassContract);
    }

    /**
     * @notice Claim Sewer Pass with BAYC and BAKC pair - TIER 4
     * @param baycTokenId token id of the ape
     * @param bakcTokenId token id of the dog
     */
    function claimBaycBakc(
        uint256 baycTokenId,
        uint256 bakcTokenId
    ) external claimable nonReentrant {
        _checkBaycClaim(baycTokenId);
        _checkBakcClaim(bakcTokenId);
        _mintSewerPass(TIER_FOUR, baycTokenId, bakcTokenId);
    }

    /**
     * @notice Claim Sewer Pass with with BAYC - TIER 3
     * @param baycTokenId token id of the ape
     */
    function claimBayc(uint256 baycTokenId) external claimable nonReentrant {
        _checkBaycClaim(baycTokenId);
        _mintSewerPass(TIER_THREE, baycTokenId, NO_DOGGO);
    }

    /**
     * @notice Claim Sewer Pass with MAYC and BAKC pair - TIER 2
     * @param maycTokenId token id of the mutant
     * @param bakcTokenId token id of the dog
     */
    function claimMaycBakc(
        uint256 maycTokenId,
        uint256 bakcTokenId
    ) external claimable nonReentrant {
        _checkMaycClaim(maycTokenId);
        _checkBakcClaim(bakcTokenId);
        _mintSewerPass(TIER_TWO, maycTokenId, bakcTokenId);
    }

    /**
     * @notice Claim Sewer Pass with MAYC - TIER 1
     * @param maycTokenId token id of the mutant
     */
    function claimMayc(uint256 maycTokenId) external claimable nonReentrant {
        _checkMaycClaim(maycTokenId);
        _mintSewerPass(TIER_ONE, maycTokenId, NO_DOGGO);
    }

    // Manage token checks and claim status

    function _checkBaycClaim(uint256 tokenId) private {
        if (!verifyTokenOwner(BAYC_CONTRACT, tokenId))
            revert UnauthorizedOwner();
        if (baycClaimed[tokenId]) revert TokenAlreadyClaimed();
        baycClaimed[tokenId] = true;
    }

    function _checkMaycClaim(uint256 tokenId) private {
        if (!verifyTokenOwner(MAYC_CONTRACT, tokenId))
            revert UnauthorizedOwner();
        if (maycClaimed[tokenId]) revert TokenAlreadyClaimed();
        maycClaimed[tokenId] = true;
    }

    function _checkBakcClaim(uint256 tokenId) private {
        if (!verifyTokenOwner(BAKC_CONTRACT, tokenId))
            revert UnauthorizedOwner();
        if (bakcClaimed[tokenId]) revert TokenAlreadyClaimed();
        bakcClaimed[tokenId] = true;
    }

    function _mintSewerPass(
        uint64 tier,
        uint256 baycMaycTokenId,
        uint256 bakcTokenId
    ) private {
        // prepare mint data for storage
        uint256 mintData = uint256(tier);
        mintData |= baycMaycTokenId << 64;
        mintData |= bakcTokenId << 128;

        uint256 sewerPassTokenId = sewerPassContract.mintSewerPass(
            _msgSender(),
            mintData
        );
        emit SewerPassMinted(
            sewerPassTokenId,
            tier,
            baycMaycTokenId,
            bakcTokenId
        );
    }

    /**
     * @notice Check BAYC/MAYC/BAKC token claim status - bayc = 0, mayc = 1, bakc = 2
     * @param collectionId id of the collection see above
     * @param tokenId id of the ape, mutant or dog
     */
    function checkClaimed(
        uint8 collectionId,
        uint256 tokenId
    ) external view returns (bool) {
        if (collectionId == 0) {
            return baycClaimed[tokenId];
        } else if (collectionId == 1) {
            return maycClaimed[tokenId];
        } else if (collectionId == 2) {
            return bakcClaimed[tokenId];
        }
        return false;
    }

    // Operator functions

    /**
     * @notice Flip the claim state
     */
    function flipClaimIsActiveState() external onlyOperator {
        claimIsActive = !claimIsActive;
    }

    /**
     * @notice Withdraw erc-20 tokens sent to the contract by error
     * @param coinContract the erc-20 contract address
     */
    function withdraw(address coinContract) external onlyOperator {
        uint256 balance = IERC20(coinContract).balanceOf(address(this));
        if (balance > 0) {
            IERC20(coinContract).transfer(operator, balance);
        }
    }
}
