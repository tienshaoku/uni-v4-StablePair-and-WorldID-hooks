// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {FixedPoint96} from "v4-core/src/libraries/FixedPoint96.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {ByteHasher} from "./ByteHasher.sol";
import {IWorldID} from "./IWorldID.sol";

contract WorldIDHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using ByteHasher for bytes;

    /// @notice Thrown when attempting to reuse a nullifier
    error DuplicateNullifier(uint256 nullifierHash);

    IWorldID internal immutable worldId;
    uint256 internal immutable externalNullifier;
    uint256 internal immutable groupId = 1;
    mapping(address => bool) public isVerified;
    mapping(uint256 => bool) internal _nullifierHashes;

    /// @param _worldId The WorldID router that will verify the proofs
    /// @param _appId The World ID app ID
    /// @param _actionId The World ID action ID
    constructor(IPoolManager _poolManager, IWorldID _worldId, string memory _appId, string memory _actionId)
        BaseHook(_poolManager)
    {
        worldId = _worldId;
        externalNullifier = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // Hook functions
    // -----------------------------------------------

    function _afterInitialize(address sender, PoolKey calldata key, uint160, int24)
        internal
        override
        returns (bytes4)
    {
        poolManager.updateDynamicLPFee(key, 100); // 100 bps

        return (BaseHook.afterInitialize.selector);
    }

    function _beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,, uint24 fee) = poolManager.getSlot0(poolId);
        fee = isVerified[sender] ? 0 : fee;

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// @param root The root of the Merkle tree (returned by the JS widget).
    /// @param nullifierHash The nullifier hash for this proof, preventing double signaling (returned by the JS widget).
    /// @param proof The zero-knowledge proof that demonstrates the claimer is registered with World ID (returned by the JS widget).
    /// @dev Feel free to rename this method however you want! We've used `claim`, `verify` or `execute` in the past.
    function verifyAndExecute(uint256 root, uint256 nullifierHash, uint256[8] calldata proof) external {
        // First, we make sure this person hasn't done this before
        if (!isVerified[msg.sender]) {
            if (_nullifierHashes[nullifierHash]) revert DuplicateNullifier(nullifierHash);

            // We now verify the provided proof is valid and the user is verified by World ID
            try worldId.verifyProof(
                root, groupId, abi.encodePacked(msg.sender).hashToField(), nullifierHash, externalNullifier, proof
            ) {
                _nullifierHashes[nullifierHash] = true;
                isVerified[msg.sender] = true;
            } catch {}
        }
    }
}
