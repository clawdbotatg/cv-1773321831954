// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TreasuryManager} from "../contracts/TreasuryManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryManagerTest is Test {
    TreasuryManager public treasury;

    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TUSD = 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07;
    address constant POOL = 0xd013725b904e76394A3aB0334Da306C505D778F8;
    address constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    address attacker = makeAddr("attacker");

    uint256 constant MAX_PER_ACTION = 0.5 ether;
    uint256 constant MAX_PER_DAY = 2 ether;
    uint256 constant COOLDOWN = 600; // 10 minutes

    function setUp() public {
        vm.prank(owner);
        treasury = new TreasuryManager(
            owner,
            UNISWAP_ROUTER,
            POOL,
            POSITION_MANAGER,
            WETH,
            TUSD,
            MAX_PER_ACTION,
            MAX_PER_DAY,
            COOLDOWN
        );

        // Set operator
        vm.prank(owner);
        treasury.setOperator(operator);
    }

    // ════════════════════════════ ACCESS CONTROL ═══════════════════════

    function test_OwnerIsSet() public view {
        assertEq(treasury.owner(), owner);
    }

    function test_OperatorIsSet() public view {
        assertEq(treasury.authorizedOperator(), operator);
    }

    function test_RevertWhen_AttackerCallsBuyback() public {
        deal(WETH, address(treasury), 1 ether);
        vm.prank(attacker);
        vm.expectRevert(TreasuryManager.NotAuthorized.selector);
        treasury.buyback(0.1 ether);
    }

    function test_RevertWhen_AttackerCallsBurnHoldings() public {
        deal(TUSD, address(treasury), 100e18);
        vm.prank(attacker);
        vm.expectRevert(TreasuryManager.NotAuthorized.selector);
        treasury.burnHoldings();
    }

    function test_RevertWhen_OperatorCallsRemoveLiquidity() public {
        vm.prank(operator);
        vm.expectRevert();
        treasury.removeLiquidity(0);
    }

    function test_RevertWhen_OperatorCallsWithdrawFunds() public {
        vm.prank(operator);
        vm.expectRevert();
        treasury.withdrawFunds(WETH, 1 ether, attacker);
    }

    // ════════════════════════════ CAPS ═══════════════════════════

    function test_RevertWhen_ExceedsActionCap() public {
        deal(WETH, address(treasury), 10 ether);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManager.ExceedsActionCap.selector, 1 ether, MAX_PER_ACTION));
        treasury.buyback(1 ether);
    }

    function test_RevertWhen_ExceedsDailyCap() public {
        deal(WETH, address(treasury), 10 ether);

        // Use smaller amounts to avoid price impact
        vm.prank(owner);
        treasury.buyback(0.01 ether);

        vm.prank(owner);
        treasury.buyback(0.01 ether);

        // Verify daily cap enforcement
        // Set dailySpent to the limit by direct storage manipulation
        vm.store(
            address(treasury),
            bytes32(uint256(3)), // dailySpent storage slot
            bytes32(MAX_PER_DAY)
        );

        // Next buyback should fail (daily cap reached)
        vm.prank(owner);
        vm.expectRevert(); // ExceedsDailyCap
        treasury.buyback(0.01 ether);
    }

    // ════════════════════════════ COOLDOWN ═══════════════════════════

    function test_RevertWhen_CooldownActive() public {
        deal(WETH, address(treasury), 10 ether);

        vm.prank(operator);
        treasury.buyback(0.1 ether);

        // Immediate second call should fail
        vm.prank(operator);
        vm.expectRevert(); // CooldownActive
        treasury.buyback(0.1 ether);
    }

    function test_CooldownResetsAfterPeriod() public {
        deal(WETH, address(treasury), 10 ether);

        vm.prank(operator);
        treasury.buyback(0.1 ether);

        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(operator);
        treasury.buyback(0.1 ether);
    }

    function test_OwnerBypassesCooldown() public {
        deal(WETH, address(treasury), 10 ether);

        vm.prank(owner);
        treasury.buyback(0.1 ether);

        // Owner can immediately call again
        vm.prank(owner);
        treasury.buyback(0.1 ether);
    }

    // ════════════════════════════ BURN ═══════════════════════════

    function test_BurnHoldings() public {
        deal(TUSD, address(treasury), 1000e18);
        uint256 deadBefore = IERC20(TUSD).balanceOf(DEAD);

        vm.prank(operator);
        treasury.burnHoldings();

        assertEq(IERC20(TUSD).balanceOf(DEAD) - deadBefore, 1000e18);
        assertEq(IERC20(TUSD).balanceOf(address(treasury)), 0);
    }

    function test_RevertWhen_BurnZero() public {
        vm.prank(operator);
        vm.expectRevert(TreasuryManager.ZeroAmount.selector);
        treasury.burnHoldings();
    }

    // ════════════════════════════ BUYBACK (FORK) ═══════════════════════════

    function test_BuybackSwapsWethToTusd() public {
        deal(WETH, address(treasury), 0.5 ether);

        vm.prank(operator);
        treasury.buyback(0.1 ether);

        assertGt(IERC20(TUSD).balanceOf(address(treasury)), 0);
    }

    // ════════════════════════════ OPERATOR MANAGEMENT ═══════════════════════════

    function test_SetOperator() public {
        address newOp = makeAddr("newOp");
        vm.prank(owner);
        treasury.setOperator(newOp);
        assertEq(treasury.authorizedOperator(), newOp);
    }

    function test_RevokeOperator() public {
        vm.prank(owner);
        treasury.revokeOperator();
        assertEq(treasury.authorizedOperator(), address(0));
    }

    function test_RevertWhen_SetOperatorZero() public {
        vm.prank(owner);
        vm.expectRevert(TreasuryManager.ZeroAddress.selector);
        treasury.setOperator(address(0));
    }

    // ════════════════════════════ WITHDRAW ═══════════════════════════

    function test_WithdrawFunds() public {
        deal(WETH, address(treasury), 1 ether);

        vm.prank(owner);
        treasury.withdrawFunds(WETH, 0.5 ether, owner);

        assertEq(IERC20(WETH).balanceOf(owner), 0.5 ether);
    }

    // ════════════════════════════ LIQUIDITY ═══════════════════════════

    /// @dev Pool: token0=TUSD, token1=WETH. Current tick ≈ -199140. Fee=10000 → tickSpacing=200.
    ///      Tick range must be multiples of 200 and straddle current tick.
    function test_AddLiquidity() public {
        // Fund treasury with both tokens
        deal(WETH, address(treasury), 0.01 ether);
        deal(TUSD, address(treasury), 5_000_000e18);

        // Ticks divisible by 200, straddling current tick -199140
        int24 tickLower = -200_000;
        int24 tickUpper = -198_200;

        uint256 wethBefore = IERC20(WETH).balanceOf(address(treasury));
        uint256 tusdBefore = IERC20(TUSD).balanceOf(address(treasury));

        vm.prank(owner);
        // amount0Min=0, amount1Min=0: pool ratio determines actual consumed amounts
        treasury.addLiquidity(tickLower, tickUpper, 5_000_000e18, 0.01 ether, 0, 0);

        // Position should be tracked
        assertEq(treasury.getLpTokenIds().length, 1);

        // Tokens should have been consumed
        assertLt(IERC20(WETH).balanceOf(address(treasury)), wethBefore);
        assertLt(IERC20(TUSD).balanceOf(address(treasury)), tusdBefore);

        console.log("LP token ID:", treasury.getLpTokenIds()[0]);
        console.log("WETH consumed:", wethBefore - IERC20(WETH).balanceOf(address(treasury)));
        console.log("TUSD consumed:", tusdBefore - IERC20(TUSD).balanceOf(address(treasury)));
    }

    function test_AddAndRemoveLiquidity() public {
        deal(WETH, address(treasury), 0.01 ether);
        deal(TUSD, address(treasury), 5_000_000e18);

        vm.prank(owner);
        treasury.addLiquidity(-200_000, -198_200, 5_000_000e18, 0.01 ether, 0, 0);

        uint256 tokenId = treasury.getLpTokenIds()[0];
        assertEq(treasury.getLpTokenIds().length, 1);

        // Remove it — owner only
        vm.prank(owner);
        treasury.removeLiquidity(tokenId);

        // LP tracking cleared
        assertEq(treasury.getLpTokenIds().length, 0);

        // Tokens returned to treasury
        assertGt(IERC20(WETH).balanceOf(address(treasury)) + IERC20(TUSD).balanceOf(address(treasury)), 0);
    }

    function test_RevertWhen_InvalidTickRange() public {
        deal(WETH, address(treasury), 1 ether);
        deal(TUSD, address(treasury), 1_000_000e18);

        vm.prank(owner);
        vm.expectRevert(TreasuryManager.InvalidTickRange.selector);
        // tickLower >= tickUpper → invalid
        treasury.addLiquidity(-100, -200, 1_000_000e18, 0.1 ether, 0, 0);
    }

    function test_RevertWhen_OperatorCannotAddLiquidity_AboveCap() public {
        deal(WETH, address(treasury), 10 ether);
        deal(TUSD, address(treasury), 100_000_000e18);

        vm.prank(operator);
        vm.expectRevert(); // ExceedsActionCap — WETH amount > MAX_PER_ACTION (0.5 ether)
        treasury.addLiquidity(-200_000, -198_200, 50_000_000e18, 1 ether, 0, 0);
    }

    // ════════════════════════════ VIEW ═══════════════════════════

    function test_GetStatus() public view {
        (uint256 wBal, uint256 tBal, uint256 spent, uint256 remaining, uint256 cooldown, address op, uint256 lpCount) = treasury.getStatus();
        assertEq(wBal, 0);
        assertEq(tBal, 0);
        assertEq(spent, 0);
        assertEq(remaining, MAX_PER_DAY);
        assertEq(cooldown, 0);
        assertEq(op, operator);
        assertEq(lpCount, 0);
    }
}
