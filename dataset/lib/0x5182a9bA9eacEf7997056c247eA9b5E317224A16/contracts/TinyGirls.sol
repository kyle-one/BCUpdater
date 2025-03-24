pragma solidity 0.8.4;

import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


import "@openzeppelin/contracts/access/Ownable.sol";


interface ILayerZeroReceiver {
    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external;
}

interface ILayerZeroUserApplicationConfig {
    // @notice set the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _configType - type of configuration. every messaging library has its own convention.
    // @param _config - configuration in the bytes. can encode arbitrary content.
    function setConfig(uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config) external;

    // @notice set the send() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setSendVersion(uint16 _version) external;

    // @notice set the lzReceive() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setReceiveVersion(uint16 _version) external;

    // @notice Only when the UA needs to resume the message flow in blocking mode and clear the stored payload
    // @param _srcChainId - the chainId of the source chain
    // @param _srcAddress - the contract address of the source contract at the source chain
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external;
}

interface ILayerZeroEndpoint is ILayerZeroUserApplicationConfig {
    // @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    // @param _dstChainId - the destination chain identifier
    // @param _destination - the address on destination chain (in bytes). address length/format may vary by chains
    // @param _payload - a custom bytes payload to send to the destination contract
    // @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    // @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    // @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function send(uint16 _dstChainId, bytes calldata _destination, bytes calldata _payload, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external payable;

    // @notice used by the messaging library to publish verified payload
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source contract (as bytes) at the source chain
    // @param _dstAddress - the address on destination chain
    // @param _nonce - the unbound message ordering nonce
    // @param _gasLimit - the gas limit for external contract execution
    // @param _payload - verified payload to send to the destination contract
    function receivePayload(uint16 _srcChainId, bytes calldata _srcAddress, address _dstAddress, uint64 _nonce, uint _gasLimit, bytes calldata _payload) external;

    // @notice get the inboundNonce of a receiver from a source chain which could be EVM or non-EVM chain
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (uint64);

    // @notice get the outboundNonce from this source chain which, consequently, is always an EVM
    // @param _srcAddress - the source chain contract address
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external view returns (uint64);

    // @notice gets a quote in source native gas, for the amount that send() requires to pay for message delivery
    // @param _dstChainId - the destination chain identifier
    // @param _userApplication - the user app address on this EVM chain
    // @param _payload - the custom message to send over LayerZero
    // @param _payInZRO - if false, user app pays the protocol fee in native token
    // @param _adapterParam - parameters for the adapter service, e.g. send some dust native token to dstChain
    function estimateFees(uint16 _dstChainId, address _userApplication, bytes calldata _payload, bool _payInZRO, bytes calldata _adapterParam) external view returns (uint nativeFee, uint zroFee);

    // @notice get this Endpoint's immutable source identifier
    function getChainId() external view returns (uint16);

    // @notice the interface to retry failed message on this Endpoint destination
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    // @param _payload - the payload to be retried
    function retryPayload(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external;

    // @notice query if any STORED payload (message blocking) at the endpoint.
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool);

    // @notice query if the _libraryAddress is valid for sending msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getSendLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the _libraryAddress is valid for receiving msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getReceiveLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the non-reentrancy guard for send() is on
    // @return true if the guard is on. false otherwise
    function isSendingPayload() external view returns (bool);

    // @notice query if the non-reentrancy guard for receive() is on
    // @return true if the guard is on. false otherwise
    function isReceivingPayload() external view returns (bool);

    // @notice get the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _userApplication - the contract address of the user application
    // @param _configType - type of configuration. every messaging library has its own convention.
    function getConfig(uint16 _version, uint16 _chainId, address _userApplication, uint _configType) external view returns (bytes memory);

    // @notice get the send() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getSendVersion(address _userApplication) external view returns (uint16);

    // @notice get the lzReceive() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getReceiveVersion(address _userApplication) external view returns (uint16);
}

