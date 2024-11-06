// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PlayChicken} from "../contracts/PlayChicken.sol";

contract PlayChickenDeployScript is Script {
    PlayChicken public playChicken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        playChicken = new PlayChicken();

        vm.stopBroadcast();
    }
}
