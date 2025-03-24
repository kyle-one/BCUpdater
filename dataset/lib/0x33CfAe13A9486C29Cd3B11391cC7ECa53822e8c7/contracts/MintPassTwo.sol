// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract PvSignedAllowlist {
    using ECDSA for bytes32;

    uint256 private constant UINT256_MAX = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    uint256[] ticketBatches;
    address signer;

    function _verify(
        bytes calldata _signature, 
        uint256 _ticketId, 
        uint256 _amount
    ) internal view {
        bytes32 hash = keccak256(abi.encodePacked(msg.sender, _ticketId, _amount));

        require(hash.toEthSignedMessageHash().recover(_signature) == signer, "signature invalid");
    }

    function _invalidate(uint256 _ticketId) internal {
        require(_ticketId < ticketBatches.length * 256, "ticket does not exist");

        uint256 batchId = _ticketId / 256;
        uint256 ticketIdInBatch = _ticketId % 256;

        require((ticketBatches[batchId] >> ticketIdInBatch) & uint256(1) != 0, "ticket already used");
        ticketBatches[batchId] = ticketBatches[batchId] & ~(uint256(1) << ticketIdInBatch);       
    }

    function isEligible(uint256 _ticketId) public view returns (bool) {
        require(_ticketId < ticketBatches.length * 256, "ticket does not exist");

        return (ticketBatches[_ticketId / 256] >> _ticketId % 256) & uint256(1) == 1;
    }

    function _setTicketSupply(uint256 supply) internal {
        uint256 batchAmount = (supply / 256) + 1;
        uint256[] memory newBatchArray = new uint256[](batchAmount);

        for (uint256 i; i < batchAmount; i++) {
            newBatchArray[i] = UINT256_MAX;
        }

        ticketBatches = newBatchArray;
    }

    function _setSigner(address _signer) internal {
        signer = _signer;
    }
}

abstract contract AbstractERC1155Factory is ERC1155Supply, ERC1155Burnable, Ownable {
    
    string public name_;
    string public symbol_;   

    function name() public view returns (string memory) {
        return name_;
    }

    function symbol() public view returns (string memory) {
        return symbol_;
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
}
/*
* @title ERC1155 token for MintPass #2
*
* @author Niftydude
*/
contract MintPassTwo is PvSignedAllowlist, AbstractERC1155Factory {

    uint256 constant MAX_SUPPLY = 203282;

    uint256 public windowOpens;
    uint256 public windowCloses;

    address redeemContract;
    bool redeemContractFinalized;
    bool redeemEnabled;

    bool mintingClosed;

    constructor(
        string memory _name, 
        string memory _symbol,  
        string memory _uri,
        uint256 _windowOpens,
        uint256 _windowCloses
    ) ERC1155(_uri) {
        name_ = _name;
        symbol_ = _symbol;

        windowOpens = _windowOpens;
        windowCloses = _windowCloses;

        _setSigner(msg.sender);
        _setTicketSupply(MAX_SUPPLY);

        _mint(msg.sender, 0, 10000, "");
    } 

    function mint(
        bytes calldata _signature, 
        uint256 _ticketId,
        uint256 _amount
    ) external {
        require(totalSupply(0) + _amount <= MAX_SUPPLY, "Max supply reached");
        require (block.timestamp > windowOpens && block.timestamp < windowCloses, "Window closed");
        require(!mintingClosed, "minting is closed");

        _verify(_signature, _ticketId, _amount);
        _invalidate(_ticketId);

        _mint(msg.sender, 0, _amount, "");
    } 

    function ownerMint (
        address[] calldata _to, 
        uint256[] calldata _amount
    ) external onlyOwner {
        require(_to.length == _amount.length, "same length required");
        require(!mintingClosed, "minting is closed");

        for(uint256 i; i < _to.length; i++) {
            require(totalSupply(0) + _amount[i] <= MAX_SUPPLY, "Max supply reached");
            _mint(_to[i], 0, _amount[i], "");
        }
    }        

    function burnFromRedeem(
        address _account, 
        uint256 _amount
    ) external {
        require(redeemContract == msg.sender, "Burnable: Only allowed from redeemable contract");
        require(redeemEnabled, "burn from redeem disabled");

        _burn(_account, 0, _amount);
    }  

    function editWindows(
        uint256 _windowOpens, 
        uint256 _windowCloses
    ) external onlyOwner {
        require(_windowOpens < _windowCloses, "open window must be before close window");

        windowOpens = _windowOpens;
        windowCloses = _windowCloses;
    }     

    function finalizeRedeemContract(
        address _redeemContract
    ) external onlyOwner {
        require(!redeemContractFinalized, "contract is finalized");

        redeemContract = _redeemContract;  
        redeemContractFinalized = true;
    } 

    function setURI(
        string memory _baseURI
    ) external onlyOwner {
        _setURI(_baseURI);
    }    

    function toggleRedeem() external onlyOwner {
        redeemEnabled = !redeemEnabled;
    }    

    function closeMintingForever() external onlyOwner {
        mintingClosed = true;
    }   

    function invalidateTickets(
        uint256[] calldata _ticketIds
    ) external onlyOwner {
        for(uint256 i; i < _ticketIds.length; i++) {
             _invalidate(_ticketIds[i]);
        }
    }

    function setSigner(
        address _signer
    ) external onlyOwner {
        _setSigner(_signer);
    }

    function resetWithNewSupply(
        uint256 _supply
    ) external onlyOwner {
        _setTicketSupply(_supply);
    }    
}