// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./Base.sol";


/**
 * @title MarketChallengerOracle extension of Base contract
 
 * @notice This contract extends the Base contract to allow VMs to be resolved by VM-creator,
 * and to subsequently allow that set result to be challenged by a member of the public.
 */
contract MarketChallengerOracle is Base {

    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using SafeCastUpgradeable for uint256;


    uint256 constant public CHALLENGE_BOND_USD_AMOUNT = 100;

    uint256 constant public SET_WINDOW_DURATION = 1 hours;

    uint256 constant public CHALLENGE_WINDOW_DURATION = 1 hours;


    enum ResolutionState {
        None,
        Set,
        Challenged,
        ChallengeCancelled,
        Complete
    }

    struct Resolution {
        ResolutionState state;
        uint8 setOutcomeIndex;
        uint32 tResultChallengeMax;
        uint8 challengeOutcomeIndex;
        address challenger;
    }


    IERC20MetadataUpgradeable private _bondUsdErc20Token;

    mapping(uint256 => Resolution) public resolutions;


    function __MarketChallengerOracle_init(
        BaseInitParams calldata baseParams,
        IERC20MetadataUpgradeable bondUsdErc20Token_
    )
        internal
        onlyInitializing
    {
        __Base_init(baseParams);
        _bondUsdErc20Token = bondUsdErc20Token_;
    }


    /**
     * @notice The ERC-20 token in which potential VM result challenger must place bond. Configured as USDC.
     */
    function bondUsdErc20Token() public view returns (IERC20MetadataUpgradeable) {
        return _bondUsdErc20Token;
    }

    function _bondAmount() private view returns (uint256) {
        return CHALLENGE_BOND_USD_AMOUNT * (10 ** _bondUsdErc20Token.decimals());
    }


    enum ResultUpdateAction {
        OperatorFinalizedUnsetResult,
        CreatorSetResult,
        SomeoneConfirmedUnchallengedResult,
        SomeoneChallengedSetResult,
        OperatorFinalizedChallenge
    }

    event ResultUpdate(
        uint256 indexed vmId,
        address operator,
        ResultUpdateAction action,
        uint8 outcomeIndex
    );

    /**
    * @notice VM resolution is in state `actualState`, but it must be in a different state to execute this action.
    */
    error WrongResolutionState(ResolutionState actualState);


    /**
     * @notice Operator: Set VM result if VM-creator has not set it within 1 hour of tResolve.
     * @dev No checks are made on whether finalOutcomeIndex is in-range,
     * or on whether underlying VM is in the ClosedResolvable state,
     * as Base._resolve call will fail anyway if requirements are not satisfied.
     */
    function finalizeUnsetResult(uint256 vmId, uint8 finalOutcomeIndex)
        external
        onlyRole(OPERATOR_ROLE)
    {
        Resolution storage resolution = resolutions[vmId];
        if (!(resolution.state == ResolutionState.None)) revert WrongResolutionState(resolution.state);
        CreatedVirtualMarketParams memory vmParams = getVirtualMarketParams(vmId);
        uint256 tResultSetMax = vmParams.tResolve + SET_WINDOW_DURATION;

        // CR-01: If block.timestamp is just a few seconds past tResultSetMax,
        // manipulating block.timestamp by a few seconds to be <= tResultSetMax
        // will cause this transaction to fail.
        // If that were to happen, this transaction could simply be reattempted later.
        // solhint-disable-next-line not-rely-on-time
        if (!(block.timestamp > tResultSetMax)) revert TooEarly();

        resolution.state = ResolutionState.Complete;
        emit ResultUpdate(vmId, _msgSender(), ResultUpdateAction.OperatorFinalizedUnsetResult, finalOutcomeIndex);

        // nonReentrant
        // Since finalizeUnsetResult is guarded by require(state == None)
        // and state has now been moved to Complete,
        // any external calls made by _resolve cannot re-enter finalizeUnsetResult.
        _resolve(vmId, finalOutcomeIndex, platformFeeBeneficiary());
    }

    /**
     * @notice VM creator: Set VM result within 1 hour of tResolve.
     * @dev No checks are made on whether finalOutcomeIndex is in-range,
     * or on whether underlying VM is in the ClosedResolvable state,
     * as Base._resolve call will fail anyway if requirements are not satisfied.
     */
    function setResult(uint256 vmId, uint8 setOutcomeIndex)
        external
        whenNotPaused
    {
        VirtualMarketState state = getVirtualMarketState(vmId);
        if (!(state == VirtualMarketState.Active_Closed_ResolvableNow)) revert WrongVirtualMarketState(state);
        CreatedVirtualMarketParams memory vmParams = getVirtualMarketParams(vmId);
        if (!(_msgSender() == vmParams.creator)) revert UnauthorizedMsgSender();
        Resolution storage resolution = resolutions[vmId];
        if (!(resolution.state == ResolutionState.None)) revert WrongResolutionState(resolution.state);
        uint256 tResultSetMax = vmParams.tResolve + SET_WINDOW_DURATION;

        // CR-01: If block.timestamp is at just a few seconds before tResultSetMax,
        // manipulating block.timestamp by a few seconds to be > tResultSetMax
        // will cause this transaction to fail.
        // In that were to happen, it would then become the contract admin's reponsibility
        // to set the result via finalizeUnsetResult.
        // solhint-disable-next-line not-rely-on-time
        if (!(block.timestamp <= tResultSetMax)) revert TooLate();

        if (!(setOutcomeIndex < vmParams.nOutcomes)) revert OutcomeIndexOutOfRange();

        // CR-01: Regardless of whether block.timestamp has been manipulated by a few seconds or not,
        // tResultChallengeMax will always be set to CHALLENGE_WINDOW_DURATION seconds later.
        // solhint-disable-next-line not-rely-on-time
        resolution.tResultChallengeMax = (block.timestamp + CHALLENGE_WINDOW_DURATION).toUint32();

        resolution.setOutcomeIndex = setOutcomeIndex;
        resolution.state = ResolutionState.Set;
        emit ResultUpdate(vmId, _msgSender(), ResultUpdateAction.CreatorSetResult, setOutcomeIndex);
    }

    /**
     * @notice Confirm a VM result that was set by VM-creator more than 1 hour ago,
     * and was not challenged by anyone.
     * @dev Callable by anyone.
     */
    function confirmUnchallengedResult(uint256 vmId)
        external
        whenNotPaused
    {
        Resolution storage resolution = resolutions[vmId];
        if (!(resolution.state == ResolutionState.Set)) revert WrongResolutionState(resolution.state);

        // CR-01: If block.timestamp is just a few seconds past tResultChallengeMax,
        // manipulating block.timestamp by a few seconds to be <= tResultChallengeMax
        // will cause this transaction to fail.
        // If that were to happen, this transaction could simply be reattempted later.
        // solhint-disable-next-line not-rely-on-time
        if (!(block.timestamp > resolution.tResultChallengeMax)) revert TooEarly();

        resolution.state = ResolutionState.Complete;
        address creatorFeeBeneficiary = getVirtualMarketCreator(vmId);
        emit ResultUpdate(vmId, _msgSender(), ResultUpdateAction.SomeoneConfirmedUnchallengedResult, resolution.setOutcomeIndex);

        // nonReentrant
        // Since confirmUnchallengedResult is guarded by require(state == Set)
        // and state has now been moved to Complete,
        // any external calls made by _resolve cannot re-enter confirmUnchallengedResult.
        _resolve(vmId, resolution.setOutcomeIndex, creatorFeeBeneficiary);
    }


    /**
     * @notice VM result cannot be challenged with the same outcome set by creator.
     */
    error ChallengeOutcomeIndexEqualToSet();

    /**
     * @notice Challenge a VM result that has been set by VM-creator,
     * but for which 1-hour challenge-period has not yet expired,
     * and set result has not been yet challenged by anyone else.
     * Caller must have pre-approved 100 USDC spending allowance to this contract,
     * and transaction will result in 100 USDC challenge-bond being transferred
     * from the caller to this contract.
     * Bond will be returned if challenge is correct,
     * or if VM ends up being cancelled because it is flagged.
     * @param vmId VM id
     * @param challengeOutcomeIndex 0-based index of VM outcome that is the correct result according to challenger.
     * Must be different than the the result set previously by VM-creator that is being challenged.
     * @dev Callable by anyone.
     */
    function challengeSetResult(uint256 vmId, uint8 challengeOutcomeIndex)
        external
        whenNotPaused
    {
        Resolution storage resolution = resolutions[vmId];
        if (!(resolution.state == ResolutionState.Set)) revert WrongResolutionState(resolution.state);
        CreatedVirtualMarketParams memory vmParams = getVirtualMarketParams(vmId);
        if (!(challengeOutcomeIndex < vmParams.nOutcomes)) revert OutcomeIndexOutOfRange();
        if (!(challengeOutcomeIndex != resolution.setOutcomeIndex)) revert ChallengeOutcomeIndexEqualToSet();

        // CR-01: If block.timestamp is at just a few seconds before tResultChallengeMax,
        // manipulating block.timestamp by a few seconds to be > tResultChallengeMax
        // will cause this transaction to fail.
        // If that were to happen, it would then become possible for the unchallenged result
        // to be confirmed via confirmUnchallengedResult, thus concluding the VM.
        // To protect against this scenario, CHALLENGE_WINDOW_DURATION is configured to be
        // much larger than the amount of time by which a miner could possibly manipulate block.timestamp.
        // solhint-disable-next-line not-rely-on-time
        if (!(block.timestamp <= resolution.tResultChallengeMax)) revert TooLate();

        resolution.challengeOutcomeIndex = challengeOutcomeIndex;
        resolution.challenger = _msgSender();
        resolution.state = ResolutionState.Challenged;
        emit ResultUpdate(vmId, _msgSender(), ResultUpdateAction.SomeoneChallengedSetResult, challengeOutcomeIndex);

        // nonReentrant
        // Since challengeSetResult is guarded by require(state == Set)
        // and state has now been moved to Challenged,
        // the following external safeTransferFrom call cannot re-enter challengeSetResult.
        _bondUsdErc20Token.safeTransferFrom(_msgSender(), address(this), _bondAmount());
    }


    /**
     * @notice Operator: Finalize VM result that has been challenged.
     * @param vmId VM id
     * @param finalOutcomeIndex 0-based index of correct VM outcome.
     */
    function finalizeChallenge(uint256 vmId, uint8 finalOutcomeIndex)
        external
        onlyRole(OPERATOR_ROLE)
    {
        Resolution storage resolution = resolutions[vmId];
        if (!(resolution.state == ResolutionState.Challenged)) revert WrongResolutionState(resolution.state);
        address creatorFeeBeneficiary;
        address challengeBondBeneficiary;
        if (finalOutcomeIndex == resolution.setOutcomeIndex) {
            // VM-owner proven correct
            creatorFeeBeneficiary = getVirtualMarketCreator(vmId);
            challengeBondBeneficiary = platformFeeBeneficiary();
        } else if (finalOutcomeIndex == resolution.challengeOutcomeIndex) {
            // Challenger proven correct
            creatorFeeBeneficiary = platformFeeBeneficiary();
            challengeBondBeneficiary = resolution.challenger;
        } else {
            // Neither VM-owner nor challenger were correct
            creatorFeeBeneficiary = platformFeeBeneficiary();
            challengeBondBeneficiary = platformFeeBeneficiary();
        }
        resolution.state = ResolutionState.Complete;
        emit ResultUpdate(vmId, _msgSender(), ResultUpdateAction.OperatorFinalizedChallenge, finalOutcomeIndex);

        // nonReentrant
        // Since finalizeChallenge is guarded by require(state == Challenged)
        // and state has now been moved to Complete,
        // the external safeTransfer call, as well as any external calls made by _resolve,
        // cannot re-enter finalizeChallenge.
        _bondUsdErc20Token.safeTransfer(challengeBondBeneficiary, _bondAmount());
        _resolve(vmId, finalOutcomeIndex, creatorFeeBeneficiary);
    }

    /**
     * @dev If the underlying VM has been cancelled after being flagged,
     * and a challenger had paid a challenge-bond, that bond will be refunded to the challenger.
     */
    function _onVirtualMarketConclusion(uint256 vmId) internal virtual override {
        if (getVirtualMarketState(vmId) == VirtualMarketState.Claimable_Refunds_Flagged) {
            Resolution storage resolution = resolutions[vmId];
            if (resolution.state == ResolutionState.Challenged) {
                resolution.state = ResolutionState.ChallengeCancelled;
                _bondUsdErc20Token.safeTransfer(resolution.challenger, _bondAmount());
            }
        }
    }

    /**
     * @dev See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
