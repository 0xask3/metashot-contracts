// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";

/** @title NFT marketplace creation contract.
 */
contract Marketplace is
    AccessControl,
    Pausable,
    ERC1155Holder,
    IERC721Receiver
{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    /** Role identifier for the NFT creator role. */
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    /** Auction duration timestamp. */
    uint256 public biddingTime;

    /** Minimum auction duration timestamp. */
    uint256 public minBiddingTime;

    /** Maximum auction duration timestamp. */
    uint256 public maxBiddingTime;

    /** Counts total number of orders. */
    Counters.Counter private _numOrders;

    /** Address of the tokens used to pay for items. */
    mapping(address => bool) public acceptedTokens;

    /** Emitted when a new order is placed. */
    event PlacedOrder(
        uint256 indexed orderId,
        address itemContract,
        address token,
        uint256 indexed itemId,
        address indexed owner,
        uint256 basePrice
    );

    /** Emitted when an order is cancelled. */
    event CancelledOrder(uint256 indexed orderId, bool isSold);

    /** Emitted at the new highest bid. */
    event NewHighestBid(
        uint256 indexed orderId,
        address indexed maker,
        uint256 bidAmount
    );

    /** Emitted when the bidding time changes. */
    event BiddingTimeChanged(address from, uint256 newBiddingTime);

    /** Emitted when the auction is finished. */
    event AuctionFinished(uint256 indexed orderId, uint256 numBids);

    /** Emitted when a new purchase occures. */
    event Purchase(
        uint256 indexed orderId,
        address itemContract,
        uint256 indexed itemId,
        address maker,
        address taker,
        uint256 price
    );

    /** Order type: fixed price or auction. */
    enum OrderType {
        FixedPrice,
        Auction
    }

    /** contract type: erc721 or erc1155. */
    enum ContractType {
        erc721,
        erc1155
    }

    /** Order struct. */
    struct Order {
        /** Item contract address. */
        address itemContract;
        /** Address of payment token */
        address token;
        /** Item id. */
        uint256 itemId;
        /** Item Amount */
        uint256 itemAmount;
        /** Base price in  tokens. */
        uint256 basePrice;
        /** Listing timestamp. */
        uint256 listedAt;
        /** Expiration timestamp - 0 for fixed price. */
        uint256 expiresAt;
        /** Ending time - set at cancellation. */
        uint256 endTime;
        /** Number of bids, always points to last (i.e. highest) bid. */
        uint256 numBids;
        /** Bid step in  tokens. */
        uint256 bidStep;
        /** Maker address. */
        address maker;
        /** Order type. */
        OrderType orderType;
        /** Contract Type */
        ContractType contractType;
    }

    /** Bid struct. */
    struct Bid {
        /** Bid amount in  tokens. */
        uint256 amount;
        /** Bidder address. */
        address bidder;
    }

    /** Orders by id. */
    mapping(uint256 => Order) public orders; // orderId => Order

    /** Bids by order and bid id. */
    mapping(uint256 => mapping(uint256 => Bid)) public bids; // orderId => bidId => Bid

    /** Stale time */
    uint256 private constant staleTime = 90 days;

    /** @notice Creates marketplace contract.
     * @dev Grants `DEFAULT_ADMIN_ROLE` to `msg.sender`.
     * Grants `CREATOR_ROLE` to `_itemCreator`.
     * @param _biddingTime Initial bidding time.
     */
    constructor(
        uint256 _biddingTime,
        uint256 _minBiddingTime,
        uint256 _maxBiddingTime
    ) {
        biddingTime = _biddingTime;
        minBiddingTime = _minBiddingTime;
        maxBiddingTime = _maxBiddingTime;

        acceptedTokens[address(0)] = true; //ETH Payment

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /** @notice Pausing some functions of contract.
    @dev Available only to admin.
    Prevents calls to functions with `whenNotPaused` modifier.
  */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /** @notice Unpausing functions of contract.
    @dev Available only to admin.
  */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /** @notice Changes bidding time.
     * @dev Available only to admin.
     *
     * Emits a {BiddingTimeChanged} event.
     *
     * @param _biddingTime New bidding time (timestamp).
     */
    function changeBiddingTime(uint256 _biddingTime)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            _biddingTime > minBiddingTime && _biddingTime < maxBiddingTime,
            "Time must be within the min and max"
        );
        biddingTime = _biddingTime;
        emit BiddingTimeChanged(msg.sender, _biddingTime);
    }

    /** @notice Changes accepted tokens.
     * @dev Available only to admin.
     *
     * Emits a {BiddingTimeChanged} event.
     *
     * @param _token Token to be changed.
     * @param _status whether added or removed.
     */
    function changeAcceptedTokens(address _token, bool _status)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        acceptedTokens[_token] = _status;
    }

    function cancelStaleOrders(uint256[] memory orderId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 len = orderId.length;
        for (uint8 i = 0; i < len; i++) {
            Order memory order = orders[orderId[i]];
            require(
                order.orderType == OrderType.FixedPrice,
                "Can't cancel an auction order"
            );
            if (order.listedAt + staleTime < block.timestamp) {
                _cancelOrder(orderId[i], false);
            }
        }
    }

    /** @notice Lists user item with a fixed price on the marketplace.
     *
     * Requirements:
     * - `basePrice` can't be zero.
     *
     * @param itemId Item ID.
     * @param basePrice Price of the item.
     */
    function listFixedPrice721(
        address itemContract,
        address token,
        uint256[] memory itemId,
        uint256[] memory basePrice
    ) external whenNotPaused {
        uint256 len = itemId.length;
        require(acceptedTokens[token], "Invalid payment token");
        for (uint8 i = 0; i < len; i++) {
            _addOrder(
                itemContract,
                token,
                itemId[i],
                1,
                basePrice[i],
                0,
                OrderType.FixedPrice,
                ContractType.erc721
            );
        }
    }

    /** @notice Lists user auction item on the marketplace.
     *
     * Requirements:
     * - `basePrice` can't be zero.
     * - `bidStep` can't be zero.
     *
     * @param itemId Item ID.
     * @param basePrice Price of the item.
     * @param bidStep Bid step.
     */
    function listAuction721(
        address itemContract,
        address token,
        uint256[] memory itemId,
        uint256[] memory basePrice,
        uint256[] memory bidStep
    ) external whenNotPaused {
        uint256 len = itemId.length;
        require(acceptedTokens[token], "Invalid payment token");
        for (uint8 i = 0; i < len; i++) {
            _addOrder(
                itemContract,
                token,
                itemId[i],
                1,
                basePrice[i],
                bidStep[i],
                OrderType.Auction,
                ContractType.erc721
            );
        }
    }

    /** @notice Lists user item with a fixed price on the marketplace.
     *
     * Requirements:
     * - `basePrice` can't be zero.
     *
     * @param itemId Item ID.
     * @param basePrice Price of the item.
     */
    function listFixedPrice1155(
        address itemContract,
        address token,
        uint256[] memory itemId,
        uint256[] memory amount,
        uint256[] memory basePrice
    ) external whenNotPaused {
        uint256 len = itemId.length;
        require(acceptedTokens[token], "Invalid payment token");
        for (uint8 i = 0; i < len; i++) {
            _addOrder(
                itemContract,
                token,
                itemId[i],
                amount[i],
                basePrice[i],
                0,
                OrderType.FixedPrice,
                ContractType.erc1155
            );
        }
    }

    /** @notice Lists user auction item on the marketplace.
     *
     * Requirements:
     * - `basePrice` can't be zero.
     * - `bidStep` can't be zero.
     *
     * @param itemId Item ID.
     * @param basePrice Price of the item.
     * @param bidStep Bid step.
     */
    function listAuction1155(
        address itemContract,
        address token,
        uint256[] memory itemId,
        uint256[] memory amount,
        uint256[] memory basePrice,
        uint256[] memory bidStep
    ) external whenNotPaused {
        uint256 len = itemId.length;
        require(acceptedTokens[token], "Invalid payment token");
        for (uint8 i = 0; i < len; i++) {
            _addOrder(
                itemContract,
                token,
                itemId[i],
                amount[i],
                basePrice[i],
                bidStep[i],
                OrderType.Auction,
                ContractType.erc1155
            );
        }
    }

    /** @notice Allows user to buy an item from an order with a fixed price.
     * @param orderId Order IDs.
     */
    function buyOrder(uint256 orderId) external payable whenNotPaused {
        Order memory order = orders[orderId];

        if (order.token == address(0)) {
            require(msg.value >= order.basePrice, "Not enough ETH sent");
        }
        require(
            order.basePrice > 0 && order.endTime == 0,
            "Order cancelled or not exist"
        );
        require(
            order.orderType == OrderType.FixedPrice,
            "Can't buy auction order"
        );
        require(msg.sender != order.maker, "Can't buy from yourself");

        // Transfer NFT to `msg.sender` and  to order maker
        _exchange(
            orderId,
            order.itemContract,
            order.itemId,
            order.basePrice,
            msg.sender,
            order.maker,
            msg.sender
        );

        _cancelOrder(orderId, true);
    }

    /** @notice Allows user to bid on an auction.
     *
     * Requirements:
     * - `bidAmount` must be higher than the last bid + bid step.
     *
     * @param orderId Order ID.
     * @param bidAmount Amount in  tokens.
     */
    function makeBid(uint256 orderId, uint256 bidAmount)
        external
        payable
        whenNotPaused
    {
        Order storage order = orders[orderId];
        require(order.expiresAt > block.timestamp, "Bidding time is over");
        require(msg.sender != order.maker, "Can't bid on your own order");

        uint256 numBids = order.numBids;

        Bid storage lastBid = bids[orderId][numBids];

        if (order.token == address(0)) {
            payable(lastBid.bidder).transfer(lastBid.amount);
            bidAmount = msg.value + lastBid.amount;
        } else {
            _transferTokens(
                order.token,
                msg.sender,
                address(this),
                lastBid.bidder == msg.sender
                    ? (bidAmount - lastBid.amount)
                    : bidAmount
            );
            if (numBids > 0 && lastBid.bidder != msg.sender) {
                _transferTokens(
                    order.token,
                    address(0),
                    lastBid.bidder,
                    lastBid.amount
                );
            }
        }

        require(
            bidAmount >= (order.basePrice + order.bidStep) &&
                bidAmount >= (lastBid.amount + order.bidStep),
            "Bid must be more than highest + bid step"
        );

        order.numBids++;
        bids[orderId][order.numBids] = Bid({
            amount: bidAmount,
            bidder: msg.sender
        });

        emit NewHighestBid(orderId, msg.sender, bidAmount);
    }

    /** @notice Allows user to cancel an order with a fixed price.
     *
     * Requirements:
     * - `msg.sender` must be the creator of the order.
     *
     * @param orderId Order ID.
     */
    function cancelOrder(uint256[] memory orderId) external whenNotPaused {
        uint256 len = orderId.length;
        for (uint8 i = 0; i < len; i++) {
            Order memory order = orders[orderId[i]];
            require(msg.sender == order.maker, "Not the order creator");
            require(
                order.orderType == OrderType.FixedPrice,
                "Can't cancel an auction order"
            );

            _cancelOrder(orderId[i], false);
        }
    }

    /** @notice Allows user to finish the auction.
     *
     * Requirements:
     * - `order.expiresAt` must be greater than the current timestamp (`block.timestamp`).
     *
     * @param orderId Order ID.
     */
    function finishAuction(uint256[] memory orderId) external whenNotPaused {
        uint256 len = orderId.length;
        for (uint8 i = 0; i < len; i++) {
            Order storage order = orders[orderId[i]];
            require(order.endTime == 0, "No such order");
            require(
                order.orderType == OrderType.Auction,
                "Not an auction order"
            );
            // require(
            //     order.expiresAt <= block.timestamp,
            //     "Can't finish before bidding time"
            // );

            uint256 numBids = order.numBids;
            Bid storage lastBid = bids[orderId[i]][numBids];
            if (numBids > 2) {
                _exchange(
                    orderId[i],
                    order.itemContract,
                    order.itemId,
                    lastBid.amount,
                    address(0),
                    order.maker,
                    lastBid.bidder
                );
                _cancelOrder(orderId[i], true);
            } else {
                // Return  to the last bidder
                if (numBids > 0) {
                    if (order.token == address(0)) {
                        payable(lastBid.bidder).transfer(lastBid.amount);
                    } else {
                        _transferTokens(
                            order.token,
                            address(0),
                            lastBid.bidder,
                            lastBid.amount
                        );
                    }
                }

                _cancelOrder(orderId[i], false);
            }

            emit AuctionFinished(orderId[i], numBids);
        }
    }

    /** @notice Adds new order to the marketplace.
     *
     * Emits a {PlacedOrder} event.
     *
     * @param itemContract Item contract address.
     * @param itemId Item ID.
     * @param basePrice Price of the item.
     * @param bidStep Bid step.
     * @param orderType Order type (see `OrderType` enum).
     */
    function _addOrder(
        address itemContract,
        address token,
        uint256 itemId,
        uint256 amount,
        uint256 basePrice,
        uint256 bidStep,
        OrderType orderType,
        ContractType contractType
    ) private {
        _numOrders.increment();
        uint256 numOrders = _numOrders.current();

        Order storage order = orders[numOrders];
        order.itemContract = itemContract;
        order.itemId = itemId;
        order.itemAmount = amount;
        order.basePrice = basePrice;
        order.listedAt = block.timestamp;
        order.maker = msg.sender;
        order.orderType = orderType;
        order.token = token;
        order.contractType = contractType;

        if (orderType == OrderType.Auction) {
            order.expiresAt = block.timestamp + biddingTime;
            order.bidStep = bidStep;
        }

        if (contractType == ContractType.erc721) {
            require(
                IERC721(itemContract).ownerOf(itemId) == order.maker,
                "ERC721 token does not belong to the author."
            );
        } else {
            require(
                IERC1155(itemContract).balanceOf(order.maker, itemId) >= amount,
                "ERC1155 token balance is not sufficient for the seller.."
            );
        }

        emit PlacedOrder(
            numOrders,
            itemContract,
            token,
            itemId,
            msg.sender,
            basePrice
        );
    }

    /** @notice Exchanges tokens and Items between users.
     * @dev `payer` here is either `itemRecipient` or `address(0)`
     * which means that we should transfer from the contract.
     *
     * @param orderId Order ID.
     * @param itemContract Item contract address.
     * @param itemId Item ID.
     * @param price Item price in tokens.
     * @param payer Address of the payer.
     * @param itemOwner Address of the item owner.
     * @param itemRecipient Address of the item recipient.
     */
    function _exchange(
        uint256 orderId,
        address itemContract,
        uint256 itemId,
        uint256 price,
        address payer,
        address itemOwner,
        address itemRecipient
    ) private {
        if (orders[orderId].token == address(0)) {
            payable(itemOwner).transfer(price);
        } else {
            _transferTokens(orders[orderId].token, payer, itemOwner, price);
        }

        if (orders[orderId].contractType == ContractType.erc721) {
            require(
                IERC721(itemContract).getApproved(itemId) == address(this),
                "Asset not owned by this listing. Probably was already sold."
            );
            IERC721(itemContract).safeTransferFrom(
                orders[orderId].maker,
                itemRecipient,
                itemId
            );
        } else {
            require(
                IERC1155(itemContract).isApprovedForAll(
                    orders[orderId].maker,
                    address(this)
                ),
                "Asset not owned by this listing. Probably was already sold."
            );
            IERC1155(itemContract).safeTransferFrom(
                orders[orderId].maker,
                itemRecipient,
                itemId,
                orders[orderId].itemAmount,
                ""
            );
        }

        emit Purchase(
            orderId,
            itemContract,
            itemId,
            itemOwner,
            itemRecipient,
            price
        );
    }

    /** @notice Transfers tokens between users.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param amount Transfer amount in tokens.
     */
    function _transferTokens(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        from != address(0)
            ? IERC20(token).safeTransferFrom(from, to, amount)
            : IERC20(token).safeTransfer(to, amount);
    }

    /** @notice Cancelling order by id.
     * @param orderId Order ID.
     * @param isSold Indicates wheter order was purchased or simply cancelled by the owner.
     */
    function _cancelOrder(uint256 orderId, bool isSold) private {
        Order storage order = orders[orderId];
        order.endTime = block.timestamp;
        emit CancelledOrder(orderId, isSold);
    }

    /** @notice Checks if item is currently listed on the marketplace.
     * @param itemContract Item contract address.
     * @param itemId Item ID.
     * @return orderId Whether the item in an open order.
     */
    function isListed(address itemContract, uint256 itemId)
        external
        view
        returns (uint256 orderId)
    {
        uint256 numOrders = _numOrders.current();
        for (uint256 i = 1; i <= numOrders; i++) {
            if (
                orders[i].endTime == 0 &&
                orders[i].itemId == itemId &&
                orders[i].itemContract == itemContract
            ) return i;
        }
        return 0;
    }

    /** @notice Returns the entire order history on the market.
     * @return Array of `Order` structs.
     */
    function getOrdersHistory() external view returns (Order[] memory) {
        uint256 numOrders = _numOrders.current();
        Order[] memory ordersArr = new Order[](numOrders);

        for (uint256 i = 1; i <= numOrders; i++) {
            ordersArr[i - 1] = orders[i];
        }
        return ordersArr;
    }

    /** @notice Returns current open orders on the market.
     * @return Array of `Order` structs.
     */
    function getOpenOrders() external view returns (Order[] memory) {
        Order[] memory openOrders = new Order[](countOpenOrders());

        uint256 counter;
        uint256 numOrders = _numOrders.current();
        for (uint256 i = 1; i <= numOrders; i++) {
            if (orders[i].endTime == 0) {
                openOrders[counter] = orders[i];
                counter++;
            }
        }
        return openOrders;
    }

    /** @notice Counts currently open orders.
     * @return numOpenOrders Number of open orders.
     */
    function countOpenOrders() public view returns (uint256 numOpenOrders) {
        uint256 numOrders = _numOrders.current();
        for (uint256 i = 1; i <= numOrders; i++) {
            if (orders[i].endTime == 0) {
                numOpenOrders++;
            }
        }
    }

    /** @notice Returns all marketplace bids sorted by orders.
     * @return Array of arrays (`Bid` structs array by each order).
     */
    function getBidsHistory() external view returns (Bid[][] memory) {
        uint256 numOrders = _numOrders.current();
        Bid[][] memory bidsHistory = new Bid[][](numOrders);

        for (uint256 i = 1; i <= numOrders; i++) {
            bidsHistory[i - 1] = getBidsByOrder(i);
        }

        return bidsHistory;
    }

    /** @notice Returns all bids by order id.
     * @param orderId Order ID.
     * @return Array of `Bid` structs.
     */
    function getBidsByOrder(uint256 orderId)
        public
        view
        returns (Bid[] memory)
    {
        uint256 numBids = orders[orderId].numBids;
        Bid[] memory orderBids = new Bid[](numBids);

        for (uint256 i = 1; i <= numBids; i++) {
            orderBids[i - 1] = bids[orderId][i];
        }

        return orderBids;
    }

    /** Always returns `IERC721Receiver.onERC721Received.selector`. */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155Receiver)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
