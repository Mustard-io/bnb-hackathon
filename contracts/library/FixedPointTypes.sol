// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";


/**
 * @dev Holds range [0.000000, 4294.967295]
 */
type UFixed32x6 is uint32;

/**
 * @dev Holds range [0.0000, 6.5535]
 */
type UFixed16x4 is uint16;

/**
 * @dev Holds range
 * [000000000000000000000000000000000000000000000000000000000000.000000000000000000,
 * 115792089237316195423570985008687907853269984665640564039457.584007913129639935]
 */
type UFixed256x18 is uint256;


/**
 * @dev The value 1.000000000000000000
 */
UFixed256x18 constant UFIXED256X18_ONE = UFixed256x18.wrap(1e18);


/**
 * @title Generic fixed-point type arithmetic and safe-casting functions
 
 * @dev The primary fixed-point type in this library is UFixed256x18,
 * but some conversions to/from UFixed32x6 and UFixed16x4 are also provided,
 * as these are used in the main contract.
 */
library FixedPointTypes {

    using SafeCastUpgradeable for uint256;
    using FixedPointTypes for UFixed16x4;
    using FixedPointTypes for UFixed32x6;
    using FixedPointTypes for UFixed256x18;

    function add(UFixed256x18 a, UFixed256x18 b) internal pure returns (UFixed256x18) {
        return UFixed256x18.wrap(UFixed256x18.unwrap(a) + UFixed256x18.unwrap(b));
    }

    function sub(UFixed256x18 a, UFixed256x18 b) internal pure returns (UFixed256x18) {
        return UFixed256x18.wrap(UFixed256x18.unwrap(a) - UFixed256x18.unwrap(b));
    }

    /**
     * @dev e.g. 1.230000_000000_000000 * 3 = 3.690000_000000_000000
     * Named `mul0` because unlike `add` and `sub`, `b` is `UFixed256x0`, not `UFixed256x18`
     */
    function mul0(UFixed256x18 a, uint256 b) internal pure returns (UFixed256x18) {
        return UFixed256x18.wrap(UFixed256x18.unwrap(a) * b);
    }

    function div0(UFixed256x18 a, uint256 b) internal pure returns (UFixed256x18) {
        return UFixed256x18.wrap(UFixed256x18.unwrap(a) / b);
    }

    /**
     * @dev More efficient implementation of (hypothetical) `value.div(b).toUint256()`
     * e.g. 200.000000_000000_000000 / 3.000000_000000_000000 = 33
     */
    function divToUint256(UFixed256x18 a, UFixed256x18 b) internal pure returns (uint256) {
        return UFixed256x18.unwrap(a) / UFixed256x18.unwrap(b);
    }

    /**
     * @dev More efficient implementation of (hypothetical) `value.floor().toUint256()`
     * e.g. 987.654321_000000_000000 => 987
     */
    function floorToUint256(UFixed256x18 value) internal pure returns (uint256) {
        return UFixed256x18.unwrap(value) / 1e18;
    }

    function eq(UFixed256x18 a, UFixed256x18 b) internal pure returns (bool) {
        return UFixed256x18.unwrap(a) == UFixed256x18.unwrap(b);
    }

    function gte(UFixed256x18 a, UFixed256x18 b) internal pure returns (bool) {
        return UFixed256x18.unwrap(a) >= UFixed256x18.unwrap(b);
    }

    function lte(UFixed256x18 a, UFixed256x18 b) internal pure returns (bool) {
        return UFixed256x18.unwrap(a) <= UFixed256x18.unwrap(b);
    }


     /**
      * @notice Cannot convert UFixed256x18 `value` to UFixed16x4 without losing precision
      */
    error UFixed16x4LossOfPrecision(UFixed256x18 value);

    /**
     * @notice e.g. 1.234500_000000_000000 => 1.2345
     * Reverts if input is too large to fit in output-type,
     * or if conversion would lose precision, e.g. 1.234560_000000_000000 will revert.
     */
    function toUFixed16x4(UFixed256x18 value) internal pure returns (UFixed16x4 converted) {
        converted = UFixed16x4.wrap((UFixed256x18.unwrap(value) / 1e14).toUint16());
        if (!(converted.toUFixed256x18().eq(value))) revert UFixed16x4LossOfPrecision(value);
    }


    /**
     * @notice Cannot convert UFixed256x18 `value` to UFixed32x6 without losing precision
     */
    error UFixed32x6LossOfPrecision(UFixed256x18 value);

    /**
     * @notice e.g. 123.456789_000000_000000 => 123.456789
     * Reverts if input is too large to fit in output-type,
     * or if conversion would lose precision, e.g. 123.456789_100000_000000 will revert.
     */
    function toUFixed32x6(UFixed256x18 value) internal pure returns (UFixed32x6 converted) {
        converted = UFixed32x6.wrap((UFixed256x18.unwrap(value) / 1e12).toUint32());
        if (!(converted.toUFixed256x18().eq(value))) revert UFixed32x6LossOfPrecision(value);
    }


    /**
     * @notice e.g. 123 => 123.000000_000000_000000
     * Reverts if input is too large to fit in output-type.
     */
    function toUFixed256x18(uint256 value) internal pure returns (UFixed256x18) {
        return UFixed256x18.wrap(value * 1e18);
    }

    /**
     * @notice e.g. 1.2345 => 1.234500_000000_000000
     * Input always fits in output-type.
     */
    function toUFixed256x18(UFixed16x4 value) internal pure returns (UFixed256x18 converted) {
        unchecked { // because type(uint16).max * 1e14 <= type(uint256).max
            return UFixed256x18.wrap(uint256(UFixed16x4.unwrap(value)) * 1e14);
        }
    }

    /**
     * @notice e.g. 123.456789 => 123.456789_000000_000000
     * Input always fits in output-type.
     */
    function toUFixed256x18(UFixed32x6 value) internal pure returns (UFixed256x18 converted) {
        unchecked { // because type(uint32).max * 1e12 <= type(uint256).max
            return UFixed256x18.wrap(uint256(UFixed32x6.unwrap(value)) * 1e12);
        }
    }

}