// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

/**
 * @title VM ids and ERC-1155 commitment-balance ids
 
 * @notice Logic for VirtualMarket (VM) ids, and for ERC-1155 token-ids
 * representing commitments on specific VM-outcome-timeslot combinations.
 * @dev Both VM ids and VM-outcome-timeslot ids are uint256.
 * The lower 5 bytes of a VM id are always 5 zero-bytes, so the 32 bytes of a VM id
 * always have the shape `VVVVVVVVVVVVVVVVVVVVVVVVVVV00000`.
 * An account that at (4-byte) timeslot `TTTT` commits a `n` ERC-20 token units
 * to a specific (1-byte) outcome index `I` of a VM with id `VVVVVVVVVVVVVVVVVVVVVVVVVVV00000`,
 * will in return be minted a balance of `n` units on the ERC-1155 token-id `VVVVVVVVVVVVVVVVVVVVVVVVVVVITTTT`.
 */
library ERC1155TokenIds {

    using SafeCastUpgradeable for uint256;

    /**
     * @dev The lower 5 bytes of a VM id must always be 0.
     */
    function isValidVirtualMarketId(uint256 value) internal pure returns (bool) {
        return value & 0xff_ff_ff_ff_ff == 0;
    }

    function extractVirtualMarketId(uint256 erc1155TokenId) internal pure returns (uint256) {
        return erc1155TokenId & ~uint256(0xff_ff_ff_ff_ff);
    }

    /**
     * @dev Destructure an ERC-1155 token-id `VVVVVVVVVVVVVVVVVVVVVVVVVVVITTTT` into its
     * `VVVVVVVVVVVVVVVVVVVVVVVVVVV00000`, `I` and `TTTT` components.
     */
    function destructure(
        uint256 erc1155TokenId
    ) internal pure returns (
        uint256 vmId,
        uint8 outcomeIndex,
        uint32 timeslot
    ) {
        vmId = erc1155TokenId & ~uint256(0xff_ff_ff_ff_ff);
        outcomeIndex = uint8((erc1155TokenId >> 32) & 0xff);
        timeslot = uint32(erc1155TokenId & 0xff_ff_ff_ff);
    }

    /**
     * @dev Assemble `VVVVVVVVVVVVVVVVVVVVVVVVVVV00000`, `I` and `TTTT` components
     * into an ERC-1155 token-id `VVVVVVVVVVVVVVVVVVVVVVVVVVVITTTT`.
     * This function should only be called with a valid VM-id.
     */
    function vmOutcomeTimeslotIdOf(
        uint256 validVirtualMarketId,
        uint8 outcomeIndex,
        uint256 timeslot
    )
        internal
        pure
        returns (uint256 tokenId)
    {
        // Since this function should always be called after the VM
        // has already been required to be in one of the non-None states,
        // and a VM can only be in a non-None state if it has a valid id,
        // then this assertion should never fail.
        assert(isValidVirtualMarketId(validVirtualMarketId));

        tokenId = uint256(bytes32(abi.encodePacked(
            bytes27(bytes32(validVirtualMarketId)), //   27 bytes
            outcomeIndex,                          // +  1 byte
            timeslot.toUint32()                    // +  4 bytes
        )));                                       // = 32 bytes
    }

}
