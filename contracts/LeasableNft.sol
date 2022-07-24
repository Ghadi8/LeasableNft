// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice tokens
import "./ERC4907.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Leasable NFT
 * @author Ghadi Mhawej
 **/

contract LeasableNft is Ownable, ERC4907, ERC721Burnable, ERC721Pausable {
    /// @notice using safe math for uints (uints might cause an overflow ==> reverts transaction when an oveflow occurs!)
    using SafeMath for uint256;
    using SafeMath for uint32;

    /// @notice using Strings for uints conversions such as => tokenId
    using Strings for uint256;

    /// @notice using Address for addresses extended functionality
    using Address for address;

    /// @notice using a counter to increment next Id to be minted
    using Counters for Counters.Counter;

    /// @notice EIP721-required Base URI
    /// This is a Uniform Resource Identifier, distinct used to identify each unique nft from the other.
    string private _baseTokenURI;

    /// @notice URI to hide NFTS during minting
    string public _notRevealedURI;

    /// @notice Base extension for metadata
    string private _baseExtension;

    /// @notice token id to be minted next
    Counters.Counter private _tokenIdTracker;

    /// @notice The rate of minting per phase
    uint256 public _mintPrice;

    /// @notice The rate of mints per user
    mapping(address => uint256) public _mintsPerUser;

    /// @notice Max number of NFTs to be minted
    uint32 private _maxTokenId;

    /// @notice max amount of nfts that can be minted per wallet address
    uint32 private _mintingLimit;

    /// @notice Splitter Contract that will collect mint fees;
    address payable private _mintingBeneficiary;

    /// @notice public metadata locked flag
    bool public locked;

    /// @notice public revealed state
    bool public revealed;

    /// @notice Minting events definition
    event AdminMinted(address indexed to, uint256 indexed tokenId);
    event Minted(address indexed to, uint256 indexed tokenId);

    /// @notice metadata not locked modifier
    /// Require function, the first parameter is the condition, if it is not met, then the second parameter is will be outputed
    modifier notLocked() {
        require(!locked, "LeasableNft: Metadata URIs are locked");
        /// The uncommon instruction specified where the function should be executed
        _;
    }

    /// @notice Art is not revealed modifier
    modifier notRevealed() {
        require(!revealed, "LeasableNft: Art is already revealed");
        _;
    }

    /// @notice Art is already revealed
    modifier Revealed() {
        require(revealed, "LeasableNft: Art is not revealed");
        _;
    }

    /// @notice constructor
    /// @param name the name of the EIP721 contract
    /// @param symbol the token symbol
    /// @param baseTokenURI EIP721-required Base URI
    /// @param notRevealedURI URI ot hide NFTs during minting

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        string memory notRevealedURI,
        uint256 mintPrice_,
        uint32 mintingLimit_,
        uint32 maxTokenId_
    ) ERC4907(name, symbol) Ownable() {
        _mintPrice = mintPrice_;
        _mintingLimit = mintingLimit_;
        _maxTokenId = maxTokenId_;
        _baseExtension = ".json";
        _baseTokenURI = baseTokenURI;
        _notRevealedURI = notRevealedURI;
        _mintingBeneficiary = payable(msg.sender);
        _tokenIdTracker.increment();
    }

    /// @notice receive fallback should revert
    /// @notice receive payement address without any minting.

    receive() external payable {
        revert("LeasableNft: Please use Mint or Admin calls");
    }

    /// @notice default fallback should revert
    fallback() external payable {
        revert("LeasableNft: Please use Mint or Admin calls");
    }

    /// @notice returnd the base URI for the contract
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC4907)
        returns (bool)
    {
        return
            interfaceId == type(IERC4907).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @dev See {IERC721Metadata-tokenURI}
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return
            revealed
                ? string(
                    abi.encodePacked(super.tokenURI(tokenId), _baseExtension)
                )
                : _notRevealedURI;
    }

    /// @notice updates the 2 addresses involved in the contract flow
    /// @param mintingBeneficiary the contract Splitter that will receive minting and royalties funds
    /// @param _owner the new admin address

    function updateAddressesAndTransferOwnership(
        address mintingBeneficiary,
        address _owner
    ) public onlyOwner {
        changeMintBeneficiary(mintingBeneficiary);
        transferOwnership(_owner);
    }

    /// @notice changes the minting beneficiary payable address
    /// @notice beneficiary the contract Splitter that will receive minting funds

    /**
     * @notice a function for admins to mint cost-free
     * @param to the address to send the minted token to
     **/

    function adminMint(address to) external whenNotPaused onlyOwner {
        require(to != address(0), "LeasableNft: Address cannot be 0");
        maxSupplyNotExceeded(1);
        _safeMint(to, _tokenIdTracker.current());
        emit AdminMinted(to, _tokenIdTracker.current());
        _tokenIdTracker.increment();
    }

    /// @notice the public minting function -- requires 1 ether sent
    /// @param to the address to send the minted token to
    /// @param amount amount of tokens to mint

    function mint(address to, uint32 amount) external payable whenNotPaused {
        uint256 received = msg.value;
        require(to != address(0), "LeasableNft: Address cannot be 0");
        require(
            received == _mintPrice.mul(amount),
            "LeasableNft: Ether sent is not the right amount"
        );

        maxSupplyNotExceeded(amount);

        checkLimit(to, amount);
        _mintsPerUser[to] += amount;

        for (uint32 i = amount; i > 0; i--) {
            _safeMint(to, _tokenIdTracker.current());
            emit Minted(to, _tokenIdTracker.current());
            _tokenIdTracker.increment();
        }

        _forwardFunds(received);
    }

    /// @notice pausing the cotract minting and token transfer
    function pause() public virtual onlyOwner {
        _pause();
    }

    /// @notice unpausing the contract minting and token transfer
    function unpause() public virtual onlyOwner {
        _unpause();
    }

    function changeMintBeneficiary(address beneficiary) public onlyOwner {
        require(
            beneficiary != address(0),
            "LeasableNft: Minting beneficiary cannot be address 0"
        );

        require(
            beneficiary != _mintingBeneficiary,
            "LeasableNft: beneficiary cannot be the same as previous"
        );
        _mintingBeneficiary = payable(beneficiary);
    }

    ///@notice gets the amounts of mints per wallet address
    function getMintingLimit() public view returns (uint256) {
        return _mintingLimit;
    }

    /// @notice changes the minting cost
    /// @param mintCost new minting cost

    function changeMintCost(uint256 mintCost) public onlyOwner {
        require(
            mintCost != _mintPrice,
            "LeasableNft: mint cost cannot be same as previous"
        );
        _mintPrice = mintCost;
    }

    function changeBaseURI(string memory newBaseURI)
        public
        onlyOwner
        notLocked
    {
        require(
            (keccak256(abi.encodePacked((_baseTokenURI))) !=
                keccak256(abi.encodePacked((newBaseURI)))),
            "LeasableNft: Base URI cannot be same as previous"
        );
        _baseTokenURI = newBaseURI;
    }

    /**
     * @notice changes to not revealed URI
     * @param newNotRevealedUri the new notRevealed URI
     **/
    function changeNotRevealedURI(string memory newNotRevealedUri)
        public
        onlyOwner
        notRevealed
    {
        require(
            (keccak256(abi.encodePacked((newNotRevealedUri))) !=
                keccak256(abi.encodePacked((_notRevealedURI)))),
            "LeasableNft: Base URI cannot be same as previous"
        );
        _notRevealedURI = newNotRevealedUri;
    }

    ///@notice reveal NFTs
    function reveal() public onlyOwner notRevealed {
        revealed = true;
    }

    /// @notice lock metadata forever
    function lockMetadata() public onlyOwner notLocked Revealed {
        locked = true;
    }

    ///@notice the public function for checking if more tokens can be minted
    function maxSupplyNotExceeded(uint32 amount) public view returns (bool) {
        require(
            _tokenIdTracker.current().add(amount.sub(1)) <= _maxTokenId,
            "LeasableNft: max NFT limit exceeded"
        );
        return true;
    }

    /// @notice Current totalSupply
    function totalSupply() external view returns (uint256) {
        return (_tokenIdTracker.current()).sub(1);
    }

    /// @notice Determines how ETH is stored/forwarded on purchases.
    /// @param received amount to forward

    function _forwardFunds(uint256 received) internal {
        /// @notice forward fund to Splitter contract using CALL to avoid 2300 stipend limit
        (bool success, ) = _mintingBeneficiary.call{value: received}("");
        require(success, "LeasableNft: Failed to forward funds");
    }

    /// @notice before transfer hook function
    /// @param from the address to send the token from
    /// @param to the address to send the token to
    /// @param tokenId to token ID to be sent

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Pausable, ERC4907) {
        super._beforeTokenTransfer(from, to, tokenId);
        if (from != to && _users[tokenId].user != address(0)) {
            delete _users[tokenId];
            emit UpdateUser(tokenId, address(0), 0);
        }
    }

    function checkLimit(address minter, uint32 amount)
        internal
        view
        returns (bool)
    {
        require(
            _mintsPerUser[minter].add(amount) <= _mintingLimit,
            "LeasableNft: Max NFT per address exceeded"
        );
        return true;
    }
}
