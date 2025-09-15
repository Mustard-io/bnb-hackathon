// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

import "./Base.sol";
import "./library/Utils.sol";

error CreationQuotaExceeded();

/**
 * @title MarketCreationQuotas extension of Base contract
 
 * @notice This contract extends the Base contract to enforce VM-creation quotas for creators.
 * @dev Quota is temporarily decremented by 1 when creator creates a VM,
 * and quota is restored when VM goes back to a Claimable state.
 */
contract MarketCreationQuotas is Base {

    using Utils for uint256;

    function __MarketCreationQuotas_init(BaseInitParams calldata params) internal onlyInitializing {
        __Base_init(params);
    }

    mapping(address => uint256) public creationQuotas;

    /**
     * @dev Decrement creator quota once VM becomes Active.
     */
    function _onVirtualMarketCreation(VirtualMarketCreationParams calldata params) internal override virtual {
        address creator = getVirtualMarketCreator(params.vmId);
        if (creationQuotas[creator] == 0) revert CreationQuotaExceeded();
        unchecked {
            creationQuotas[creator] -= 1;
        }
    }

    /**
     * @dev Restore creator quota once Active VM becomes Claimable.
     */
    function _onVirtualMarketConclusion(uint256 vmId) internal override virtual {
        address creator = getVirtualMarketCreator(vmId);
        creationQuotas[creator] += 1;
    }

    struct QuotaAdjustment {
        address creator;
        int256 relativeAmount;
    }

    event CreationQuotaAdjustments(QuotaAdjustment[] adjustments);

    /**
     * @notice Operator: Adjust VM-creation quotas for multiple creators.
     */
    function adjustCreationQuotas(QuotaAdjustment[] calldata adjustments)
        external
    {
        for (uint256 i = 0; i < adjustments.length; i++) {
            QuotaAdjustment calldata adjustment = adjustments[i];
            creationQuotas[adjustment.creator] = creationQuotas[adjustment.creator].add(adjustment.relativeAmount);
        }
        emit CreationQuotaAdjustments(adjustments);
    }

    /**
     * @dev See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;

}
