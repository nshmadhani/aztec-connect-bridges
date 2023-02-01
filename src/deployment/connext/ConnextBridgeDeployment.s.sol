// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ConnextBridge} from "../../bridges/connext/ConnextBridge.sol";

contract ConnextBridgeDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying ConnextL2Bridge bridge");
        vm.broadcast();
        ConnextBridge bridge = new ConnextBridge(ROLLUP_PROCESSOR, 0x2b501381c6d6aFf9238526352b1c7560Aa35A7C5, 0xE592427A0AEce92De3Edee1F18E0157C05861564,address(0), tx.origin );
        emit log_named_address("Example bridge deployed to", address(bridge));
        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("ConnextL2Bridge bridge address id", addressId);
    }
}
