//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";

import {IRebaseToken} from "../src/IRebaseToken.sol";

contract CrossChainTest is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 constant SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetail;
    Register.NetworkDetails arbSepoliaNetworkDetail;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    function setUp() public {
        string memory SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
        string memory ARB_SEPOLIA_RPC_URL = vm.envString("ARB_SEPOLIA_RPC_URL");

        sepoliaFork = vm.createSelectFork(SEPOLIA_RPC_URL);
        arbSepoliaFork = vm.createFork(ARB_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        //DEPLOY REBASE TOKEN ON SEPOLIA
        sepoliaNetworkDetail = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        vm.deal(address(vault), 1e18);
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetail.rmnProxyAddress,
            sepoliaNetworkDetail.routerAddress
        );
        sepoliaToken.grantBurnAndMintRole(address(vault));
        sepoliaToken.grantBurnAndMintRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetail.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetail.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetail.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));
        vm.stopPrank();

        //DEPLOY REBASE TOKEN ON ARBITRUM SEPOLIA
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetail = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetail.rmnProxyAddress,
            arbSepoliaNetworkDetail.routerAddress
        );
        arbSepoliaToken.grantBurnAndMintRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetail.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetail.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetail.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetail.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetail.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        TokenPool.ChainUpdate[] memory chainUpdate = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        bytes memory remoteTokenAddress = abi.encode(remoteToken);
        chainUpdate[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: remoteTokenAddress,
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(address(localPool)).applyChainUpdates(new uint64[](0), chainUpdate);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory evmTokenAmount = new Client.EVMTokenAmount[](1);
        evmTokenAmount[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: evmTokenAmount,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = IERC20(address(localToken)).balanceOf(user);
        console.log("LOCAL BALANCE BEFORE", localBalanceBefore);
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = IERC20(address(localToken)).balanceOf(user);
        console.log("LOCAL BALANCE AFTER", localBalanceAfter);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = IERC20(address(remoteToken)).balanceOf(user);
        console.log("REMOTE BALANCE BEFORE", remoteBalanceBefore);
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        vm.selectFork(remoteFork);
        uint256 remoteBalanceAfter = IERC20(address(remoteToken)).balanceOf(user);
        console.log("REMOTE BALANCE AFTER", remoteBalanceAfter);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);

        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(remoteUserInterestRate, localUserInterestRate);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetail,
            arbSepoliaNetworkDetail,
            sepoliaToken,
            arbSepoliaToken
        );
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(
            arbSepoliaToken.balanceOf(user),
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetail,
            sepoliaNetworkDetail,
            arbSepoliaToken,
            sepoliaToken
        );
    }
}
