// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./FixedPointTypes.sol";

/**
 * @dev beta = 1.0 at the VM's close-time.
 */
UFixed256x18 constant _BETA_CLOSE = UFIXED256X18_ONE;

uint256 constant _MIN_POSSIBLE_COMMITMENT_AMOUNT = 1;

uint256 constant _MAX_POSSIBLE_COMMITMENT_AMOUNT = type(uint256).max;

/**
 * @dev 255 not 256, because nOutcomes is stored in in a uint8
 */
uint256 constant _MAX_OUTCOMES_PER_VIRTUAL_FLOOR = 255;

/**
 * @notice Totals over all commitments to a specific VM outcome
 */
struct OutcomeTotals {
    /**
     * @notice Total ERC-20 payment-token amount committed to this outcome.
     */
    uint256 amount;

    /**
     * @notice Total (ERC-20 payment-token amount × beta × 1e18) committed to this outcome.
     */
    UFixed256x18 amountTimesBeta_e18;
}

/**
 * @dev Component of the VM state that is stored on-chain.
 * This is combined with block.timestamp and vm.nonzeroOutcomeCount to calculate the exact state.
 */
enum VirtualMarketInternalState {
    None,
    Active,
    Claimable_Payouts,
    Claimable_Refunds_ResolvedNoWinners,
    Claimable_Refunds_ResolvableNever,
    Claimable_Refunds_Flagged
}

/**
 * @dev Main VM data structure.
 */
struct VirtualMarket {
    // Storage slot 0
    address creator; //   20 bytes
    uint32 tOpen;    // +  4 bytes
    uint32 tClose;   // +  4 bytes
    uint32 tResolve; // +  4 bytes
                     // = 32 bytes => packed into 1 32-byte slot

    // Storage slot 1
    UFixed32x6 betaOpenMinusBetaClose;        // +  4 bytes ; fits with 6-decimal-place precision entire range [0.000000, 4294.967295]
    UFixed16x4 totalFeeRate;                  // +  2 bytes ; fits with 4-decimal-place precision entire range [0.0000, 1.0000]
    UFixed16x4 protocolFeeRate;               // +  2 bytes ; fits with 4-decimal-place precision entire range [0.0000, 1.0000]
    uint8 nOutcomes;                          // +  1 byte
    VirtualMarketInternalState _internalState; // +  1 byte
    uint8 nonzeroOutcomeCount;                // +  1 byte  ; number of outcomes having aggregate commitments > 0
    IERC20Upgradeable paymentToken;           // + 20 bytes
                                              // = 31 bytes => packed into 1 32-byte slot

    // Storage slot 2: Not written to, but used in calculation of outcome-specific slots
    // A fixed-length array is used so as not to store an entire 32-byte slot to write array-length,
    // and instead the length is stored in 1 byte in `nOutcomes`
    OutcomeTotals[_MAX_OUTCOMES_PER_VIRTUAL_FLOOR] outcomeTotals;

    // Storage slot 3
    uint8 winningOutcomeIndex; // +  1 byte
    uint192 winnerProfits;     // + 24 bytes ; fits with 18-decimal-place precision all values up to ~1.5e30 (and with less decimals, more)
                               // = 25 bytes => packed into 1 32-byte slot

    // Storage slot 4
    uint256 bonusAmount;

    // Storage slot 5
    // _prefixed as they are not meant to be read directly, but through .minMaxCommitmentAmounts()
    uint128 _optionalMinCommitmentAmount;
    uint128 _optionalMaxCommitmentAmount;
}


/**
 * @notice Exact state of a VM.
 */
enum VirtualMarketState {
    /**
     * @notice VM does not exist.
     */
    None,

    /**
     * @notice VM accepting commitments to outcomes.
     * For a VM to be resolvable, there must be (i) one or more winners, and (ii) funds to share between those winners.
     * If a VM is in the `Active_Open_MaybeResolvableNever` state, it means that not enough commitments have been yet
     * made to enough different outcomes to ensure that it will be possible to meet these conditions when commitments close.
     * In this state commitment-balances on this VM cannot be transferred.
     */
    Active_Open_MaybeResolvableNever,

    /**
     * @notice VM open for commitments.
     * Enough commitments have been made to enough different outcomes to allow this VM to not be classified as *Unresolvable* at t == tClose.
     * In this VM state, commitment-balances on this VM may be transferred.
     */
    Active_Open_ResolvableLater,

    /**
     * @notice VM closed for commitments.
     * For a VM to be resolvable, there must be (i) one or more winners, and (ii) funds to share between those winners.
     * Commitment-period is now closed with either of these conditions left unsatisfied, so VM is classified as unresolvable.
     * Only possible action is to call cancelVirtualMarketUnresolvable.
     * In this state commitment-balances on this VM cannot be transferred.
     */
    Active_Closed_ResolvableNever,

    /**
     * @notice VM closed for commitments.
     * Only possible action is to wait for result to be published at tResolve.
     * In this VM state, commitment-balances on this VM may be transferred.
     */
    Active_Closed_ResolvableLater,

    /**
     * @notice The VM is active but is closed for commitments.
     * The only course of action is for the extending contract to call _resolve.
     */
    Active_Closed_ResolvableNow,

    /**
     * @notice The VM was resolved with a winning outcome,
     * and accounts having commitments on that winning outcome may call claimPayouts.
     */
    Claimable_Payouts,

