// SPDX-License-Identifier: no license

pragma solidity 0.8.12;

/**
 * @title Mechanism to call diamond-inheritance root initializer just once.
 
 */
contract MultipleInheritanceOptimization {

    bool private _rootInitialized;

    /**
     * @dev Should be diamond-root's last declared modifier.
     * Ensures that diamond-root initializer is run only once.
     */
    modifier multipleInheritanceRootInitializer() {
        if (!_rootInitialized) {
            _rootInitialized = true;
            _;
        }
    }

    /**
     * @dev Should be diamond-leaf's last declared modifier.
     * Clears up the storage variable once it has served its purpose.
     */
    modifier multipleInheritanceLeafInitializer() {
        _;
        _rootInitialized = false;
    }

    /**
     * @dev See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
