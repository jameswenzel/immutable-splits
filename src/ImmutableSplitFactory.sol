// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {Recipient} from "./Structs.sol";
import {ImmutableSplit} from "./ImmutableSplit.sol";
import {Create2ClonesWithImmutableArgs} from "create2-clones-with-immutable-args/Create2ClonesWithImmutableArgs.sol";
import {
    InvalidBps, InvalidTotalBps, RecipientsMustBeSortedByAscendingBpsAndAddress, AlreadyDeployed
} from "./Errors.sol";
import {IImmutableSplitFactory} from "./IImmutableSplitFactory.sol";

contract ImmutableSplitFactory is IImmutableSplitFactory {
    uint32 constant RECEIVE_HOOK_SELECTOR = 0x95a9ecf1;
    address public immutable IMMUTABLE_SPLIT_IMPLEMENTATION;
    mapping(bytes32 => address payable) internal deployedSplits;

    constructor(address _impl) {
        IMMUTABLE_SPLIT_IMPLEMENTATION = _impl;
    }

    event log_bytes(bytes);

    function createImmutableSplit(Recipient[] calldata recipients) external returns (address payable) {
        bytes32 recipientsHash = _getRecipientsHash(recipients);
        address deployedSplitAddress = deployedSplits[recipientsHash];
        if (deployedSplitAddress != address(0)) {
            revert AlreadyDeployed(deployedSplitAddress);
        }
        bytes memory data;
        ///@solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            // copy all calldata to memory, offset by one word, where we will store bytes length
            // (returndata here will return 0 for 1 gas cheaper than pushing 0 onto the stack)
            calldatacopy(add(ptr, 0x20), returndatasize(), calldatasize())
            // store the length of calldata in the first word by shift left by 32 bits
            // overwrite the selector in the following 4 bytes
            mstore(add(ptr, 4), or(shl(32, calldatasize()), RECEIVE_HOOK_SELECTOR))
            // set pointer to data
            data := ptr
            // update free memory pointer
            mstore(0x40, add(ptr, add(0x20, calldatasize())))
        }

        address payable split = Create2ClonesWithImmutableArgs.clone(IMMUTABLE_SPLIT_IMPLEMENTATION, data, bytes32(0));
        deployedSplits[recipientsHash] = split;
        return split;
    }

    function getDeployedImmutableSplitAddress(Recipient[] calldata recipients) public view returns (address) {
        return deployedSplits[_getRecipientsHash(recipients)];
    }

    function _getRecipientsHash(Recipient[] calldata recipients) internal pure returns (bytes32) {
        _validateBps(recipients);
        return keccak256(abi.encode(recipients));
    }

    function _validateBps(Recipient[] calldata recipients) internal pure {
        uint256 totalBps;
        uint256 lastBps;
        Recipient lastRecipient;
        unchecked {
            for (uint256 i; i < recipients.length; ++i) {
                Recipient recipient = recipients[i];
                if (Recipient.unwrap(recipient) <= Recipient.unwrap(lastRecipient)) {
                    revert RecipientsMustBeSortedByAscendingBpsAndAddress();
                }
                uint256 bps = recipient.bps();

                if (bps > 10000 || bps == 0) revert InvalidBps(bps);
                totalBps += bps;
                lastBps = bps;
                lastRecipient = recipient;
            }
        }
        if (totalBps != 10000) {
            revert InvalidTotalBps(totalBps);
        }
    }
}
