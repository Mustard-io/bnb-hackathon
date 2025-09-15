// SPDX-License-Identifier: no license

pragma solidity 0.8.12;


/**
 * @title Generic utility functions
 
 */
library Utils {

    /**
     * @notice `value` doesn't fit in 192 bits
     */
    error TooLargeForUint192(uint256 value);

    function toUint192(uint256 value) internal pure returns (uint192) {
        if (!(value <= type(uint192).max)) revert TooLargeForUint192(value);
        return uint192(value);
    }


    function isEmpty(string memory value) internal pure returns (bool) {
        return bytes(value).length == 0;
    }


    /**
     * @dev Addition of a signed int256 to an unsigned uint256, returning a unsigned uint256,
     * (implicitly) checked for over/underflow.
     */
    function add(uint256 a, int256 b) internal pure returns (uint256) {
        if (b >= 0) {
            return a + uint256(b);
        } else {
            return a - uint256(-b);
        }
    }

}
