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
    
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant CONNEXT = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6; //mainnet
    address private constant BENEFICIARY = address(11);
    address private constant OWNER = address(12);

    uint32 private constant GOERLI_ID = 1735353714;
    uint32 private constant MUMBAI_ID = 9991;
    

    address private rollupProcessor;

    AddressRegistry private addressRegistry;


    // The reference to the example bridge
    ConnextBridge private bridge;

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);
        
        addressRegistry = new AddressRegistry(rollupProcessor);

        // Deploy a new example bridge
        bridge = new ConnextBridge(rollupProcessor, CONNEXT, address(addressRegistry), address(this));

        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);
        vm.deal(OWNER, 0);

        vm.label(address(bridge), "Connext Bridge");

        // // Subsidize the bridge when used with Dai and register a beneficiary
        // AztecTypes.AztecAsset memory daiAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        // uint256 criteria = bridge.computeCriteria(daiAsset, emptyAsset, daiAsset, emptyAsset, 0);
        // uint32 gasPerMinute = 200;
        // SUBSIDY.subsidize{value: 1 ether}(address(bridge), criteria, gasPerMinute);

        // SUBSIDY.registerBeneficiary(BENEFICIARY);

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

    
    function testInvalidOwner(address _callerAddress) public {
        vm.assume(_callerAddress != address(this));
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.transferOwnership(_callerAddress);
    }
    
    function testTransferOwnership() public {
        bridge.transferOwnership(OWNER);
        assertEq(bridge.owner(), OWNER);
    }

    function testAddDomains(uint32  _domain0, uint32 _domain1) public  {
        uint32[] memory domains = new uint32[](2);
        domains[0] = _domain0;
        domains[1] = _domain1; 
        bridge.addDomains(domains);
        assertEq(bridge.domains(0), _domain0);
        assertEq(bridge.domains(1), _domain1);
        assertEq(bridge.domainCount(), 2);
    }

    function testInvalidUpdateDomains() public  {
        uint32[] memory index = new uint32[](2);
        uint32[] memory domains = new uint32[](2);

        index[0] = 0; domains[0] = GOERLI_ID;
        index[1] = 1; domains[1] = MUMBAI_ID;

        vm.expectRevert(ConnextBridge.InvalidDomainIndex.selector);        
        bridge.updateDomains(index,domains);
    }

    function testInvalidLengthUpdateDomains() public  {
        uint32[] memory index = new uint32[](1);
        uint32[] memory domains = new uint32[](2);

        domains[0] = GOERLI_ID;
        index[0] = 1; domains[1] = MUMBAI_ID;

        vm.expectRevert(ConnextBridge.InvalidConfiguration.selector);        
        bridge.updateDomains(index,domains);
    }

    function testAddAndUpdateDomainsFlow(uint32 _domain0, uint32 _domain1) public  {
        uint32[] memory domains = new uint32[](2);
        domains[0] = _domain0;
        domains[1] = _domain1;

        bridge.addDomains(domains);
        assertEq(bridge.domains(0), _domain0);
        assertEq(bridge.domains(1), _domain1);

        uint32[] memory index = new uint32[](2);
        
        index[0] = 1; domains[0] = GOERLI_ID;
        index[1] = 0; domains[1] = MUMBAI_ID;

        bridge.updateDomains(index,domains);
        assertEq(bridge.domains(1), GOERLI_ID);
        assertEq(bridge.domains(0), MUMBAI_ID);

    }
    

    function testInvalidDomainID() public {
        uint32[] memory domains = new uint32[](2);
        domains[0] = GOERLI_ID;
        domains[1] = MUMBAI_ID;
        bridge.addDomains(domains); // now the domains are at 0, 1 index
        vm.expectRevert(ConnextBridge.InvalidDomainID.selector);
        bridge.getDomainID(3);
    }

    function testGetDomainID() public {
        uint32[] memory domains = new uint32[](2);
        domains[0] = GOERLI_ID;
        domains[1] = MUMBAI_ID;        
        bridge.addDomains(domains); // now the domains are at 0, 1 index
        assertEq(bridge.getDomainID(0), GOERLI_ID);
        assertEq(bridge.getDomainID(1), MUMBAI_ID);
    }


    function testGetDestinationAddress(address _domain0, address _domain1) public {
        addressRegistry.registerAddress(_domain0);
        addressRegistry.registerAddress(_domain1);
        
        assertEq(bridge.getDestinationAddress(16), _domain0);
        assertEq(bridge.getDestinationAddress(32), _domain1);
    }

    function testGetSlippage(uint64 _slippage) public {
        vm.assume(_slippage >= 0 && _slippage <= 1024);       
        uint64 auxData =  _slippage << (bridge.TO_MASK_LENGTH() + bridge.DEST_DOMAIN_LENGTH());
        assertEq(bridge.getSlippage(auxData), _slippage);
    }

    function testGetRelayerFee(uint64 _relayerFee) public {
        vm.assume(_relayerFee >= 0 && _relayerFee <= (2 ** 20));       
        uint64 auxData =  _relayerFee << (bridge.TO_MASK_LENGTH() + bridge.DEST_DOMAIN_LENGTH() + bridge.SLIPPAGE_LENGTH());
        assertEq(bridge.getRelayerFee(auxData), _relayerFee);
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != rollupProcessor);
        // Use HEVM cheatcode to call from a different address than is address(this)
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidInputAssetType() public {
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testFullFlowUnit(address _destination) public {
        vm.assume(address(this) != _destination);
        addressRegistry.registerAddress(_destination);
    }

    function testFullFlowUnit(address _destination, uint256 _depositAmount) public {
        vm.warp(block.timestamp + 1 days);

        vm.assume(address(this) != _destination);
        addressRegistry.registerAddress(_destination);

        uint32[] memory domains = new uint32[](2);
        domains[0] = GOERLI_ID;
        domains[1] = MUMBAI_ID;        
        bridge.addDomains(domains); // now the domains are at 0, 1 index

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA =
            AztecTypes.AztecAsset({id: 1, erc20Address: DAI, assetType: AztecTypes.AztecAssetType.ERC20});


        // Rollup processor transfers ERC20 tokens to the bridge before calling convert. Since we are calling
        // bridge.convert(...) function directly we have to transfer the funds in the test on our own. In this case
        // we'll solve it by directly minting the _depositAmount of Dai to the bridge.
        deal(DAI, address(bridge), _depositAmount);

        // Store dai balance before interaction to be able to verify the balance after interaction is correct
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(rollupProcessor);

        uint64 auxData = 4950486679553;

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAssetA, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            emptyAsset, // _outputAssetA - not used so can be lefr emoty
            emptyAsset, // _outputAssetB - not used so can be left empty
            _depositAmount, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            auxData, // _auxData - not used in the example bridge
            BENEFICIARY // _rollupBeneficiary - address, the subsidy will be sent to
        );

    }
    //1001000000010100000000000000000000000000001






}