    /**
     * @notice The VM was cancelled because there were no commitments to the winning outcome,
     * and accounts having commitments on any of this VM's outcomes may claim back a refund of the original commitment.
     */
    Claimable_Refunds_ResolvedNoWinners,

    /**
     * @notice The VM was cancelled because at close-time the VM was unresolvable,
     * and accounts having commitments on any of this VM's outcomes may claim back a refund of the original commitment.
     */
    Claimable_Refunds_ResolvableNever,

    /**
     * @notice The VM was cancelled because it was flagged,
     * and accounts having commitments on any of this VM's outcomes may claim back a refund of the original commitment.
     */
    Claimable_Refunds_Flagged
}



/**
 * @title VirtualMarket object methods
 
 */
library VirtualMarkets {

    using FixedPointTypes for UFixed256x18;
    using FixedPointTypes for UFixed32x6;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using VirtualMarkets for VirtualMarket;

    /**
     * @dev Combines the entire state of a VM into this single state value,
     * so that Base can determine the next possible action for a VM based on
     * this combined state alone.
     */
    function state(VirtualMarket storage vm) internal view returns (VirtualMarketState) {
        VirtualMarketInternalState _internalState = vm._internalState;
        if (_internalState == VirtualMarketInternalState.None) {
            return VirtualMarketState.None;
        } else if (_internalState == VirtualMarketInternalState.Active) {
            // solhint-disable-next-line not-rely-on-time
            if (block.timestamp < vm.tClose) {
                if (vm.nonzeroOutcomeCount >= 2) {
                    return VirtualMarketState.Active_Open_ResolvableLater;
                } else {
                    return VirtualMarketState.Active_Open_MaybeResolvableNever;
                }
            } else {
                if (vm.nonzeroOutcomeCount >= 2) {
                    // solhint-disable-next-line not-rely-on-time
                    if (block.timestamp < vm.tResolve) {
                        return VirtualMarketState.Active_Closed_ResolvableLater;
                    } else {
                        return VirtualMarketState.Active_Closed_ResolvableNow;
                    }
                } else {
                    return VirtualMarketState.Active_Closed_ResolvableNever;
                }
            }
        } else if (_internalState == VirtualMarketInternalState.Claimable_Payouts) {
            return VirtualMarketState.Claimable_Payouts;
        } else if (_internalState == VirtualMarketInternalState.Claimable_Refunds_ResolvedNoWinners) {
            return VirtualMarketState.Claimable_Refunds_ResolvedNoWinners;
        } else if (_internalState == VirtualMarketInternalState.Claimable_Refunds_ResolvableNever) {
            return VirtualMarketState.Claimable_Refunds_ResolvableNever;
        } else /*if (_internalState == VirtualMarketInternalState.Claimable_Refunds_Flagged)*/ {
            assert(_internalState == VirtualMarketInternalState.Claimable_Refunds_Flagged); // Ensure all enum values have been handled.
            return VirtualMarketState.Claimable_Refunds_Flagged;
        }
    }

    /**
     * @dev Compare:
     * 1. (((tClose - t) * (betaOpen - 1)) / (tClose - tOpen)) * amount
     * 2. (((tClose - t) * (betaOpen - 1) * amount) / (tClose - tOpen))
     * (2) has less rounding error than (1), but then the *precise* effective beta used in the computation might not
     * have a uint256 representation.
     * Therefore some (miniscule) rounding precision is sacrificed to gain computation reproducibility.
     */
    function betaOf(VirtualMarket storage vm, uint256 t) internal view returns (UFixed256x18) {
        UFixed256x18 betaOpenMinusBetaClose = vm.betaOpenMinusBetaClose.toUFixed256x18();
        return _BETA_CLOSE.add(betaOpenMinusBetaClose.mul0(vm.tClose - t).div0(vm.tClose - vm.tOpen));
    }

    function totalCommitmentsToAllOutcomesPlusBonus(VirtualMarket storage vm) internal view returns (uint256 total) {
        total = vm.bonusAmount;
        for (uint256 i = 0; i < vm.nOutcomes; i++) {
            total += vm.outcomeTotals[i].amount;
        }
    }

    function minMaxCommitmentAmounts(VirtualMarket storage vm) internal view returns (uint256 min, uint256 max) {
        min = vm._optionalMinCommitmentAmount;
        max = vm._optionalMaxCommitmentAmount;
        if (min == 0) {
            min = _MIN_POSSIBLE_COMMITMENT_AMOUNT;
        }
        if (max == 0) {
            max = _MAX_POSSIBLE_COMMITMENT_AMOUNT;
        }
    }

    /**
     * @dev Equivalent to state == Active_Open_ResolvableLater || state == Active_Open_MaybeResolvableNever,
     * but ~300 gas cheaper.
     */
    function isOpen(VirtualMarket storage vm) internal view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return vm._internalState == VirtualMarketInternalState.Active && block.timestamp < vm.tClose;
    }

    function isClaimableRefunds(VirtualMarket storage vm) internal view returns (bool) {
        return vm._internalState == VirtualMarketInternalState.Claimable_Refunds_ResolvedNoWinners
            || vm._internalState == VirtualMarketInternalState.Claimable_Refunds_ResolvableNever
            || vm._internalState == VirtualMarketInternalState.Claimable_Refunds_Flagged;
    }

    function refundBonusAmount(VirtualMarket storage vm) internal {
        if (vm.bonusAmount > 0) {
            vm.paymentToken.safeTransfer(vm.creator, vm.bonusAmount);
        }
    }

}
