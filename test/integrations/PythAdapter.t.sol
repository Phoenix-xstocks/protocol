// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { PythAdapter } from "../../src/integrations/PythAdapter.sol";

contract MockPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }

    mapping(bytes32 => Price) public prices;
    uint256 public updateFee = 1;

    function setPrice(bytes32 id, int64 price_, uint64 conf_, int32 expo_, uint publishTime_) external {
        prices[id] = Price(price_, conf_, expo_, publishTime_);
    }

    function getPriceNoOlderThan(bytes32 id, uint) external view returns (Price memory) {
        Price memory p = prices[id];
        require(p.publishTime > 0, "no price");
        return p;
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory) {
        return prices[id];
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        // no-op for mock
    }

    function getUpdateFee(bytes[] calldata) external view returns (uint) {
        return updateFee;
    }
}

contract PythAdapterTest is Test {
    PythAdapter public adapter;
    MockPyth public mockPyth;
    address owner;

    bytes32 constant NVDA_FEED = 0xb1073854ed24cbc755dc527418f52b7d271f6cc967bbf8d8129112b18860a593;
    bytes32 constant TSLA_FEED = 0x16dad506d7db8da01c87581c87ca897a012a153557d4d578c3b9c9e1bc0632f1;
    address constant NVDAx = address(0xA);
    address constant TSLAx = address(0xB);

    function setUp() public {
        owner = address(this);
        mockPyth = new MockPyth();
        adapter = new PythAdapter(address(mockPyth), owner);

        adapter.setFeedId(NVDAx, NVDA_FEED);
        adapter.setFeedId(TSLAx, TSLA_FEED);

        // Set mock prices: NVDA $130, TSLA $280 (8 decimals, expo=-8)
        mockPyth.setPrice(NVDA_FEED, 13000000000, 100000, -8, block.timestamp);
        mockPyth.setPrice(TSLA_FEED, 28000000000, 200000, -8, block.timestamp);
    }

    function test_getLatestPrice_nvda() public view {
        (int192 price, uint32 ts) = adapter.getLatestPrice(NVDA_FEED);
        assertEq(price, 13000000000, "NVDA should be $130 in 8 decimals");
        assertEq(ts, uint32(block.timestamp));
    }

    function test_getLatestPrice_tsla() public view {
        (int192 price,) = adapter.getLatestPrice(TSLA_FEED);
        assertEq(price, 28000000000, "TSLA should be $280 in 8 decimals");
    }

    function test_getPriceByAsset() public view {
        (int192 price,) = adapter.getPriceByAsset(NVDAx);
        assertEq(price, 13000000000);
    }

    function test_getPriceByAsset_unconfigured_reverts() public {
        vm.expectRevert();
        adapter.getPriceByAsset(address(0xDEAD));
    }

    function test_setFeedId() public {
        bytes32 newFeed = keccak256("NEW");
        adapter.setFeedId(address(0xC), newFeed);
        assertEq(adapter.feedIds(address(0xC)), newFeed);
    }

    function test_setFeedIds_batch() public {
        address[] memory assets = new address[](2);
        assets[0] = address(0xD);
        assets[1] = address(0xE);
        bytes32[] memory feeds = new bytes32[](2);
        feeds[0] = keccak256("D");
        feeds[1] = keccak256("E");

        adapter.setFeedIds(assets, feeds);
        assertEq(adapter.feedIds(address(0xD)), feeds[0]);
        assertEq(adapter.feedIds(address(0xE)), feeds[1]);
    }

    function test_setFeedId_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        adapter.setFeedId(address(0xF), keccak256("F"));
    }

    function test_setMaxPriceAge() public {
        adapter.setMaxPriceAge(1 hours);
        assertEq(adapter.maxPriceAge(), 1 hours);
    }

    function test_price_normalization_expo_negative5() public {
        // Price with expo=-5 (5 decimals): NVDA = 13000000 (130.00000)
        // Should normalize to 8 decimals: 13000000 * 10^3 = 13000000000
        mockPyth.setPrice(NVDA_FEED, 13000000, 100, -5, block.timestamp);
        (int192 price,) = adapter.getLatestPrice(NVDA_FEED);
        assertEq(price, 13000000000, "should normalize -5 expo to 8 decimals");
    }

    function test_price_normalization_expo_negative10() public {
        // Price with expo=-10: NVDA = 1300000000000 (130.0000000000)
        // Should normalize: 1300000000000 / 10^2 = 13000000000
        mockPyth.setPrice(NVDA_FEED, 1300000000000, 100, -10, block.timestamp);
        (int192 price,) = adapter.getLatestPrice(NVDA_FEED);
        assertEq(price, 13000000000, "should normalize -10 expo to 8 decimals");
    }

    function test_updatePrices() public {
        bytes[] memory data = new bytes[](1);
        data[0] = hex"01";
        adapter.updatePrices{ value: 1 }(data);
    }

    function test_updatePrices_refunds_excess() public {
        bytes[] memory data = new bytes[](1);
        data[0] = hex"01";
        uint256 balBefore = address(this).balance;
        adapter.updatePrices{ value: 100 }(data);
        // Should refund 99 (fee is 1)
        assertEq(address(this).balance, balBefore - 1);
    }

    receive() external payable {}
}
