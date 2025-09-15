// SPDX-License-Identifier: no license

pragma solidity 0.8.12;


/**
 * @title Reserved storage slots
 
 */
contract ExtraStorageGap {

    /**
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[200] private __gap;

}