abstract contract NonblockingReceiver is Ownable, ILayerZeroReceiver {
    ILayerZeroEndpoint public endpoint;

    struct FailedMessages {
        uint payloadLength;
        bytes32 payloadHash;
    }

    mapping(uint16 => mapping(bytes => mapping(uint => FailedMessages))) public failedMessages;
    mapping(uint16 => bytes) public trustedSourceLookup;

    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload);

    // abstract function
    function _LzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) virtual internal;

    function lzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) external override {
        require(msg.sender == address(endpoint)); // boilerplate! lzReceive must be called by the endpoint for security
        require(_srcAddress.length == trustedSourceLookup[_srcChainId].length && keccak256(_srcAddress) == keccak256(trustedSourceLookup[_srcChainId]), "NonblockingReceiver: invalid source sending contract");

        // try-catch all errors/exceptions
        // having failed messages does not block messages passing
        try this.onLzReceive(_srcChainId, _srcAddress, _nonce, _payload) {
            // do nothing
        } catch {
            // error / exception
            failedMessages[_srcChainId][_srcAddress][_nonce] = FailedMessages(_payload.length, keccak256(_payload));
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        }
    }

    function onLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) public {
        // only internal transaction
        require(msg.sender == address(this), "NonblockingReceiver: caller must be Bridge.");
        _LzReceive( _srcChainId, _srcAddress, _nonce, _payload);
    }

    function _lzSend(uint16 _dstChainId, bytes memory _payload, address payable _refundAddress, address _zroPaymentAddress, bytes memory _txParam) internal {
        endpoint.send{value: msg.value}(_dstChainId, trustedSourceLookup[_dstChainId], _payload, _refundAddress, _zroPaymentAddress, _txParam);
    }

    function retryMessage(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes calldata _payload) external payable {
        // assert there is message to retry
        FailedMessages storage failedMsg = failedMessages[_srcChainId][_srcAddress][_nonce];
        require(failedMsg.payloadHash != bytes32(0), "NonblockingReceiver: no stored message");
        require(_payload.length == failedMsg.payloadLength && keccak256(_payload) == failedMsg.payloadHash, "LayerZero: invalid payload");
        // clear the stored message
        failedMsg.payloadLength = 0;
        failedMsg.payloadHash = bytes32(0);
        // execute the message. revert if it fails again
        this.onLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function setTrustedSource(uint16 _chainId, bytes calldata _trustedSource) external onlyOwner {
        require(trustedSourceLookup[_chainId].length == 0, "The trusted source address has already been set for the chainId!");
        trustedSourceLookup[_chainId] = _trustedSource;
    }
}
/* 
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░██████████████░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░██▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░██▒██▒▒▒██▒░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░██░░▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░██▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░███▒█▒███░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░▒▒█▒█▒█▒▒░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░▒▒█▒█▒█▒▒░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░███████░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░███████░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░▒▒▒░▒▒▒░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░███░███░░░░░░░░░░░░░░░░░░░░░
░░░░═══░░░║░║░║░║░░░░░░░░░░░░░░░░░░░░░░░
░░░░░║░░║░║░░║░╚╦╝░░░░░░░░░░░░░░░░░░░░░░
░░░░░║░░║░║░─║░░║░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░══░░░░░░║░░══░░░░░░░░░░░░░░░░░░░░░░
░░░░║░░░░░░░░║░║░░░░░░░░░░░░░░░░░░░░░░░░
░░░░║░═░║░╔═░║░░═░░░░░░░░░░░░░░░░░░░░░░░
░░░░░══░║░║░░║░══║░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ */

