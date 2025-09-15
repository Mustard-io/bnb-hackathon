// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

import "./MarketChallengerOracle.sol";
import "./MarketCreationQuotas.sol";
import "./MarketMetadataValidator.sol";

/**
 * @title MarketCreatorManager protocol contract
 
 * @notice Enables accounts to commit an amount of ERC-20 tokens to a prediction that a specific future event,
 * or VirtualMarket (VM), resolves to a specific outcome from a predefined list of 2 or more mutually-exclusive
 * possible outcomes.
 * Users committing funds to a specific VM outcome at a specific timepoint are issued with a commitment receipt
 * in the form of a ERC-1155 commitment-balance.
 * If a VM is resolved to a winning outcome and winner profits are available, the commitment-balance may be redeemed
 * by its holder for the corresponding share of the profit.
 * @dev Merges all the multiple Base contract extensions into one final contract.
 */
contract MarketCreatorManager is
    MarketChallengerOracle,
    MarketCreationQuotas,
    MarketMetadataValidator
{

    function initialize(
        BaseInitParams calldata params,
        IERC20MetadataUpgradeable bondUsdErc20Token_
    )
        external
        initializer
        multipleInheritanceLeafInitializer
    {
        __MarketChallengerOracle_init(params, bondUsdErc20Token_);
        __MarketMetadataValidator_init(params);
        __MarketCreationQuotas_init(params);
    }

    function _onVirtualMarketCreation(VirtualMarketCreationParams calldata params)
        internal override(Base, MarketMetadataValidator, MarketCreationQuotas)
    {
        MarketCreationQuotas._onVirtualMarketCreation(params);
        MarketMetadataValidator._onVirtualMarketCreation(params);
    }

    function _onVirtualMarketConclusion(uint256 vmId)
        internal override(Base, MarketChallengerOracle, MarketCreationQuotas)
    {
        MarketChallengerOracle._onVirtualMarketConclusion(vmId);
        MarketCreationQuotas._onVirtualMarketConclusion(vmId);
    }

}
