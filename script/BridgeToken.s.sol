//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

contract BridgeToken is Script {
    function run(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress
    ) public {
        Client.EVMTokenAmount[] memory evmTokenAmount = new Client.EVMTokenAmount[](1);
        evmTokenAmount[0] = Client.EVMTokenAmount({token: tokenAddress, amount: amountToSend});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: evmTokenAmount,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        vm.startBroadcast();
        uint256 fee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(address(routerAddress), fee);
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