/// @title A LayerZero OmnichainNonFungibleToken Contract
/// @author Tiny Girls
/// @notice You can use this to mint ONFT and transfer across chain
/// @dev All function calls are currently implemented without side effects
contract TinyGirls is ERC721, NonblockingReceiver, ILayerZeroUserApplicationConfig {

    using Strings for uint256;
    string public baseTokenURI;
    string public baseTokenNotRevealedURI;

    address _owner;

    uint256 public nextTokenId;
    uint256 public immutable maxSupply;
    uint256 public immutable maxMintPerTx = 2;
    uint256 public immutable maxPerWallet = 3;

    bool public revealed = false;

    /// @notice Constructor for the OmnichainNonFungibleToken
    /// @param _baseTokenURI the Uniform Resource Identifier (URI) for tokenId token
    /// @param _layerZeroEndpoint handles message transmission across chains
    /// @param _startToken the starting mint number on this chain
    /// @param _maxSupply the max number of mints on this chain
    constructor(
        string memory _baseTokenURI,
        string memory _baseTokenNotRevealedURI,
        address _layerZeroEndpoint,
        uint256 _startToken,
        uint256 _maxSupply
    )
    ERC721("TinyGirls", "TG"){
        setBaseURI(_baseTokenURI);
        setBaseNotRevealedURI(_baseTokenNotRevealedURI);
        endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        nextTokenId = _startToken;
        maxSupply = _maxSupply;
        _owner = msg.sender;

        for(uint8 i = 0; i < 100; i++){
            _safeMint(msg.sender, nextTokenId++);
        }
    }

    function mint(uint8 _amountMint) external {
        require(_amountMint > 0 && _amountMint <= maxMintPerTx, "Tiny Girls: Only 3 mint per TX");
        require(nextTokenId + _amountMint <= maxSupply, "Tiny Girls: Max supply for this chain");
        require(_amountMint <= maxMintPerTx && balanceOf(msg.sender) <= maxPerWallet, "Tiny Girls: Only max 3 for address");
        
        _safeMint(msg.sender, ++nextTokenId);
        if (_amountMint == 2) {
            _safeMint(msg.sender, ++nextTokenId);
        }
    }

    function totalSupply() public view returns (uint) {
        return maxSupply;
    }
    
    function reveal() public onlyOwner {
        revealed = true;
    }

    /// @notice Burn OmniChainNFT_tokenId on source chain and mint on destination chain
    /// @param _chainId the destination chain id you want to transfer too
    /// @param omniChainNFT_tokenId the id of the ONFT you want to transfer
    function traverseNFT(
        uint16 _chainId,
        uint256 omniChainNFT_tokenId
    ) public payable {
        require(trustedSourceLookup[_chainId].length != 0, "This chain is not a trusted source source.");

        // burn ONFT on source chain
         _burn(omniChainNFT_tokenId);

        // encode payload w/ sender address and ONFT token id
        bytes memory payload = abi.encode(msg.sender, omniChainNFT_tokenId);

        // encode adapterParams w/ extra gas for destination chain
        // This example uses 500,000 gas. Your implementation may need more.
        uint16 version = 1;
        uint gas = 350000;
        bytes memory adapterParams = abi.encodePacked(version, gas);

        // use LayerZero estimateFees for cross chain delivery
        (uint quotedLayerZeroFee, ) = endpoint.estimateFees(_chainId, address(this), payload, false, adapterParams);

        require(msg.value >= quotedLayerZeroFee, "Not enough gas to cover cross chain transfer.");

        endpoint.send{value:msg.value}(
            _chainId,                      // destination chainId
            trustedSourceLookup[_chainId], // destination address of OmnichainNFT
            payload,                       // abi.encode()'ed bytes
            payable(msg.sender),           // refund address
            address(0x0),                  // future parameter
            adapterParams                  // adapterParams
        );
    }

    /// @notice Set the baseTokenURI
    /// @param _baseTokenURI to set
    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }
    
    function setBaseNotRevealedURI(string memory _baseTokenNotRevealedURI) public onlyOwner {
        baseTokenNotRevealedURI = _baseTokenNotRevealedURI;
    }

    /// @notice Get the base URI
    function _baseURI() override internal view returns (string memory) {
        return baseTokenURI;
    }
    function tokenURI(uint256 tokenId) public view virtual override returns(string memory){
        require(_exists(tokenId),"ERC721Metadata: URI query for nonexistent token");

        if(!revealed) {
            return baseTokenNotRevealedURI;
        }

        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI, tokenId.toString(),".json")) : "";
    }

    /// @notice Override the _LzReceive internal function of the NonblockingReceiver
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    /// @dev safe mints the ONFT on your destination chain
    function _LzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override  {
        (address _dstAddress, uint256 tokenId) = abi.decode(_payload, (address, uint256));
        _safeMint(_dstAddress, tokenId);
    }

    //---------------------------DAO CALL----------------------------------------
    // generic config for user Application
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyOwner {
        endpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyOwner {
        endpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyOwner {
        endpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        endpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    function renounceOwnership() public override onlyOwner {}
}