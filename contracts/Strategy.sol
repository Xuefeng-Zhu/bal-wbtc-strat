// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/balancer/IVault.sol";
import "../interfaces/balancer/IMerkleRedeem.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    bytes32 public POOL_ID =
        0xfeadd389a5c427952d8fdb8057d6c8ba1156cc56000000000000000000000066;
    IERC20 public POOL = IERC20(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IERC20 public BAL = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IVault public BAL_VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IMerkleRedeem public BAL_DISTRIBUTOR =
        IMerkleRedeem(0x6d19b2bF3A36A61530909Ae65445a906D98A2Fa8);

    constructor(address _vault) public BaseStrategy(_vault) {
        want.approve(address(BAL_VAULT), type(uint256).max);
        POOL.approve(address(BAL_VAULT), type(uint256).max);
        BAL.approve(address(BAL_VAULT), type(uint256).max);
    }

    function manualRedeemRewards(IMerkleRedeem.Claim[] memory claims)
        external
        onlyGovernance
    {
        BAL_DISTRIBUTOR.claimWeeks(payable(address(this)), claims);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        return POOL.balanceOf(address(this));
    }

    function balanceOfBal() public view returns (uint256) {
        return BAL.balanceOf(address(this));
    }

    function name() external view override returns (string memory) {
        return "Strategy-Balancer-wBTC";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        // assume that pool token has similar value to want
        return balanceOfWant() + balanceOfPool();
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _swapBalToWbtc();

        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 assets = estimatedTotalAssets();

        if (debt <= assets) {
            _debtPayment = _debtOutstanding;
            _profit = assets - debt;

            uint256 amountToFree = _profit.add(_debtPayment);
            uint256 wantBalance = balanceOfWant();

            if (wantBalance < amountToFree) {
                _withdrawSome(amountToFree.sub(wantBalance));

                wantBalance = balanceOfWant();
                if (wantBalance < amountToFree) {
                    if (_profit > wantBalance) {
                        _profit = wantBalance;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(
                            wantBalance.sub(_profit),
                            _debtPayment
                        );
                    }
                }
            }
        } else {
            _loss = debt - assets;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = balanceOfWant();

        // do not invest if we have more debt than want
        if (_debtOutstanding > wantBalance) {
            return;
        }

        uint256 toDeposit = wantBalance.sub(_debtOutstanding);
        (IAsset[] memory tokens, , ) = BAL_VAULT.getPoolTokens(POOL_ID);
        require(address(tokens[0]) == address(want));

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = toDeposit;
        amounts[1] = 0;
        amounts[2] = 0;

        bytes memory userData =
            abi.encode(
                IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amounts,
                0 // Note 0 can be frontrun for a bad outcome
            );

        IVault.JoinPoolRequest memory req =
            IVault.JoinPoolRequest({
                assets: tokens,
                maxAmountsIn: amounts,
                userData: userData,
                fromInternalBalance: false
            });

        BAL_VAULT.joinPool(POOL_ID, address(this), address(this), req);
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBalance = balanceOfWant();
        if (wantBalance < _amountNeeded) {
            _withdrawSome(_amountNeeded.sub(wantBalance));
        }

        wantBalance = balanceOfWant();
        if (_amountNeeded > wantBalance) {
            _liquidatedAmount = wantBalance;
            _loss = _amountNeeded.sub(wantBalance);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        return _withdrawSome(type(uint256).max);
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 balanceOfWantBefore = balanceOfWant();

        (IAsset[] memory tokens, , ) = BAL_VAULT.getPoolTokens(POOL_ID);
        require(address(tokens[0]) == address(want));

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _amount;
        amounts[1] = 0;
        amounts[2] = 0;

        // We would need to check how much to withdraw
        // But generally speaking we want to get out the exact amount
        bytes memory userData =
            abi.encode(
                IVault.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
                amounts,
                balanceOfPool()
            );

        IVault.ExitPoolRequest memory req =
            IVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: amounts,
                userData: userData,
                toInternalBalance: false
            });

        BAL_VAULT.exitPool(POOL_ID, address(this), payable(address(this)), req);

        return balanceOfWant().sub(balanceOfWantBefore);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        POOL.transfer(_newStrategy, balanceOfPool());
        POOL.transfer(_newStrategy, balanceOfBal());
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(POOL);
        protected[1] = address(BAL);
        return protected;
    }

    function _swapBalToWbtc() internal {
        uint256 balBalance = balanceOfBal();
        if (balBalance == 0) {
            return;
        }

        bytes memory userData = abi.encode();
        IVault.SingleSwap memory singleSwap =
            IVault.SingleSwap(
                POOL_ID,
                IVault.SwapKind.GIVEN_IN,
                IAsset(address(BAL)),
                IAsset(address(want)),
                balBalance,
                userData
            );
        IVault.FundManagement memory fundManagement =
            IVault.FundManagement(
                address(this),
                false,
                payable(address(this)),
                false
            );

        BAL_VAULT.swap(singleSwap, fundManagement, 0, type(uint256).max);
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
