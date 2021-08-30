// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

interface IVault {
    // Stable Pool
    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IAsset[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );

    // Vault
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    // userData looks like this: scrapd from pkg/pool-stable/contracts/StablePoolUserDataHelpers.sol
    // Join
    // function exactTokensInForBptOut(bytes memory self)
    //     internal
    //     pure
    //     returns (bytes memory self, uint256[] memory amountsIn, uint256 minBPTAmountOut)
    // {
    //     (joinKind, amountsIn, minBPTAmountOut) = abi.decode(self, (StablePool.JoinKind, uint256[], uint256));
    // }

    // // Exits
    // function exactBptInForTokenOut(bytes memory self) internal pure returns (uint256 bptAmountIn, uint256 tokenIndex) {
    //     (, bptAmountIn, tokenIndex) = abi.decode(self, (StablePool.ExitKind, uint256, uint256));
    // }

    // function bptInForExactTokensOut(bytes memory self)
    //     internal
    //     pure
    //     returns (uint256[] memory amountsOut, uint256 maxBPTAmountIn)
    // {
    //     (, amountsOut, maxBPTAmountIn) = abi.decode(self, (StablePool.ExitKind, uint256[], uint256));
    // }
}
