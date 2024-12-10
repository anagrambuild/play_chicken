// SPDX-License-Identifier: GNU-AGPL-3.0-or-later
pragma solidity ^0.8.20;

// solhint-disable no-console

import {Script, console} from "forge-std/Script.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {RewardChicken} from "../contracts/RewardChicken.sol";

contract RewardChickenDeployScript is Script {
    event RewardChickenDeployed(address rewardChickenProxy, address rewardChicken);
    event RewardChickenUpgraded(address rewardChickenProxy, address rewardChicken);

    function deployTransparentProxy() public {
        address admin = vm.envAddress("CHICKEN_POOL_ADMIN");
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");
        address deploymentAdmin = msg.sender;
        bytes memory initializationData = abi.encodeWithSelector(RewardChicken.initialize.selector, deploymentAdmin);
        vm.startBroadcast();
        address implementation = address(new RewardChicken());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, admin, initializationData);
        address proxyAddress = address(proxy);

        console.log("TransparentUpgradeableProxy deployed at: ", proxyAddress);
        emit RewardChickenDeployed(proxyAddress, implementation);
        RewardChicken rewardChicken = RewardChicken(proxyAddress);
        if (admin != deploymentAdmin) {
            rewardChicken.grantRole(rewardChicken.DEFAULT_ADMIN_ROLE(), admin);
            rewardChicken.revokeRole(rewardChicken.DEFAULT_ADMIN_ROLE(), deploymentAdmin);
            console.log("Pool admin role is ", admin);
            console.log("Deployment role has been renounced ", deploymentAdmin);
        } else {
            console.log("Pool admin role is ", admin);
        }
        rewardChicken.grantRole(rewardChicken.PAUSER_ROLE(), admin);
        rewardChicken.grantRole(rewardChicken.PROTOCOL_ROLE(), protocolAdmin);
        console.log("Protocol admin role is ", protocolAdmin);
        vm.stopBroadcast();
    }

    function upgradeTransparentProxy() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAddress = vm.envAddress("PLAY_CHICKEN_PROXY");
        vm.startBroadcast();
        address implementation = address(new RewardChicken());
        ITransparentUpgradeableProxy poolProxy = ITransparentUpgradeableProxy(proxyAddress);
        ProxyAdmin(proxyAdmin).upgradeAndCall(poolProxy, implementation, "");
        console.log("TransparentUpgradeableProxy upgraded to: ", implementation);
        emit RewardChickenUpgraded(proxyAddress, implementation);
        vm.stopBroadcast();
    }
}
