//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./IRebaseToken.sol";
import {Pool} from "@ccip/contracts/libraries/Pool.sol";
import {console} from "forge-std/Test.sol";

contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router)
        TokenPool(_token, 18, _allowlist, _rmnProxy, _router)
    {}

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);
        address originalSender = lockOrBurnIn.originalSender;
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(originalSender);
        console.log("REBASETOKEN INTEREST RATE", userInterestRate);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);
        address receiver = releaseOrMintIn.receiver;
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        console.log("REBASETOKEN MINT INTEREST RATE", userInterestRate);
        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.sourceDenominatedAmount, userInterestRate);
        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }
}
