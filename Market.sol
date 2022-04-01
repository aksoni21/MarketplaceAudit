//SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarket is ERC721URIStorage, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;
    bool public isActive = true;

    // Market variables
    address payable marketcontractowner;
    address payable contractwallet;
    uint256 listingPrice = 0.025 ether;
    uint256 marketEnablement = 500; //in %
    uint256 maxBlocks = 1054080; //about 6 months;

    mapping(uint256 => MarketItem) private idToMarketItem;

    // address payable public highestBidder;
    mapping(uint256 => mapping(address => uint256)) private bids2lvl;

    struct MarketItem {
        uint256 tokenId;
        address payable creator;
        address payable seller;
        address payable currentowner;
        uint256 buynowprice;
        bool sold;
        uint256 creatorRoyalty;
        uint256 startDate;
        bool inauction;
        uint256 highestBindingBid;
        address highestBidder;
    }

    event MarketItemCreated(
        uint256 indexed tokenId,
        address creator,
        address seller,
        address currentowner,
        uint256 buynowprice,
        bool sold,
        uint256 creatorRoyalty,
        uint256 startDate,
        bool inauction,
        uint256 highestBindingBid,
        address highestBidder
    );

    constructor() ERC721("Encanto Tokens", "ENCA") {
        marketcontractowner = payable(msg.sender);
        contractwallet = payable(msg.sender);
    }

    /* Mints a token and lists it in the marketplace */
    function createToken(
        string memory tokenURI,
        uint256 buyprice,
        uint256 royalty,
        uint256 aucprice,
        bool startauc
    ) public payable contIsActive returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        createMarketItem(newTokenId, buyprice, royalty, aucprice, startauc);
        return newTokenId;
    }

    /* Places an item for sale on the marketplace */
    function createMarketItem(
        uint256 tokenId,
        uint256 buynowprice,
        uint256 royalty,
        uint256 auctionstartprice,
        bool startauction
    ) private {
        require(
            buynowprice > 10000,
            "Buy Now Price must be at least 10000 wei"
        );
        require(
            auctionstartprice > 10000,
            "Auction Price must be at least 10000 wei"
        );
        require(
            msg.value == listingPrice,
            "Price must be equal to listing price"
        );

        uint256 startdate = block.timestamp;

        idToMarketItem[tokenId] = MarketItem(
            tokenId,
            payable(msg.sender), //this should be the creator address for royalties,
            payable(msg.sender), //this should be the seller address,
            payable(address(this)), //this should be the current owner,
            buynowprice,
            false,
            royalty,
            startdate,
            startauction,
            auctionstartprice,
            msg.sender
        );
        _transfer(msg.sender, address(this), tokenId);
        // IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        emit MarketItemCreated(
            tokenId,
            msg.sender,
            msg.sender,
            address(this),
            buynowprice,
            false,
            royalty,
            startdate,
            startauction,
            auctionstartprice,
            msg.sender
        );
    }

    /* Relists the NFT for resell on the marketplace */
    function resellitem(
        uint256 tokenId,
        uint256 buynowprice,
        uint256 auctionstartprice,
        bool startauction
    ) public payable nonReentrant {
        require(
            idToMarketItem[tokenId].currentowner == msg.sender,
            "Only item owner can perform this operation"
        );
        require(buynowprice > 1, "Buy Now Price must be at least 1 wei");
        require(auctionstartprice > 1, "Auction Price must be at least 1 wei");
        require(
            msg.value == listingPrice,
            "Price must be equal to listing price"
        );

        idToMarketItem[tokenId].sold = false;
        idToMarketItem[tokenId].buynowprice = buynowprice;
        idToMarketItem[tokenId].seller = payable(msg.sender);
        idToMarketItem[tokenId].currentowner = payable(address(this));
        idToMarketItem[tokenId].inauction = startauction;
        idToMarketItem[tokenId].startDate = block.timestamp; //fix
        idToMarketItem[tokenId].highestBidder = address(0);
        idToMarketItem[tokenId].highestBindingBid = auctionstartprice;
        _itemsSold.decrement();

        _transfer(msg.sender, address(this), tokenId);
    }

    /* Creates the sale of a marketplace item */
    /* Transfers ownership of the item, as well as funds between parties */
    function createMarketSale(uint256 tokenId)
        public
        payable
        notNFTOwner(tokenId)
        nonReentrant
        contIsActive
    {
        require(
            idToMarketItem[tokenId].inauction == false,
            "This NFT is in an Auction. Please place a bid instead"
        );
        uint256 saleprice = idToMarketItem[tokenId].buynowprice;
        require(
            msg.value == saleprice,
            "Please submit the asking price in order to complete the purchase"
        );
        require(
            idToMarketItem[tokenId].creator != address(0),
            "This is a cancelled item, not for purchase"
        );

        address seller = idToMarketItem[tokenId].seller;
        address creator = idToMarketItem[tokenId].creator;
        idToMarketItem[tokenId].seller = payable(address(0)); //prevents reentrancy
        idToMarketItem[tokenId].creator = payable(address(0)); //prevents reentrancy
        idToMarketItem[tokenId].sold = true;
        idToMarketItem[tokenId].inauction = false;
        idToMarketItem[tokenId].highestBidder = address(0);
        _itemsSold.increment();

        // payable(marketcontractowner).transfer(listingPrice);
        // payable(seller).transfer(msg.value);

        uint256 creatorvalue = (saleprice *
            idToMarketItem[tokenId].creatorRoyalty) / 10000;

        uint256 sellervalue = saleprice - creatorvalue - marketEnablement;
        if (
            idToMarketItem[tokenId].seller ==
            idToMarketItem[tokenId].creator
        ) {
            payable(seller).transfer(sellervalue + creatorvalue);
        } else {
            payable(seller).transfer(sellervalue);
            payable(creator).transfer(creatorvalue);
        }
        payable(marketcontractowner).transfer(listingPrice + marketEnablement);
        idToMarketItem[tokenId].currentowner = payable(msg.sender);
        _transfer(address(this), msg.sender, tokenId);
        idToMarketItem[tokenId].creator = payable(creator);
    }

    function finalizeAuction(uint256 tokenId)
        public
        payable
        onlyNFTOwnerOrIfExpired(tokenId)
        nonReentrant
        contIsActive
    {
        require(
            idToMarketItem[tokenId].inauction == false,
            "This NFT is in an Auction. Please place a bid instead"
        );
        require(
            idToMarketItem[tokenId].creator != address(0),
            "This is a cancelled item, not for purchase"
        );

        uint256 saleprice = idToMarketItem[tokenId].highestBindingBid;
        address highestbidder = idToMarketItem[tokenId].highestBidder;

        require(highestbidder != address(0), "This NFT does not have a bidder");
        require(
            msg.value == saleprice,
            "Please submit the asking price in order to complete the purchase"
        );

        address seller = idToMarketItem[tokenId].seller;
        address creator = idToMarketItem[tokenId].creator;
        idToMarketItem[tokenId].highestBidder = address(0); //prevents reentrancy
        idToMarketItem[tokenId].seller = payable(address(0)); //prevents reentrancy
        idToMarketItem[tokenId].creator = payable(address(0)); //prevents reentrancy
        idToMarketItem[tokenId].sold = true;
        idToMarketItem[tokenId].inauction = false;
        _itemsSold.increment();

        uint256 creatorvalue = (saleprice *
            idToMarketItem[tokenId].creatorRoyalty) / 10000;

        uint256 sellervalue = saleprice - creatorvalue - marketEnablement;
        if (
            idToMarketItem[tokenId].seller ==
            idToMarketItem[tokenId].creator
        ) {
            payable(seller).transfer(sellervalue + creatorvalue);
        } else {
            payable(seller).transfer(sellervalue);
            payable(creator).transfer(creatorvalue);
        }

        payable(marketcontractowner).transfer(listingPrice + marketEnablement);
        idToMarketItem[tokenId].currentowner = payable(highestbidder);
        _transfer(address(this), msg.sender, tokenId);
        idToMarketItem[tokenId].creator = payable(creator);

    }

    function turnOffAuction(uint256 tokenId)
        public
        onlyNFTOwnerOrIfExpired(tokenId)
    {
        idToMarketItem[tokenId].inauction = false;
    }

    function cancelitem(uint256[] memory ids)
        public
        onlyNFTOwnerforCancel(ids)
        nonReentrant
    {
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 thisid = ids[i];
            //only nft owner can cancel them

            if (idToMarketItem[thisid].currentowner == msg.sender) {
                idToMarketItem[thisid].creator = payable(address(0));
                // uint256 id = idToMarketItem[thisid].tokenId;
                // IERC721(nftContract).transferFrom(msg.sender, address(0), id);
            } else if (
                idToMarketItem[thisid].creator == msg.sender &&
                idToMarketItem[thisid].currentowner == address(0)
            ) {
                idToMarketItem[thisid].creator = payable(address(0));
                // uint256 id = idToMarketItem[thisid].tokenId;
                // IERC721(nftContract).transferFrom(msg.sender, address(0), id);
            }
        }
    }

    /*Auction functions */
    function placeBid(uint256 thisitemId)
        public
        payable
        notNFTOwner(thisitemId)
        notMarketContractOwner(thisitemId)
        nonReentrant
        contIsActive
    {
        require(msg.value >= 100, "Bid must be at least a 100 wei");

        // bids2lvl[itemIda][msg.sender] = bids2lvl[itemIda][msg.sender] + 1;
        uint256 currentBid = bids2lvl[thisitemId][msg.sender] + msg.value;
        require(currentBid > idToMarketItem[thisitemId].highestBindingBid);

        bids2lvl[thisitemId][msg.sender] = currentBid;
        idToMarketItem[thisitemId].highestBindingBid = currentBid;
        idToMarketItem[thisitemId].highestBidder = payable(msg.sender);
    }

    function returnBid(uint256 thisitemId) public nonReentrant {
        require(
            msg.sender != idToMarketItem[thisitemId].highestBidder,
            "Highest bidder cannot withdraw their bid"
        );
        require(bids2lvl[thisitemId][msg.sender] > 0);

        address payable recipient = payable(msg.sender);
        uint256 value = bids2lvl[thisitemId][msg.sender];

        //resetting the bid of the recipient to prevent reentrancy along with
        bids2lvl[thisitemId][recipient] = 0;

        //send the value to the rightful recipient
        recipient.transfer(value);
    }

    function AuctionsCleanUp() external onlyMarketOwner nonReentrant returns (bool) {
        uint256 itemCount = _tokenIds.current();

        for (uint256 i = 0; i < itemCount; i++) {
            if (
                (idToMarketItem[i + 1].startDate - block.timestamp) > maxBlocks
            ) {
                idToMarketItem[i + 1].inauction = false;
            }
        }
        return true;
    }

    /*Fetch Functions */
    /* Returns all unsold market items */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _tokenIds.current();
        uint256 unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idToMarketItem[i + 1].currentowner == address(this)) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items that a user has purchased */
    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].currentowner == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].currentowner == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items a user has created */
    function fetchItemsCreated() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only the item a user has selected */
    function fetchIndividualItem(uint256 thisItemId)
        public
        view
        returns (MarketItem[] memory)
    {
        MarketItem storage clickeditem = idToMarketItem[thisItemId];

        MarketItem[] memory items = new MarketItem[](1);
        items[0] = clickeditem;

        return items;
    }

    /* Returns only the item a user has selected */
    function fetchIndividualCreatorItems(uint256 thisItemId)
        public
        view
        returns (MarketItem[] memory)
    {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        MarketItem storage clickeditem = idToMarketItem[thisItemId];
        address clickedItemCreator = clickeditem.seller;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                idToMarketItem[i + 1].seller == clickedItemCreator &&
                idToMarketItem[i + 1].tokenId != thisItemId
            ) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                idToMarketItem[i + 1].seller == clickedItemCreator &&
                idToMarketItem[i + 1].tokenId != thisItemId
            ) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns Cancelleditems*/
    function fetchcancelleditems()
        public
        view
        onlyMarketOwner
        returns (MarketItem[] memory)
    {
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](5);
        for (uint256 i = 0; i < 5; i++) {
            if (idToMarketItem[i + 1].creator == address(0)) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a <= b) {
            return a;
        } else {
            return b;
        }
    }

    /* Get functions */
    /* Returns the highest bid for an Item */
    function gethighestBindingBid(uint256 thisItemId)
        public
        view
        returns (uint256)
    {
        return idToMarketItem[thisItemId].highestBindingBid;
    }

    /* Returns the highest bidder for an Item */
    function gethighestBidder(uint256 thisItemId)
        public
        view
        returns (address)
    {
        return idToMarketItem[thisItemId].highestBidder;
    }

    /* Places an item for sale on the marketplace */
    function getitemcount() public view returns (uint256) {
        uint256 itemCount = _tokenIds.current();
        return itemCount;
    }

    function getunsoldcount() public view returns (uint256) {
        uint256 unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        return unsoldItemCount;
    }

    function getbids(uint256 itemitemId) public view returns (uint256) {
        uint256 thisbid = bids2lvl[itemitemId][msg.sender];
        return thisbid;
    }

    function getRoyaltyAmount(uint256 thisitemId)
        public
        view
        returns (uint256)
    {
        uint256 thisRoyalty = idToMarketItem[thisitemId].creatorRoyalty;
        return thisRoyalty;
    }

    /*NFT Owner modifier and Not NFT Owner modifier */
    modifier onlyNFTOwnerforCancel(uint256[] memory ids) {
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 thisid = ids[i];
            require(
                msg.sender == idToMarketItem[thisid].seller,
                "NFT owner perform this action"
            );
        }
        _;
    }
    modifier onlyNFTOwnerOrIfExpired(uint256 id) {
        // creator or current owner will be able to call this at anytime.
        // market owner will only be able to call this if the item is expired
        if (msg.sender == idToMarketItem[id].seller) {
            require(
                msg.sender == idToMarketItem[id].seller,
                "Only NFT creator can perform this action"
            );
        } else if ((block.number - idToMarketItem[id].startDate) > maxBlocks) {
            require(msg.sender == marketcontractowner);
        }
        _;
    }
    modifier notNFTOwner(uint256 thisId) {
        require(
            msg.sender != idToMarketItem[thisId].seller,
            "NFT creator cannot perform this action"
        );
        _;
    }

    modifier notMarketContractOwner(uint256 thisId) {
        require(
            msg.sender != marketcontractowner,
            "Market owner cannot perform this action"
        );
        _;
    }

    modifier contIsActive() {
        require(isActive == true);
        _;
    }

    /*MarketOwner functions */
    modifier onlyMarketOwner() {
        require(msg.sender == marketcontractowner);
        _;
    }

    function toggleCircuitBreaker() external onlyMarketOwner {
        isActive = !isActive;
    }

    function testmaxblocks(uint256 thisId) public view returns (uint256) {
        return idToMarketItem[thisId].startDate;
    }

    function testmaxblocksconditional(uint256 thisId)
        public
        view
        returns (bool)
    {
        uint256 t = idToMarketItem[thisId].startDate;
        return (block.timestamp >= (t + 2 minutes));
    }

    /* Returns the listing price of the contract */
    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }

    /* Sets the listing price of the contract */
    function setListingPrice(uint256 _newprice) external onlyMarketOwner {
        listingPrice = _newprice;
    }

    /* Returns the market enablement price of the contract */
    function getMarketEnablement() public view returns (uint256) {
        return marketEnablement;
    }

    /* Returns the market enablement price of the contract */
    function setMarketEnablement(uint256 _newenabler) external onlyMarketOwner {
        marketEnablement = _newenabler;
    }

    /* Returns market contract owner */
    function getMarketContractOwner() public view returns (address) {
        return marketcontractowner;
    }

    /* Returns the market contract wallet address */
    function getMarketWallet() public view returns (address) {
        return contractwallet;
    }

    /* Returns the market contract wallet address  */
    function setMarketWallet(address _newwallet) external onlyMarketOwner {
        contractwallet = payable(_newwallet);
    }

    /* Withdraw */
    function withdraw() external onlyMarketOwner {
        require(address(this).balance > 0);
        payable(contractwallet).transfer(address(this).balance);
    }

    /* Returns the auction expiration block size */
    function getMaxBlocks() public view returns (uint256) {
        return maxBlocks;
    }

    /* Sets the auction expiration block size */
    function setMaxBlocks(uint256 _newlimit) external onlyMarketOwner {
        maxBlocks = _newlimit;
    }
}
