// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IERC721PepeMetadata {
	
	function setBaseURI(string memory uri) external;
	
	function setPepeContract(address _pepe) external;
	
	function tokenURI(uint256 hash) external view returns (string memory);
			
}



interface IERC721Pepe is IERC721 {
	
	function setBaseURI(string memory uri) external;
	
	function setPepeMinter(address _minter) external;
	
	function setAuthorizedSigningAddress(address signer) external;
	
	function mint(address to, uint256 imageHash) external;
	
	function burn(uint256 _tokenId) external;
			
}

contract ERC721PepeMinter is Ownable {

    bytes32 private PEPEOBJECT_TYPEHASH = keccak256("PepeObject(address userAddress,uint256 timestamp,uint256 imageHash)");
    bytes32 public DOMAIN_SEPARATOR;

    address public pepeContract;
    address public authorizedSigningAddress;
    uint256 public signatureExpireSeconds;

    constructor(address _authorizedSigningAddress, uint256 _signatureExpireSeconds) {
        authorizedSigningAddress = _authorizedSigningAddress;
        signatureExpireSeconds = _signatureExpireSeconds;

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("McPepe's"),
            keccak256("1"),
            block.chainid,
            this // this contract verifies the signature
        ));
    }

    function setPepeContract(address _pepeContract) external onlyOwner {
        pepeContract = _pepeContract;
    }

    function setAuthorizedSigningAddress(address signer) external onlyOwner {
        authorizedSigningAddress = signer;
    }

    function setSignatureExpireSeconds(uint256 expireSeconds) external onlyOwner {
        signatureExpireSeconds = expireSeconds;
    }

    function splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "bad signature length");

        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
            // second 32 bytes.
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function mint(uint256 timestamp, uint256 imageHash, bytes memory signature) external {
        // Split signature into main components
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = splitSignature(signature);

        bytes32 hashStruct = keccak256(
            abi.encode(
                PEPEOBJECT_TYPEHASH,
                msg.sender,
                timestamp,
                imageHash
            )
        );

        // 1. hashing the data (above is part of this) and generating the hashes
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));

        // 2. use the data hashes and the signature to generate the public key opf the signer using ercecover method
        address signer = ecrecover(hash, v, r, s);
        require(signer == authorizedSigningAddress, "invalid signature");
        require(signer != address(0), "signature 0x0");
        require(timestamp + signatureExpireSeconds > block.timestamp, "signature expired");

        // 3. mint pepe, checking imageHash is not already existing
        IERC721Pepe(pepeContract).mint(msg.sender, imageHash);
    }
}



contract ERC721Pepe is ERC721, Ownable {
    address public minter;
    address public metadata;
    uint256 public tokenId = 1;

    // Mappings from imageHash to tokenId and vice versa
    mapping(uint256 => uint256) public imageHashTokenIds;
    mapping(uint256 => uint256) public tokenIdImageHashes;

    constructor(string memory name_, string memory symbol_, address minterContract, address metadataContract) ERC721(name_, symbol_) {
        minter = minterContract;
        metadata = metadataContract;
    }

    function setPepeMinter(address minterContract) external onlyOwner {
        minter = minterContract;
    }

    function setPepeMetadata(address metadataContract) external onlyOwner {
        metadata = metadataContract;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        _requireMinted(_tokenId);

        // send the tokenId and hash to the metadata contract for further processing
        uint256 hash = tokenIdImageHashes[_tokenId];
        string memory uri = IERC721PepeMetadata(metadata).tokenURI(hash);
        return uri;
    }

    function mint(address to, uint256 imageHash) external {
        require(msg.sender == minter, "must be minter");

        // check imageHash doesn't already exist
        require(imageHashTokenIds[imageHash] == 0, "hash exists");

        // store imageHash <=> tokenId
        imageHashTokenIds[imageHash] = tokenId;
        tokenIdImageHashes[tokenId] = imageHash;

        _mint(to, tokenId++);
    }

    function burn(uint256 _tokenId) external {
        require(msg.sender == ownerOf(_tokenId), "must be owner");

        // look up imageHash from tokenId
        uint256 imageHash = tokenIdImageHashes[_tokenId];

        // clean up mappings
        delete imageHashTokenIds[imageHash];
        delete tokenIdImageHashes[_tokenId];

        _burn(_tokenId);
    }
}
