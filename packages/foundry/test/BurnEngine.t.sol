// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BurnEngine} from "../contracts/BurnEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BurnEngineTest is Test {
    BurnEngine public burnEngine;

    address constant CLANKER_FEE_LOCKER = 0xF3622742b1E446D92e45E22923Ef11C2fcD55D68;
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TUSD = 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07;
    address constant POOL = 0xd013725b904e76394A3aB0334Da306C505D778F8;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address alice = makeAddr("alice");

    function setUp() public {
        // Fork Base mainnet
        burnEngine = new BurnEngine(
            CLANKER_FEE_LOCKER,
            UNISWAP_ROUTER,
            POOL,
            WETH,
            TUSD
        );
    }

    function test_Constructor() public view {
        assertEq(address(burnEngine.CLANKER_FEE_LOCKER()), CLANKER_FEE_LOCKER);
        assertEq(address(burnEngine.UNISWAP_ROUTER()), UNISWAP_ROUTER);
        assertEq(address(burnEngine.WETH()), WETH);
        assertEq(address(burnEngine.TUSD()), TUSD);
        assertEq(burnEngine.totalBurnedAllTime(), 0);
        assertEq(burnEngine.cycleCount(), 0);
    }

    function test_GetStatus() public view {
        (uint256 burned, uint256 lastCycle, uint256 count, uint256 wethBal, uint256 tusdBal) = burnEngine.getStatus();
        assertEq(burned, 0);
        assertEq(lastCycle, 0);
        assertEq(count, 0);
        assertEq(wethBal, 0);
        assertEq(tusdBal, 0);
    }

    function test_GetCurrentPrice() public view {
        uint256 price = burnEngine.getCurrentPrice();
        // Price should be non-zero
        assertGt(price, 0);
        console.log("TUSD price in WETH:", price);
    }

    function test_RevertWhen_NothingToBurn() public {
        // BurnEngine is not set as feeOwner and has no tokens
        // The claim calls should succeed but yield 0, then revert on NothingToBurn
        vm.expectRevert(BurnEngine.NothingToBurn.selector);
        burnEngine.executeFullCycle();
    }

    function test_ExecuteCycleWithDirectTusd() public {
        // Send some TUSD directly to the BurnEngine to test the burn path
        // Deal TUSD to the burn engine
        deal(TUSD, address(burnEngine), 1000e18);

        uint256 deadBefore = IERC20(TUSD).balanceOf(DEAD);

        burnEngine.executeFullCycle();

        uint256 deadAfter = IERC20(TUSD).balanceOf(DEAD);
        assertEq(deadAfter - deadBefore, 1000e18);
        assertEq(burnEngine.totalBurnedAllTime(), 1000e18);
        assertEq(burnEngine.cycleCount(), 1);
        assertGt(burnEngine.lastCycleTimestamp(), 0);
    }

    function test_ExecuteCycleWithWeth() public {
        // Send WETH to BurnEngine to test the swap + burn path
        deal(WETH, address(burnEngine), 0.01 ether);

        uint256 deadBefore = IERC20(TUSD).balanceOf(DEAD);

        burnEngine.executeFullCycle();

        uint256 deadAfter = IERC20(TUSD).balanceOf(DEAD);
        assertGt(deadAfter, deadBefore);
        assertGt(burnEngine.totalBurnedAllTime(), 0);
        assertEq(burnEngine.cycleCount(), 1);
    }

    function test_MultipleCycles() public {
        deal(TUSD, address(burnEngine), 500e18);
        burnEngine.executeFullCycle();
        assertEq(burnEngine.cycleCount(), 1);

        deal(TUSD, address(burnEngine), 300e18);
        burnEngine.executeFullCycle();
        assertEq(burnEngine.cycleCount(), 2);
        assertEq(burnEngine.totalBurnedAllTime(), 800e18);
    }

    function test_EmitsEvent() public {
        deal(TUSD, address(burnEngine), 100e18);

        vm.expectEmit(false, false, false, false);
        emit BurnEngine.CycleExecuted(0, 0, 0, 0, 100e18, 100e18, block.timestamp);

        burnEngine.executeFullCycle();
    }

    function test_AnyoneCanCall() public {
        deal(TUSD, address(burnEngine), 100e18);

        vm.prank(alice);
        burnEngine.executeFullCycle();

        assertEq(burnEngine.cycleCount(), 1);
    }
}
