// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import "./PriceTable.sol";

// LiqudityPricer is a contract that calculates the price of a buy or sell operation
contract LiquidityPricer {
    using PriceTable for uint256;

    uint256 public constant EDGE = PriceTable.V_STEP;

    error MaxVolume();
    error InsufficientQuantityToSell();
    error ZeroQty();

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
        uint256 newVolume = getTotalVolume() + _qty;
        require(newVolume < PriceTable.V_MAX, MaxVolume());
        totalBuyVolume += _qty;
        emit BuyCommit(_qty);
    }

    /**
     * @dev Executes a sell operation, decreasing the total volume.
     */
    function commitSell(uint256 _qty) external {
        uint256 newVolume = getTotalVolume();
        require(newVolume > _qty, InsufficientQuantityToSell());
        totalSellVolume += _qty;
        emit SellCommit(_qty);
    }

    function quote(bool _isBuy, uint256 _qty) internal view returns (uint256 quotedPrice) {
        require(_qty > 0, ZeroQty());
        uint256 totalVolume = getTotalVolume();
        if (_isBuy) {
            uint256 newVolume = totalVolume + _qty + EDGE;
            require(newVolume < PriceTable.V_MAX, MaxVolume());
            quotedPrice = PriceTable.getPrice(newVolume);
        } else {
            require(totalVolume > _qty + EDGE, InsufficientQuantityToSell());
            uint256 newVolume = totalVolume - _qty - EDGE;
            quotedPrice = PriceTable.getPrice(newVolume);
        }

        quotedPrice = quotedPrice * maxPrice / PriceTable.PRICE_MAX;
    }

    function getTotalVolume() internal view returns (uint256) {
        return totalBuyVolume - totalSellVolume;
    }
}
