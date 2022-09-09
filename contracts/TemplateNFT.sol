// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/**
 * @title LICENSE REQUIREMENT
 * @dev This contract is licensed under the MIT license.
 */

import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/ITemplateNFT.sol";
import "./utils/OpenseaProxy.sol";

contract TemplateNFT is
    ERC721AUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    ITemplateNFT // implements IERC2981
{
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIndexCounter; // token index counter
    uint256 public constant MAX_PER_MINT_LIMIT = 50; // based on ERC721A limitations

    uint256 public startTimestamp;

    uint256 public reserved;
    uint256 public maxSupply;
    uint256 public maxPerMint;
    uint256 public maxPerWallet;
    uint256 public price;

    uint256 public royaltyFee;

    address public payoutReceiver;

    bool public isPayoutChangeLocked;
    bool private isOpenSeaProxyActive;
    bool private startAtOne;

    /**
     * @dev Additional uri details of a particular token
     */
    mapping(uint256 => string) private URI_POSTFIX;

    /**
     * @dev Additional data for each token that needs to be stored and accessed on-chain
     */
    mapping(uint256 => bytes32) public data;

    /**
     * @dev Storing how many tokens each address has minted in public sale
     */
    mapping(address => uint256) public mintedBy;

    /**
     * @dev Reciver of royalty for a particular token Id
     */
    mapping(uint256 => address) public royaltyReceiver;

    string public PROVENANCE_HASH = "";
    string private CONTRACT_URI = "";
    string private BASE_URI = "";
    string private EXTENSION = "";

    function initialize(
        uint256 _price,
        uint256 _maxSupply,
        uint256 _nReserved,
        uint256 _maxPerMint,
        uint256 _royaltyFee,
        string memory _name,
        string memory _symbol,
        string memory _uri,
        bool _startAtOne
    ) public initializerERC721A initializer {
        startTimestamp = block.timestamp + 60;

        price = _price;
        reserved = _nReserved;
        maxPerMint = _maxPerMint;
        maxPerWallet = _maxPerMint;
        maxSupply = _maxSupply;

        royaltyFee = _royaltyFee;

        BASE_URI = _uri;

        isOpenSeaProxyActive = true;

        startAtOne = _startAtOne;

        __ERC721A_init(_name, _symbol);
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    // This constructor ensures that this contract can only be used as a master copy
    // Marking constructor as initializer makes sure that real initializer cannot be called
    // Thus, as the owner of the contract is 0x0, no one can do anything with the contract
    // on the other hand, it's impossible to call this function in proxy,
    // so the real initializer is the only initializer
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function _baseURI() internal view override returns (string memory) {
        return BASE_URI;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return startAtOne ? 1 : 0;
    }

    function contractURI() public view returns (string memory uri) {
        uri = bytes(CONTRACT_URI).length > 0 ? CONTRACT_URI : _baseURI();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (bytes(URI_POSTFIX[tokenId]).length > 0) {
            return
                string(
                    abi.encodePacked(BASE_URI, URI_POSTFIX[tokenId], EXTENSION)
                );
        } else {
            return super.tokenURI(tokenId);
        }
    }

    function startTokenId() public view returns (uint256) {
        return _startTokenId();
    }

    // ----- Admin functions -----

    function setBaseURI(string calldata uri) public onlyOwner {
        BASE_URI = uri;
    }

    function setExtension(string calldata _extension) public onlyOwner {
        EXTENSION = _extension;
    }

    // Contract-level metadata for Opensea
    function setContractURI(string calldata uri) public onlyOwner {
        CONTRACT_URI = uri;
    }

    function setPostfixURI(uint256 _tokenId, string calldata postfix)
        public
        onlyOwner
    {
        URI_POSTFIX[_tokenId] = postfix;
    }

    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    function reduceMaxSupply(uint256 _maxSupply)
        public
        whenSaleNotStarted
        onlyOwner
    {
        require(
            _totalMinted() + reserved <= _maxSupply,
            "Max supply is too low, already minted more (+ reserved)"
        );

        require(
            _maxSupply < maxSupply,
            "Cannot set higher than the current maxSupply"
        );

        maxSupply = _maxSupply;
    }

    // Lock changing withdraw address
    function lockPayoutChange() public onlyOwner {
        isPayoutChangeLocked = true;
    }

    // function to disable gasless listings for security in case
    // opensea ever shuts down or is compromised
    // from CryptoCoven https://etherscan.io/address/0x5180db8f5c931aae63c74266b211f580155ecac8#code
    function setIsOpenSeaProxyActive(bool _isOpenSeaProxyActive)
        public
        onlyOwner
    {
        isOpenSeaProxyActive = _isOpenSeaProxyActive;
    }

    // ---- Minting ----

    function _mintConsecutive(
        uint256 nTokens,
        address to,
        bytes32 extraData
    ) internal {
        require(
            _totalMinted() + nTokens + reserved <= maxSupply,
            "Not enough Tokens left."
        );

        uint256 nextTokenId = _nextTokenId();

        _safeMint(to, nTokens, "");

        if (extraData.length > 0) {
            for (uint256 i; i < nTokens; i++) {
                uint256 tokenId = nextTokenId + i;
                data[tokenId] = extraData;
            }
        }
    }

    // ---- Mint control ----

    modifier whenSaleStarted() {
        require(saleStarted(), "Sale not started");
        _;
    }

    modifier whenSaleNotStarted() {
        require(!saleStarted(), "Sale should not be started");
        _;
    }

    modifier whenNotPayoutChangeLocked() {
        require(!isPayoutChangeLocked, "Payout change is locked");
        _;
    }

    // ---- Mint public ----

    function mintSingle(string calldata uri)
        external
        payable
        nonReentrant
        whenSaleStarted
    {   
        uint256 currentId = totalSupply();
        URI_POSTFIX[currentId] = uri;
        mint(1);
    }

    // Contract can sell tokens
    function mint(uint256 nTokens) internal {
        // setting it to 0 means no limit
        if (maxPerWallet > 0) {
            require(
                mintedBy[msg.sender] + nTokens <= maxPerWallet,
                "You cannot mint more than maxPerWallet tokens for one address!"
            );

            // only store minted amounts after limit is enabled to save gas
            mintedBy[msg.sender] += nTokens;
        }

        require(
            nTokens <= maxPerMint,
            "You cannot mint more than MAX_TOKENS_PER_MINT tokens at once!"
        );

        require(nTokens * price <= msg.value, "Inconsistent amount sent!");

        _mintConsecutive(nTokens, msg.sender, 0x0);
    }

    // Owner can claim free tokens
    function claim(uint256 nTokens, address to)
        external
        nonReentrant
        onlyOwner
    {
        require(nTokens <= reserved, "That would exceed the max reserved.");

        reserved = reserved - nTokens;

        _mintConsecutive(nTokens, to, 0x0);
    }

    // ---- Mint configuration

    function updateMaxPerMint(uint256 _maxPerMint)
        external
        onlyOwner
        nonReentrant
    {
        require(_maxPerMint <= MAX_PER_MINT_LIMIT, "Too many tokens per mint");
        maxPerMint = _maxPerMint;
    }

    // set to 0 to save gas, mintedBy is not used
    function updateMaxPerWallet(uint256 _maxPerWallet)
        external
        onlyOwner
        nonReentrant
    {
        maxPerWallet = _maxPerWallet;
    }

    // ---- Sale control ----

    function updateStartTimestamp(uint256 _startTimestamp) public onlyOwner {
        startTimestamp = _startTimestamp;
    }

    function startSale() public onlyOwner {
        startTimestamp = block.timestamp;
    }

    function stopSale() public onlyOwner {
        startTimestamp = type(uint256).max;
    }

    function saleStarted() public view returns (bool) {
        return block.timestamp >= startTimestamp;
    }

    // ---- Offchain Info ----

    // This should be set before sales open.
    function setProvenanceHash(string memory provenanceHash) public onlyOwner {
        PROVENANCE_HASH = provenanceHash;
    }

    function setRoyaltyFee(uint256 _royaltyFee) public onlyOwner {
        royaltyFee = _royaltyFee;
    }

    function setRoyaltyReceiver(uint256 _tokenId, address _receiver)
        public
        onlyOwner
    {
        royaltyReceiver[_tokenId] = _receiver;
    }

    function setPayoutReceiver(address _receiver)
        public
        onlyOwner
        whenNotPayoutChangeLocked
    {
        payoutReceiver = payable(_receiver);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = getRoyaltyReceiver(tokenId);
        royaltyAmount = (salePrice * royaltyFee) / 10000;
    }

    function getPayoutReceiver()
        public
        view
        returns (address payable receiver)
    {
        receiver = payoutReceiver != address(0x0)
            ? payable(payoutReceiver)
            : payable(owner());
    }

    function getRoyaltyReceiver(uint256 tokenId)
        public
        view
        returns (address payable receiver)
    {
        receiver = royaltyReceiver[tokenId] != address(0x0)
            ? payable(royaltyReceiver[tokenId])
            : getPayoutReceiver();
    }

    // ---- Allow royalty deposits from Opensea -----

    receive() external payable {}

    function _withdraw() private {
        uint256 balance = address(this).balance;
        address payable receiver = getPayoutReceiver();

        AddressUpgradeable.sendValue(receiver, balance);
    }

    function withdraw() public virtual onlyOwner {
        _withdraw();
    }

    function withdrawToken(IERC20Upgradeable token) public virtual onlyOwner {
        uint256 balance = token.balanceOf(address(this));

        address payable receiver = getPayoutReceiver();

        token.safeTransfer(receiver, balance);
    }

    // -------- ERC721 overrides --------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return
            interfaceId == type(IERC2981Upgradeable).interfaceId ||
            interfaceId == type(ITemplateNFT).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Override isApprovedForAll to allowlist user's OpenSea proxy accounts to enable gas-less listings.
     * Taken from CryptoCoven: https://etherscan.io/address/0x5180db8f5c931aae63c74266b211f580155ecac8#code
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        // Get a reference to OpenSea's proxy registry contract by instantiating
        // the contract using the already existing address.
        ProxyRegistry proxyRegistry = ProxyRegistry(
            0xa5409ec958C83C3f309868babACA7c86DCB077c1
        );

        if (
            isOpenSeaProxyActive &&
            address(proxyRegistry.proxies(owner)) == operator
        ) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }
}
