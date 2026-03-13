// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter02} from "./interfaces/ISwapRouter02.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

/// @title TreasuryManager — Custodied Treasury for ₸USD Monetary Policy
/// @notice Owner + authorized operator pattern with hard-coded caps
/// @dev Owner is Austin's personal wallet. Operator is the bot hot wallet.
contract TreasuryManager is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════════
    //                        IMMUTABLE STATE
    // ══════════════════════════════════════════════════════════════════

    ISwapRouter02 public immutable UNISWAP_ROUTER;
    IUniswapV3Pool public immutable POOL;
    INonfungiblePositionManager public immutable POSITION_MANAGER;
    IERC20 public immutable WETH;
    IERC20 public immutable TUSD;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint24 public constant POOL_FEE = 10000; // 1%

    /// @notice Maximum WETH spend per single action (immutable)
    uint256 public immutable MAX_SPEND_PER_ACTION;

    /// @notice Maximum WETH spend per rolling 24h window (immutable)
    uint256 public immutable MAX_SPEND_PER_DAY;

    /// @notice Minimum seconds between operator actions (immutable)
    uint256 public immutable COOLDOWN_PERIOD;

    /// @notice TWAP window in seconds for price checks
    uint32 public constant TWAP_WINDOW = 1800; // 30 minutes

    /// @notice Maximum slippage tolerance in basis points
    uint256 public constant MAX_SLIPPAGE_BPS = 300; // 3%

    // ══════════════════════════════════════════════════════════════════
    //                           STORAGE
    // ══════════════════════════════════════════════════════════════════

    address public authorizedOperator;

    /// @notice Rolling 24h spend tracker (in WETH, 18 decimals)
    uint256 public dailySpent;

    /// @notice Timestamp of last daily spend reset
    uint256 public dailyResetTimestamp;

    /// @notice Timestamp of last operator action (cooldown enforcement)
    uint256 public lastActionTimestamp;

    /// @notice LP token IDs owned by this contract
    uint256[] public lpTokenIds;

    // ══════════════════════════════════════════════════════════════════
    //                           EVENTS
    // ══════════════════════════════════════════════════════════════════

    event BuybackExecuted(uint256 wethSpent, uint256 tusdReceived);
    event BurnExecuted(uint256 tusdBurned);
    event LiquidityAdded(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 tokenId, uint256 amount0, uint256 amount1);
    event OperatorSet(address indexed newOperator);
    event OperatorRevoked(address indexed oldOperator);
    event FundsWithdrawn(address indexed token, uint256 amount, address indexed to);

    // ══════════════════════════════════════════════════════════════════
    //                           ERRORS
    // ══════════════════════════════════════════════════════════════════

    error NotAuthorized();
    error ExceedsActionCap(uint256 requested, uint256 max);
    error ExceedsDailyCap(uint256 requested, uint256 remaining);
    error CooldownActive(uint256 timeRemaining);
    error ZeroAmount();
    error ZeroAddress();

    // ══════════════════════════════════════════════════════════════════
    //                          MODIFIERS
    // ══════════════════════════════════════════════════════════════════

    modifier onlyOperatorOrOwner() {
        if (msg.sender != owner() && msg.sender != authorizedOperator) revert NotAuthorized();
        _;
    }

    modifier enforceCapAndCooldown(uint256 wethAmount) {
        if (wethAmount == 0) revert ZeroAmount();
        if (wethAmount > MAX_SPEND_PER_ACTION) revert ExceedsActionCap(wethAmount, MAX_SPEND_PER_ACTION);

        // Reset daily counter if 24h passed
        if (block.timestamp >= dailyResetTimestamp + 1 days) {
            dailySpent = 0;
            dailyResetTimestamp = block.timestamp;
        }

        uint256 remaining = MAX_SPEND_PER_DAY - dailySpent;
        if (wethAmount > remaining) revert ExceedsDailyCap(wethAmount, remaining);

        // Cooldown check (only for operator, owner bypasses)
        if (msg.sender == authorizedOperator && block.timestamp < lastActionTimestamp + COOLDOWN_PERIOD) {
            revert CooldownActive(lastActionTimestamp + COOLDOWN_PERIOD - block.timestamp);
        }

        _;

        dailySpent += wethAmount;
        lastActionTimestamp = block.timestamp;
    }

    // ══════════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════════

    constructor(
        address _owner,
        address _uniswapRouter,
        address _pool,
        address _positionManager,
        address _weth,
        address _tusd,
        uint256 _maxSpendPerAction,
        uint256 _maxSpendPerDay,
        uint256 _cooldownPeriod
    ) Ownable(_owner) {
        UNISWAP_ROUTER = ISwapRouter02(_uniswapRouter);
        POOL = IUniswapV3Pool(_pool);
        POSITION_MANAGER = INonfungiblePositionManager(_positionManager);
        WETH = IERC20(_weth);
        TUSD = IERC20(_tusd);
        MAX_SPEND_PER_ACTION = _maxSpendPerAction;
        MAX_SPEND_PER_DAY = _maxSpendPerDay;
        COOLDOWN_PERIOD = _cooldownPeriod;
        dailyResetTimestamp = block.timestamp;
    }

    // ══════════════════════════════════════════════════════════════════
    //                    OPERATOR/OWNER FUNCTIONS
    // ══════════════════════════════════════════════════════════════════

    /// @notice Market buy ₸USD with WETH (within caps)
    function buyback(uint256 amountIn)
        external
        nonReentrant
        onlyOperatorOrOwner
        enforceCapAndCooldown(amountIn)
    {
        uint256 minAmountOut = _calculateMinAmountOut(amountIn);

        WETH.forceApprove(address(UNISWAP_ROUTER), amountIn);

        uint256 tusdReceived = UNISWAP_ROUTER.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(TUSD),
                fee: POOL_FEE,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        emit BuybackExecuted(amountIn, tusdReceived);
    }

    /// @notice Burn all TUSD held by this contract
    function burnHoldings() external nonReentrant onlyOperatorOrOwner {
        uint256 tusdBalance = TUSD.balanceOf(address(this));
        if (tusdBalance == 0) revert ZeroAmount();

        TUSD.safeTransfer(DEAD, tusdBalance);

        emit BurnExecuted(tusdBalance);
    }

    /// @notice Add concentrated liquidity to the WETH/TUSD pool
    function addLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        external
        nonReentrant
        onlyOperatorOrOwner
        enforceCapAndCooldown(_wethAmountFromLiquidity(amount0Desired, amount1Desired))
    {
        address token0 = POOL.token0();
        address token1 = POOL.token1();

        IERC20(token0).forceApprove(address(POSITION_MANAGER), amount0Desired);
        IERC20(token1).forceApprove(address(POSITION_MANAGER), amount1Desired);

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            POSITION_MANAGER.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: POOL_FEE,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );

        lpTokenIds.push(tokenId);

        emit LiquidityAdded(tokenId, liquidity, amount0, amount1);
    }

    // ══════════════════════════════════════════════════════════════════
    //                      OWNER-ONLY FUNCTIONS
    // ══════════════════════════════════════════════════════════════════

    /// @notice Remove an LP position — OWNER ONLY
    function removeLiquidity(uint256 tokenId) external nonReentrant onlyOwner {
        // Get position info
        (,,,,,,, uint128 liquidity,,,,) = POSITION_MANAGER.positions(tokenId);

        // Decrease liquidity
        POSITION_MANAGER.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // Collect tokens
        (uint256 amount0, uint256 amount1) = POSITION_MANAGER.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Remove from tracking array
        _removeLpTokenId(tokenId);

        emit LiquidityRemoved(tokenId, amount0, amount1);
    }

    /// @notice Emergency fund withdrawal — OWNER ONLY
    function withdrawFunds(address token, uint256 amount, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit FundsWithdrawn(token, amount, to);
    }

    /// @notice Set a new authorized operator
    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        authorizedOperator = newOperator;
        emit OperatorSet(newOperator);
    }

    /// @notice Emergency revoke operator access
    function revokeOperator() external onlyOwner {
        address old = authorizedOperator;
        authorizedOperator = address(0);
        emit OperatorRevoked(old);
    }

    // ══════════════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════════

    /// @notice Get treasury status
    function getStatus()
        external
        view
        returns (
            uint256 wethBalance,
            uint256 tusdBalance,
            uint256 _dailySpent,
            uint256 dailyRemaining,
            uint256 cooldownRemaining,
            address operator,
            uint256 lpCount
        )
    {
        uint256 _remaining = MAX_SPEND_PER_DAY;
        if (block.timestamp < dailyResetTimestamp + 1 days) {
            _remaining = MAX_SPEND_PER_DAY > dailySpent ? MAX_SPEND_PER_DAY - dailySpent : 0;
        }

        uint256 _cooldown = 0;
        if (block.timestamp < lastActionTimestamp + COOLDOWN_PERIOD) {
            _cooldown = lastActionTimestamp + COOLDOWN_PERIOD - block.timestamp;
        }

        return (
            WETH.balanceOf(address(this)),
            TUSD.balanceOf(address(this)),
            dailySpent,
            _remaining,
            _cooldown,
            authorizedOperator,
            lpTokenIds.length
        );
    }

    /// @notice Get TWAP price over the configured window
    function getTWAPPrice() external view returns (uint256 price) {
        return _getTWAPPrice();
    }

    /// @notice Get all LP token IDs
    function getLpTokenIds() external view returns (uint256[] memory) {
        return lpTokenIds;
    }

    // ══════════════════════════════════════════════════════════════════
    //                      INTERNAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════════

    function _calculateMinAmountOut(uint256 amountIn) internal view returns (uint256) {
        uint256 twapPrice = _getTWAPPrice();
        address token0 = POOL.token0();

        uint256 expectedOut;
        if (token0 == address(WETH)) {
            // WETH is token0, TUSD is token1
            // twapPrice is in terms of tick → we need to convert
            expectedOut = (amountIn * twapPrice) / 1e18;
        } else {
            expectedOut = (amountIn * 1e18) / twapPrice;
        }

        return (expectedOut * (10000 - MAX_SLIPPAGE_BPS)) / 10000;
    }

    /// @dev Get 30-min TWAP tick, convert to price
    function _getTWAPPrice() internal view returns (uint256) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_WINDOW;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = POOL.observe(secondsAgos);

        int24 twapTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(TWAP_WINDOW)));

        // Convert tick to sqrtPriceX96
        // price = 1.0001^tick
        // For simplicity, use the approximation via TickMath equivalent
        uint160 sqrtPriceX96 = _getSqrtRatioAtTick(twapTick);

        address token0 = POOL.token0();
        uint256 sqrtPrice = uint256(sqrtPriceX96);

        if (token0 == address(WETH)) {
            return (sqrtPrice * sqrtPrice * 1e18) >> 192;
        } else {
            return (1e18 << 192) / (sqrtPrice * sqrtPrice);
        }
    }

    /// @dev Compute sqrt(1.0001^tick) * 2^96 — simplified TickMath
    /// Adapted from Uniswap V3 TickMath library
    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= 887272, "T");

        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /// @dev Determine WETH amount from liquidity add parameters
    function _wethAmountFromLiquidity(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        address token0 = POOL.token0();
        if (token0 == address(WETH)) {
            return amount0;
        } else {
            return amount1;
        }
    }

    /// @dev Remove LP token ID from tracking array
    function _removeLpTokenId(uint256 tokenId) internal {
        uint256 len = lpTokenIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (lpTokenIds[i] == tokenId) {
                lpTokenIds[i] = lpTokenIds[len - 1];
                lpTokenIds.pop();
                return;
            }
        }
    }

    /// @dev Required to receive ERC721 tokens (LP NFTs)
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
