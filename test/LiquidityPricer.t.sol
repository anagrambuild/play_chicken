// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {PriceTable} from "../contracts/PriceTable.sol";
import {LiquidityPricer} from "../contracts/LiquidityPricer.sol";

contract TestLiquidityPricer is Test {
    uint256 public constant PRICE_MAX = 20e18;

    LiquidityPricer pricer;

    function setUp() public {
        pricer = new LiquidityPricer(PRICE_MAX);
    }

    function testQuoteBuyZeroRevert() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.ZeroQty.selector));
        pricer.quoteBuy(0);
    }

    function testQuoteSellZeroRevert() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.ZeroQty.selector));
        pricer.quoteSell(0);
    }

    function testQuoteBuy() public {
        assertGe(pricer.quoteBuy(100), 0);
        assertGe(pricer.quoteBuy(1), 0);
    }

    function testQuoteSellRevertInsufficient() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.InsufficientQuantityToSell.selector));
        pricer.quoteSell(100);
    }

    function testCommitBuy() public {
        pricer.commitBuy(100);
        assertEq(pricer.totalBuyVolume(), 100);
    }

    function testCommitBuyMaxVolume() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.MaxVolume.selector));
        pricer.commitBuy(PriceTable.V_MAX + 1);
    }

    function testBuyPriceAtMaxIsMax() public {
        assertEq(pricer.quoteBuy(PriceTable.V_MAX), PRICE_MAX);
    }

    function testCommitSell() public {
        uint256 buyPrice = pricer.quoteBuy(100);
        pricer.commitBuy(100);
        uint256 sellPrice = pricer.quoteSell(100);
        pricer.commitSell(100);
        assertEq(pricer.totalBuyVolume(), 100);
        assertEq(pricer.totalSellVolume(), 100);
        assertLt(sellPrice, buyPrice);
    }

    function testCommitSellRevertInsufficient() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidityPricer.InsufficientQuantityToSell.selector));
        pricer.commitSell(100);
    }
}
