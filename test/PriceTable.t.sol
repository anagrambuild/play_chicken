// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {PriceTable} from "../contracts/PriceTable.sol";

contract TestPriceTable is Test {
    // The expected prices array
    uint256[] public expectedPrices = [
        0,
        215443469003188352,
        271441761659490688,
        310723250595385856,
        341995189335339392,
        368403149864038656,
        391486764116886336,
        412128529980855680,
        430886938006376704,
        448140474655716480,
        464158883361277888,
        479141985706278400,
        493242414866093952,
        506579701910088576,
        519249410185110400,
        531329284591305472,
        542883523318981312,
        553965825675446400,
        564621617328617088,
        574889707894483072,
        584803547642573184,
        594392195276312960,
        603681073679768576,
        612692567522841728,
        621446501190771712,
        629960524947436544,
        638250429885990656,
        646330407009565184,
        654213262037718016,
        661910594802622976,
        669432950082169472,
        676789945210700672,
        683990378670678784,
        691042323001118464,
        697953204690888832,
        704729873206489088,
        711378660898012544,
        717905435206831872,
        724315644344174080,
        730614357406280320,
        736806299728077184,
        742895884144656512,
        748887238721850624,
        754784231428757376,
        760590492152278272,
        766309432393553024,
        771944262936164224,
        777498009734258688,
        782973528233772672,
        788373516310524288,
        793700525984099712,
        798956974045401344,
        804145151717811456,
        809267233456645632,
        814325284978471936,
        819321270600645760,
        824257059961711360,
        829134434184969728,
        833955091540260608,
        838720652652714240,
        843432665301749120,
        848092608848811264,
        852701898328159744,
        857261888231339520,
        861773876012753408,
        866239105340902784,
        870658769117361152,
        875034012283327360,
        879365934431635712,
        883655592240361216,
        887904001742600576,
        892112140445634688,
        896280949311432832,
        900411334609370112,
        904504169651027328,
        908560296416069888,
        912580527077393280,
        916565645433022336,
        920516408251588736,
        924433546537648128,
        928317766722555776,
        932169751786157568,
        935990162314115712,
        939779637495297408,
        943538796063306496,
        947268237185909504,
        950968541305814912,
        954640270936003968,
        958283971412556672,
        961900171607704576,
        965489384605629696,
        969052108343350144,
        972588826218855936,
        976100007668507520,
        979586108715561344,
        983047572491558528,
        986484829732187904,
        989898299249129344,
        993288388379268608,
        996655493412596224,
        999999999999999872
    ];

    function testPriceAtMaxVolume() public pure {
        uint256 actualPrice = PriceTable.getPrice(PriceTable.V_MAX);
        assertEq(actualPrice, 1e18, "Price mismatch at max volume");
    }

    function testGetPrice() public view {
        uint256 maxVol = PriceTable.V_MAX;
        for (uint256 v = 0; v < maxVol; v += PriceTable.V_STEP) {
            uint256 actualPrice = PriceTable.getPrice(v);
            uint256 stepIndex = v / PriceTable.V_STEP;
            assertTrue(
                stepIndex < expectedPrices.length, string(abi.encodePacked("Step index out of bounds ", uint2str(stepIndex)))
            );
            uint256 expectedPrice = expectedPrices[stepIndex];
            assertEq(
                actualPrice, expectedPrice, string(abi.encodePacked("Price mismatch at index ", uint2str(v / PriceTable.STEP)))
            );
        }
        assertEq(PriceTable.getPrice(PriceTable.V_MAX), PriceTable.PRICE_MAX, "Price mismatch at max volume");
    }

    function testGetPriceAtInterpolationPoint(uint256 v) public pure {
        vm.assume(v > 0 && v < PriceTable.V_MAX);
        uint256 actualPrice = PriceTable.getPrice(v);
        uint256 stepIndex = v / PriceTable.V_STEP;
        uint256 remainder = v % PriceTable.V_STEP;
        uint256 priceLower = PriceTable.loadPriceAtStep(PriceTable.PRICE_DATA, stepIndex);
        uint256 priceUpper = PriceTable.loadPriceAtStep(PriceTable.PRICE_DATA, stepIndex + 1);
        uint256 expectedPrice = priceLower + ((priceUpper - priceLower) * remainder) / PriceTable.V_STEP;
        assertEq(actualPrice, expectedPrice, "Price mismatch at interpolation point");
        assertGt(actualPrice, PriceTable.getPrice(v - 1), "Price should be greater than previous volume");
        //assertLt(actualPrice, PriceTable.getPrice(v + 1), "Price should be less than next volume");
    }

    function testPriceAt455() public pure {
        uint256 actualPrice = PriceTable.getPrice(455);
        assertEq(actualPrice, 9802677839645070, "Price mismatch at 455");
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            bstr[--k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }
}
