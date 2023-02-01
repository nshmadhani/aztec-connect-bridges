// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConnextBridge} from "../../../bridges/connext/ConnextBridge.sol";
import {AddressRegistry} from "../../../bridges/registry/AddressRegistry.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

/*
 * @notice The purpose of this test is to test the bridge in an environment that is as close to the final deployment
 *         as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
 */
contract ConnextBridgeE2ETest is BridgeTestBase {

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant CONNEXT = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6; //mainnet
    address private constant BENEFICIARY = address(11);
    address private constant OWNER = address(12);

    uint32 private constant MAINNET_ID = 6648936;
    uint32 private constant POLYGON_ID = 1886350457;
    

    address private rollupProcessor;

    AddressRegistry private addressRegistry;


    // The reference to the example bridge
    ConnextBridge private bridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    AztecTypes.AztecAsset private usdcAsset;

    function setUp() public {


        addressRegistry = new AddressRegistry(address(ROLLUP_PROCESSOR));


        // Deploy a new example bridge
        bridge = new ConnextBridge(address(ROLLUP_PROCESSOR), CONNEXT, 0xE592427A0AEce92De3Edee1F18E0157C05861564,address(addressRegistry), MULTI_SIG);

        // Use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "ConnextBridge");
        vm.label(USDC, "USDC");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 120k
        // WARNING: If you set this value too low the interaction will fail for seemingly no reason!
        // OTOH if you se it too high bridge users will pay too much
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 120000);

        // List USDC with a gasLimit of 100k
        // Note: necessary for assets which are not already registered on RollupProcessor
        // Call https://etherscan.io/address/0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455#readProxyContract#F25 to get
        // addresses of all the listed ERC20 tokens
        ROLLUP_PROCESSOR.setSupportedAsset(USDC, 100000);

        uint32[] memory domains = new uint32[](2);
        domains[0] = MAINNET_ID;
        domains[1] = POLYGON_ID;
        bridge.addDomains(domains);

        vm.stopPrank();

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        // Subsidize the bridge when used with USDC and register a beneficiary
        // usdcAsset = ROLLUP_ENCODER.getRealAztecAsset(USDC);
        // uint256 criteria = bridge.computeCriteria(usdcAsset, emptyAsset, usdcAsset, emptyAsset, 0);
        // uint32 gasPerMinute = 200;
        // SUBSIDY.subsidize{value: 1 ether}(address(bridge), criteria, gasPerMinute);

        // SUBSIDY.registerBeneficiary(BENEFICIARY);

        // // Set the rollupBeneficiary on BridgeTestBase so that it gets included in the proofData
        // ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);

    }

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testConnextBridgeE2ETest(address _destination,uint256 _depositAmount) public {
        vm.assume(address(this) != _destination && _destination != address(0));
        vm.assume(_depositAmount != 0 && _depositAmount < 10 * (10 ** 6)); //liquidity Caps
        vm.warp(block.timestamp + 1 days);

        // register address
        addressRegistry.registerAddress(_destination);

        // Mint the depositAmount of Dai to rollupProcessor
        deal(USDC, address(ROLLUP_PROCESSOR), _depositAmount);

        // Computes the encoded data for the specific bridge interaction

        uint64 auxData = 4950486679553;

        ROLLUP_ENCODER.defiInteractionL2(id, usdcAsset, emptyAsset, emptyAsset, emptyAsset, auxData, _depositAmount);

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();


    }
}
