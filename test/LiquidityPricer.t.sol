// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {PriceTable} from "../contracts/PriceTable.sol";
import {LiquidityPricer} from "../contracts/LiquidityPricer.sol";

contract TestLiquidityPricer is Test {
    uint256 public constant PRICE_MAX = 20e18;

    LiquidityPricer public pricer;

    function setUp() public {
        pricer = new LiquidityPricer(PRICE_MAX);
    }

    function testQuoteBuyZeroRevert() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.NoPriceForZeroQty.selector));
        pricer.quoteBuy(0);
    }

    function testQuoteSellZeroRevert() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.NoPriceForZeroQty.selector));
        pricer.quoteSell(0);
    }

    function testQuoteBuy() public view {
        assertGe(pricer.quoteBuy(100), 0);
        assertGe(pricer.quoteBuy(1), 0);
    }

    function testQuoteSellRevertInsufficient() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.InsufficientQuantityToSell.selector));
        pricer.quoteSell(100);
    }

    function testCommitBuy(uint256 buyQty) public {
        vm.assume(buyQty > 0 && buyQty <= PriceTable.V_MAX);
        pricer.commitBuy(buyQty);
        assertEq(pricer.totalBuyVolume(), buyQty);
    }

    function testCommitBuyMaxVolume() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.ExceedsMaxVolume.selector));
        pricer.commitBuy(PriceTable.V_MAX + 1);
    }

    function testBuyPriceAtMaxIsMax() public view {
        assertEq(pricer.quoteBuy(PriceTable.V_MAX), PRICE_MAX);
    }

    function testSellingOutIsNotZeroPriced(uint256 sellQty) public {
        vm.assume(sellQty > 0 && sellQty < 256);
        pricer.commitBuy(256);
        uint256 price = pricer.quoteSell(sellQty);
        assertTrue(price > 0, "Price may never be zero");
    }

    function testCommitSell(uint256 qtyToBuy) public {
        vm.assume(qtyToBuy > 0 && qtyToBuy <= PriceTable.V_MAX);
        uint256 buyPrice = pricer.quoteBuy(qtyToBuy);
        pricer.commitBuy(qtyToBuy);
        uint256 sellPrice = pricer.quoteSell(qtyToBuy);
        pricer.commitSell(qtyToBuy);
        assertEq(pricer.totalBuyVolume(), qtyToBuy);
        assertEq(pricer.totalSellVolume(), qtyToBuy);
        assertLt(sellPrice, buyPrice, "Selling price must be lower than buying price");
    }

    function testCommitSellRevertInsufficient() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.InsufficientQuantityToSell.selector));
        pricer.commitSell(100);
    }
}
