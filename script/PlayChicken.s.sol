// SPDX-License-Identifier: GNU-AGPL-3.0-or-later
pragma solidity ^0.8.20;

// solhint-disable no-console

import {Script, console} from "forge-std/Script.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PlayChicken} from "../contracts/PlayChicken.sol";

contract PlayChickenDeployScript is Script {
    event PlayChickenDeployed(address playChickenProxy, address playChicken);
    event PlayChickenUpgraded(address playChickenProxy, address playChicken);

    function deployTransparentProxy() public {
        address admin = vm.envAddress("CHICKEN_POOL_ADMIN");
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");
        address deploymentAdmin = msg.sender;
        bytes memory initializationData = abi.encodeWithSelector(PlayChicken.initialize.selector, deploymentAdmin);
        vm.startBroadcast();
        address implementation = address(new PlayChicken());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, admin, initializationData);
        address proxyAddress = address(proxy);

        console.log("TransparentUpgradeableProxy deployed at: ", proxyAddress);
        emit PlayChickenDeployed(proxyAddress, implementation);
        PlayChicken playChicken = PlayChicken(proxyAddress);
        if (admin != deploymentAdmin) {
            playChicken.grantRole(playChicken.DEFAULT_ADMIN_ROLE(), admin);
            playChicken.revokeRole(playChicken.DEFAULT_ADMIN_ROLE(), deploymentAdmin);
            console.log("Pool admin role is ", admin);
            console.log("Deployment role has been renounced ", deploymentAdmin);
        } else {
            console.log("Pool admin role is ", admin);
        }
        playChicken.grantRole(playChicken.PAUSER_ROLE(), admin);
        playChicken.grantRole(playChicken.PROTOCOL_ROLE(), protocolAdmin);
        console.log("Protocol admin role is ", protocolAdmin);
        vm.stopBroadcast();
    }

    function upgradeTransparentProxy() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAddress = vm.envAddress("PLAY_CHICKEN_PROXY");
        vm.startBroadcast();
        address implementation = address(new PlayChicken());
        ITransparentUpgradeableProxy poolProxy = ITransparentUpgradeableProxy(proxyAddress);
        ProxyAdmin(proxyAdmin).upgradeAndCall(poolProxy, implementation, "");
        console.log("TransparentUpgradeableProxy upgraded to: ", implementation);
        emit PlayChickenUpgraded(proxyAddress, implementation);
        vm.stopBroadcast();
    }
}
