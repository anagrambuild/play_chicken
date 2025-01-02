// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable var-name-mixedcase
// solhint-disable no-console

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Test, console} from "forge-std/Test.sol";

import {ChickenLauncher} from "../contracts/ChickenLauncher.sol";
import {TokenMath} from "../contracts/TokenMath.sol";

contract ChickenLauncherTest is Test {
    using TokenMath for uint256;

    address public CHICKEN_LAUNCHER;
    address public CHICKEN_ADMIN;
    ChickenLauncher public launcher;

    function setUp() public {
        CHICKEN_LAUNCHER = vm.addr(0x1);
        CHICKEN_ADMIN = vm.addr(0x2);
        mockChickenLauncher(CHICKEN_LAUNCHER);
        launcher = ChickenLauncher(CHICKEN_LAUNCHER);
    }

    function testInitialize() public view {
        assertTrue(launcher.hasRole(launcher.DEFAULT_ADMIN_ROLE(), CHICKEN_ADMIN));
        assertTrue(launcher.hasRole(launcher.PAUSER_ROLE(), CHICKEN_ADMIN));
        // caller is not pauser
        assertFalse(launcher.hasRole(launcher.PAUSER_ROLE(), address(this)));
        // caller is not admin
        assertFalse(launcher.hasRole(launcher.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function testPause() public {
        assertEq(launcher.paused(), false);
        vm.prank(CHICKEN_ADMIN);
        launcher.pause();
        assertEq(launcher.paused(), true);
    }

    function testPauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), launcher.PAUSER_ROLE()
            )
        );
        launcher.pause();
    }

    function testUnpause() public {
        vm.prank(CHICKEN_ADMIN);
        launcher.pause();
        assertEq(launcher.paused(), true);
        vm.prank(CHICKEN_ADMIN);
        launcher.unpause();
        assertEq(launcher.paused(), false);
    }

    function testUnpauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), launcher.PAUSER_ROLE()
            )
        );
        launcher.unpause();
    }

    function testLaunchRevertWhenPaused() public {
        vm.prank(CHICKEN_ADMIN);
        launcher.pause();
        assertEq(launcher.paused(), true);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        launcher.launch("Chicken", "CHICKEN", 1000, CHICKEN_ADMIN, 10000);
    }

    function testUpgradeOkayWhenPaused() public {
        vm.prank(CHICKEN_ADMIN);
        launcher.pause();
        assertEq(launcher.paused(), true);
        vm.expectEmit();
        emit ChickenLauncher.TokenUpgraded(0x2946259E0334f33A064106302415aD3391BeD384, 0xF2E246BB76DF876Cef8b38ae84130F4F55De395b);
        vm.prank(CHICKEN_ADMIN);
        launcher.upgradeToken();
    }

    function testUpgradeOnlyPermittedForAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), launcher.DEFAULT_ADMIN_ROLE()
            )
        );
        launcher.upgradeToken();
    }

    function testLaunchNewToken() public {
        vm.expectEmit();
        emit ChickenLauncher.TokenCreated(
            0x2946259E0334f33A064106302415aD3391BeD384,
            "Chicken",
            "CHICKEN",
            uint256(1000).tokens(),
            CHICKEN_ADMIN,
            uint256(10000).tokens()
        );
        address chicken = launcher.launch("Chicken", "CHICKEN", uint256(1000).tokens(), CHICKEN_ADMIN, uint256(10000).tokens());
        IERC20 chickenToken = IERC20(chicken);
        assertEq(chickenToken.totalSupply(), uint256(1000).tokens());
    }

    function mockChickenLauncher(address _launcher) internal {
        ChickenLauncher implementation = new ChickenLauncher();
        bytes memory code = address(implementation).code;
        vm.etch(_launcher, code);
        console.log("ChickenLauncher owner: ", CHICKEN_ADMIN);
        ChickenLauncher(_launcher).initialize(CHICKEN_ADMIN);
    }
}
