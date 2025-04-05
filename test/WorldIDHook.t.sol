// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {WorldIDHook} from "../src/WorldIDHook.sol";
import {IWorldID} from "../src/IWorldID.sol";
import {ByteHasher} from "../src/ByteHasher.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {Math} from "@openzeppelin/contracts/utils/Math/Math.sol";

contract WorldIDHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;
    using ByteHasher for bytes;

    WorldIDHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;
    address worldId = makeAddr("worldId");

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, worldId, "", ""); //Add all the necessary constructor arguments from the hook
        deployCodeTo("WorldIDHook.sol:WorldIDHook", constructorArgs, flags);
        hook = WorldIDHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = key.toId();
    }

    function _init(uint256 initPrice) internal {
        uint160 sqrtPrice = uint160(Math.sqrt(FullMath.mulDiv(initPrice, 1 << 192, 1e18)));
        manager.initialize(key, sqrtPrice);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        int256 liquidityAmount = 1000e18;
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(tickLower, tickUpper, liquidityAmount, 0), ZERO_BYTES
        );
    }

    function test_no_fee_reduction() public {
        uint256 initPrice = 1.01e18;
        _init(initPrice);

        // Perform a test swap //
        bool zeroForOne = true;
        uint256 amountSpecified = 1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, -int256(amountSpecified), ZERO_BYTES);

        // ~= 1e18 * 1.01 * 0.999
        assertEq(int256(swapDelta.amount1()), int256(1008885184329855518));
    }

    function test_fee_reduction() public {
        uint256 initPrice = 1.01e18;
        _init(initPrice);

        uint256[8] memory mockedProof;
        for (uint256 i; i < 8; i++) {
            mockedProof[i] = 0;
        }
        vm.mockCall(
            worldId,
            abi.encodeWithSelector(
                IWorldID.verifyProof.selector,
                0,
                1,
                abi.encodePacked(msg.sender).hashToField(),
                0,
                abi.encodePacked(abi.encodePacked("").hashToField(), "").hashToField(),
                mockedProof
            ),
            ""
        );
        hook.verifyAndExecute(0, 0, mockedProof);

        // Perform a test swap //
        bool zeroForOne = false;
        uint256 amountSpecified = 1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, -int256(amountSpecified), ZERO_BYTES);

        // ~= 1e18 / 1.01 * 1 (no fee)
        assertEq(int256(swapDelta.amount0()), int256(989015990718292169));
    }
}
