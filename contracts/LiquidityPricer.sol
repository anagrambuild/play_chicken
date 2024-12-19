// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PriceTable} from "./PriceTable.sol";

// LiqudityPricer is a contract that calculates the price of a buy or sell operation
contract LiquidityPricer {
    using PriceTable for uint256;

    uint256 public constant EDGE = PriceTable.V_STEP;

    error ExceedsMaxVolume();
    error InsufficientQuantityToSell();
    error NoPriceForZeroQty();
    error QuotedPriceIsZero();

    event BuyCommit(uint256 qty);
    event SellCommit(uint256 qty);

    uint256 public totalBuyVolume;
    uint256 public totalSellVolume;
    uint256 public maxPrice;

    constructor(uint256 _maxPrice) {
        totalBuyVolume = 0;
        totalSellVolume = 0;
        maxPrice = _maxPrice;
    }

    /**
     * @dev Quotes the current price based on the total volume.
     * @return quotedPrice The price after the operation, scaled by 1e18.
     */
    function quoteBuy(uint256 _qty) external view returns (uint256 quotedPrice) {
        return quote(true, _qty);
    }

    /**
     * @dev Quotes the current price based on the total volume.
     * @return quotedPrice The price after the operation, scaled by 1e18.
     */
    function quoteSell(uint256 _qty) external view returns (uint256 quotedPrice) {
        return quote(false, _qty);
    }

    /**
     * @dev Executes a buy operation, increasing the total volume.
     */
    function commitBuy(uint256 _qty) external {
        uint256 newVolume = getNetVolume() + _qty;
        require(newVolume <= PriceTable.V_MAX, ExceedsMaxVolume());
        totalBuyVolume += _qty;
        emit BuyCommit(_qty);
    }

    /**
     * @dev Executes a sell operation, decreasing the total volume.
     */
    function commitSell(uint256 _qty) external {
        uint256 newVolume = getNetVolume();
        require(newVolume >= _qty, InsufficientQuantityToSell());
        totalSellVolume += _qty;
        emit SellCommit(_qty);
    }

    function quote(bool _isBuy, uint256 _qty) internal view returns (uint256 quotedPrice) {
        require(_qty > 0, NoPriceForZeroQty()); // Handle zero quantity

        uint256 netVolumeBuys = getNetVolume(); // Current total volume from your system

        if (_isBuy) {
            uint256 newVolume = netVolumeBuys + _qty; // New volume after the buy
            require(newVolume <= PriceTable.V_MAX, ExceedsMaxVolume()); // Ensure volume is within bounds

            // Apply edge adjustment
            newVolume = Math.min(newVolume + EDGE, PriceTable.V_MAX);
            quotedPrice = PriceTable.getPrice(newVolume);
        } else {
            require(netVolumeBuys >= _qty, InsufficientQuantityToSell()); // Ensure enough volume to sell

            // Apply edge adjustment and ensure no underflows
            uint256 newVolume = netVolumeBuys > _qty + EDGE ? netVolumeBuys - _qty - EDGE : Math.max(1, netVolumeBuys - _qty);
            quotedPrice = PriceTable.getPrice(newVolume);
        }

        // Scale quoted price based on maxPrice and ensure it's non-zero
        quotedPrice = (quotedPrice * maxPrice) / PriceTable.PRICE_MAX;

        // Ensure quotedPrice is within the allowed bounds
        require(quotedPrice > 0, QuotedPriceIsZero());
        return quotedPrice;
    }

    function getNetVolume() internal view returns (uint256) {
        return totalBuyVolume - totalSellVolume;
    }
}
