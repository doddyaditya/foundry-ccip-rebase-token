//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";

import {Vault} from "../src/Vault.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/IRebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";

contract TokenandPoolDeployer is Script {
    function run() public returns (RebaseToken, RebaseTokenPool) {
        vm.startBroadcast();
        RebaseToken rebaseToken = new RebaseToken();
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        RebaseTokenPool rebaseTokenPool = new RebaseTokenPool(
            IERC20(address(rebaseToken)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );
        rebaseToken.grantBurnAndMintRole(address(rebaseTokenPool));
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(rebaseToken));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(rebaseToken));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress)
            .setPool(address(rebaseToken), address(rebaseTokenPool));
        vm.stopBroadcast();
        return (rebaseToken, rebaseTokenPool);
    }
}

contract VaultDeployer is Script {
    function run(address _rebaseToken) public returns (Vault) {
        vm.startBroadcast();
        Vault vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantBurnAndMintRole(address(vault));
        vm.stopBroadcast();
        return vault;
    }
}
