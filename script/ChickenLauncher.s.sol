// SPDX-License-Identifier: GNU-AGPL-3.0-or-later
pragma solidity ^0.8.20;

// solhint-disable no-console

import {Script, console} from "forge-std/Script.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ChickenLauncher} from "../contracts/ChickenLauncher.sol";

contract ChickenLauncherDeployScript is Script {
    event ChickenLauncherDeployed(address chickenLauncherProxy, address chickenLauncher);
    event ChickenLauncherUpgraded(address chickenLauncherProxy, address chickenLauncher);

    function deployTransparentProxy() public {
        address admin = vm.envAddress("CHICKEN_POOL_ADMIN");
        address deploymentAdmin = msg.sender;
        bytes memory initializationData = abi.encodeWithSelector(ChickenLauncher.initialize.selector, deploymentAdmin);
        vm.startBroadcast();
        address implementation = address(new ChickenLauncher());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, admin, initializationData);
        address proxyAddress = address(proxy);
        console.log("TransparentUpgradeableProxy deployed at: ", proxyAddress);
        emit ChickenLauncherDeployed(proxyAddress, implementation);
        ChickenLauncher chickenLauncher = ChickenLauncher(proxyAddress);
        if (admin != deploymentAdmin) {
            chickenLauncher.grantRole(chickenLauncher.DEFAULT_ADMIN_ROLE(), admin);
            chickenLauncher.revokeRole(chickenLauncher.DEFAULT_ADMIN_ROLE(), deploymentAdmin);
            console.log("Pool admin role is ", admin);
            console.log("Deployment role has been renounced ", deploymentAdmin);
        } else {
            console.log("Pool admin role is ", admin);
        }
        chickenLauncher.grantRole(chickenLauncher.PAUSER_ROLE(), admin);
        console.log("Pauser role is ", admin);
        vm.stopBroadcast();
    }

    function upgradeTransparentProxy() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAddress = vm.envAddress("CHICKEN_LAUNCHER_PROXY");
        vm.startBroadcast();
        address implementation = address(new ChickenLauncher());
        ITransparentUpgradeableProxy poolProxy = ITransparentUpgradeableProxy(proxyAddress);
        ProxyAdmin(proxyAdmin).upgradeAndCall(poolProxy, implementation, "");
        console.log("TransparentUpgradeableProxy upgraded to: ", implementation);
        emit ChickenLauncherUpgraded(proxyAddress, implementation);
        vm.stopBroadcast();
    }
}
