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

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract ConnextBridgeTest is BridgeTestBase {
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant CONNEXT =
        0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6; //mainnet
    address private constant BENEFICIARY = address(11);
    address private constant OWNER = address(12);

    uint32 private constant MAINNET_ID = 6648936;
    uint32 private constant POLYGON_ID = 1886350457;

    address private rollupProcessor;

    AddressRegistry private addressRegistry;

    // The reference to the example bridge
    ConnextBridge private bridge;

    event XCalled();

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        addressRegistry = new AddressRegistry(rollupProcessor);

        // Deploy a new example bridge
        bridge = new ConnextBridge(
            rollupProcessor,
            CONNEXT,
            0xE592427A0AEce92De3Edee1F18E0157C05861564,
            address(addressRegistry)
        );

        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);
        vm.deal(OWNER, 0);
        vm.label(address(bridge), "Connext Bridge");
        vm.label(address(USDC), "USDC");

        // // Subsidize the bridge when used with Dai and register a beneficiary

        AztecTypes.AztecAsset memory usdcAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: USDC,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 criteria = bridge.computeCriteria(usdcAsset, emptyAsset, emptyAsset, emptyAsset, 0);
        uint32 gasPerMinute = 200;
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criteria, gasPerMinute);

        SUBSIDY.registerBeneficiary(BENEFICIARY);
    }

    /**
        TEST PLAN

        --convert--
        [*] onlyRollup is tested
        [*] Make sure the inputAssetA is ERC20
        [] _totalInputValue is amount of value transfered to contract
        [] domainID is a valid domain supporting the asset
        [] toAddressID is also valid
        [] slippage is valid 
        [] relayerFee is not null
        [] funds are approved by the user to bridge contrsct
        [] full flow with xCall event being called 
        
        --onlyOwner--
        [*] make sure gated functions revert with invalid caller 

        --transferOwnership--
        [*] owner changes

        --addDomain--
        [*] batch add of new domains

        --updateDomain--
        [*] batch update 
        [*] test inconsistent indexes
     */

    function testAddDomains(uint32 _domain0, uint32 _domain1) public {
        uint32[] memory domains = new uint32[](2);
        domains[0] = _domain0;
        domains[1] = _domain1;
        bridge.addDomains(domains);
        assertEq(bridge.domains(0), _domain0);
        assertEq(bridge.domains(1), _domain1);
        assertEq(bridge.domainCount(), 2);
    }

    function testInvalidUpdateDomains() public {
        uint32[] memory index = new uint32[](2);
        uint32[] memory domains = new uint32[](2);

        index[0] = 0;
        domains[0] = MAINNET_ID;
        index[1] = 1;
        domains[1] = POLYGON_ID;

        vm.expectRevert(ConnextBridge.InvalidDomainIndex.selector);
        bridge.updateDomains(index, domains);
    }

    function testInvalidLengthUpdateDomains() public {
        uint32[] memory index = new uint32[](1);
        uint32[] memory domains = new uint32[](2);

        domains[0] = MAINNET_ID;
        index[0] = 1;
        domains[1] = POLYGON_ID;

        vm.expectRevert(ConnextBridge.InvalidConfiguration.selector);
        bridge.updateDomains(index, domains);
    }

    function testAddAndUpdateDomainsFlow(uint32 _domain0, uint32 _domain1)
        public
    {
        uint32[] memory domains = new uint32[](2);
        domains[0] = _domain0;
        domains[1] = _domain1;

        bridge.addDomains(domains);
        assertEq(bridge.domains(0), _domain0);
        assertEq(bridge.domains(1), _domain1);

        uint32[] memory index = new uint32[](2);

        index[0] = 1;
        domains[0] = MAINNET_ID;
        index[1] = 0;
        domains[1] = POLYGON_ID;

        bridge.updateDomains(index, domains);
        assertEq(bridge.domains(1), MAINNET_ID);
        assertEq(bridge.domains(0), POLYGON_ID);
    }

    function testInvalidDomainID() public {
        uint32[] memory domains = new uint32[](2);
        domains[0] = MAINNET_ID;
        domains[1] = POLYGON_ID;
        bridge.addDomains(domains); // now the domains are at 0, 1 index
        vm.expectRevert(ConnextBridge.InvalidDomainID.selector);
        bridge.getDomainID(3);
    }

    function testGetDomainID() public {
        uint32[] memory domains = new uint32[](2);
        domains[0] = MAINNET_ID;
        domains[1] = POLYGON_ID;
        bridge.addDomains(domains); // now the domains are at 0, 1 index
        assertEq(bridge.getDomainID(0), MAINNET_ID);
        assertEq(bridge.getDomainID(1), POLYGON_ID);
    }

    function testGetDestinationAddress(address _domain0, address _domain1)
        public
    {
        addressRegistry.registerAddress(_domain0);
        addressRegistry.registerAddress(_domain1);

        assertEq(bridge.getDestinationAddress(16), _domain0);
        assertEq(bridge.getDestinationAddress(32), _domain1);
    }

    function testGetSlippage(uint64 _slippage) public {
        vm.assume(_slippage < 2**bridge.SLIPPAGE_LENGTH());
        uint64 auxData = _slippage <<
            (bridge.TO_MASK_LENGTH() + bridge.DEST_DOMAIN_LENGTH());
        assertEq(bridge.getSlippage(auxData), _slippage);
    }

    function testGetRelayerFee(uint64 _relayerFee) public {
        vm.assume(_relayerFee <= 10_000);

        uint64 auxData = _relayerFee <<
            (bridge.TO_MASK_LENGTH() +
                bridge.DEST_DOMAIN_LENGTH() +
                bridge.SLIPPAGE_LENGTH());

        assertEq(bridge.getRelayerFee(auxData, 10_000), _relayerFee);
    }
    //relayeFee allows upto 2^14 but capped at 10K
    function testGetRelayerFeeMorethan10K(uint64 _relayerFee) public {
        vm.assume(_relayerFee > 10_000 && _relayerFee <= (2 ** bridge.RELAYED_FEE_LENGTH() - 1));

        uint64 auxData = _relayerFee <<
            (bridge.TO_MASK_LENGTH() +
                bridge.DEST_DOMAIN_LENGTH() +
                bridge.SLIPPAGE_LENGTH());

        assertEq(bridge.getRelayerFee(auxData, 10_000), 10_000);
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != rollupProcessor);
        // Use HEVM cheatcode to call from a different address than is address(this)
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(
            emptyAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            address(0)
        );
    }

    function testInvalidInputAssetType() public {
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(
            emptyAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            address(0)
        );
    }

    function testFullFlowUnit(address _destination, uint256 _depositAmount)
        public
    {
        vm.assume(address(this) != _destination && _destination != address(0));
        vm.assume(_depositAmount >= 100_000 && _depositAmount < 10 * (10**6));

        addressRegistry.registerAddress(_destination);

        uint32[] memory domains = new uint32[](2);
        domains[0] = MAINNET_ID;
        domains[1] = POLYGON_ID;
        bridge.addDomains(domains); // now the domains are at 0, 1 index

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: USDC,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // Rollup processor transfers ERC20 tokens to the bridge before calling convert. Since we are calling
        // bridge.convert(...) function directly we have to transfer the funds in the test on our own. In this case
        // we'll solve it by directly minting the _depositAmount of Dai to the bridge.
        deal(USDC, address(bridge), _depositAmount);

        // Store dai balance before interaction to be able to verify the balance after interaction is correct

        //relayerFee = 00001111101000(1000 bps)(10%)
        //slippage=0000000101(5 bps)
        //TO_INDEX=000000000000000000000000(0)
        //DOMAIN_ID=00001(1)
        //1111101000000000010100000000000000000000000000001(549758498242561)

        uint64 auxData = 549758498242561;

        bridge.convert(
            inputAssetA, // _inputAssetA - definition of an input assets
            emptyAsset, // _inputAssetB - not used so can be left empty
            emptyAsset, // _outputAssetA - not used so can be lefr emoty
            emptyAsset, // _outputAssetB - not used so can be left empty
            _depositAmount, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            auxData,
            BENEFICIARY // _rollupBeneficiary - address, the subsidy will be sent to
        );
    }
}
