// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {WorldIDHook} from "../src/WorldIDHook.sol";
import {IWorldID} from "../src/IWorldID.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/// @notice Mines the address and deploys the WorldIDHook.sol Hook contract
contract WorldIDHookScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, address(0), "", "");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(WorldIDHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        WorldIDHook hook = new WorldIDHook{salt: salt}(IPoolManager(POOLMANAGER), IWorldID(address(0)), "", "");
        console.logAddress(address(hook));
        require(address(hook) == hookAddress, "WorldIDHookScript: hook address mismatch");
    }
}
