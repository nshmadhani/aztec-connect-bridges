// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ConnextBridge} from "../../bridges/connext/ConnextBridge.sol";

contract ConnextBridgeDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying ConnextL2Bridge bridge");
        vm.broadcast();

        address registry = 0xb51A65A4d1EaB576C1Fc02c5F67055Bcfb15F1D9;
        ConnextBridge bridge = new ConnextBridge(
                                        ROLLUP_PROCESSOR, 
                                        0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6, 
                                        registry
                                    );


        emit log_named_address("ConnextL2Bridge bridge deployed to", address(bridge));
        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("ConnextL2Bridge bridge address id", addressId);
    }
}
