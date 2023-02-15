// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IConnext} from "../../interfaces/connext/IConnext.sol";
import {AddressRegistry} from "../registry/AddressRegistry.sol";

/**
 * @title Connext L2 Bridge Contract
 * @author Nishay Madhani (@nshmadhani on Github, Telegram)
 * @notice You can use this contract to deposit funds into other L2's using connext
 * @dev  This Bridge is resposible for bridging funds from Aztec to L2 using Connext xCall.
 */
contract ConnextBridge is BridgeBase, Ownable{

    error InvalidDomainIndex();
    error InvalidConfiguration();
    error InvalidDomainID();

    IConnext public Connext;
    AddressRegistry public Registry;


    /// @dev The following masks are used to decode slippage(bps), destination domain, 
    ///       relayerfee bps and destination address from 1 uint64
    
    /// Binary number 11111 (last 5 bits) from LSB
    uint64 public constant DEST_DOMAIN_MASK = 0x1F;
    uint64 public constant DEST_DOMAIN_LENGTH = 5;

    /// Binary number 111111111111111111111111 (next 24 bits)
    uint64 public constant TO_MASK = 0xFFFFFF;
    uint64 public constant TO_MASK_LENGTH = 24;

    /// Binary number 1111111111 (next 10 bits)
    uint64 public constant SLIPPAGE_MASK = 0x3FF;
    uint64 public constant SLIPPAGE_LENGTH = 10;


    /// Binary number 11111111111111 (next 14 bits)
    uint64 public constant RELAYED_FEE_MASK = 0x3FFF;
    uint64 public constant RELAYED_FEE_LENGTH = 14;

    uint32 public domainCount;
    mapping(uint32 => uint32) public domains;

    uint256 public maxRelayerFee;



    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(
        address _rollupProcessor,
        address _connext,
        address _registry
    ) BridgeBase(_rollupProcessor) {
        Connext = IConnext(_connext);
        Registry = AddressRegistry(_registry);
        maxRelayerFee = 0.01 ether;
    }

    receive() external payable {}

    /**
     * @notice A function which returns an _totalInputValue amount of _inputAssetA
     * @param _inputAssetA - Arbitrary ERC20 token
     * @param _totalInputValue - amount of _inputAssetA to bridge
     * @param _auxData - contains domainDestination, recepient, slippage, relayerFee
     * @return outputValueA - the amount of output asset to return
     * @dev
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256,
            uint256,
            bool
        )
    {
        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) {
            revert ErrorLib.InvalidInputA();
        }

        uint256 relayerFee = getRelayerFee(_auxData, maxRelayerFee);

        _xTransfer(
            getDestinationAddress(_auxData),
            getDomainID(_auxData),
            _inputAssetA.erc20Address,
            _totalInputValue,
            getSlippage(_auxData),
            relayerFee
        );

        return (0, 0, false);
    }

    /**
     * @notice Add a new domain to the mapping
     * @param _domainIDs new domains to be added to the end of the mapping
     * @dev elements are included based on the domainCount variablle
     */
    function addDomains(uint32[] calldata _domainIDs) external onlyOwner {
        for (uint32 index = 0; index < _domainIDs.length; index++) {
            domains[domainCount] = _domainIDs[index];
            domainCount = domainCount + 1;
        }
    }

    /**
     * @notice Update domainIDs for each chain according to connext
     * @param _index index where domain is located in domains map
     * @param _newDomains new domainIDs
     * @dev 0th element in _index is key for 0th elemen in _newDomains for domains map
     */
    function updateDomains(
        uint32[] calldata _index,
        uint32[] calldata _newDomains
    ) external onlyOwner {
        if (_index.length != _newDomains.length) {
            revert InvalidConfiguration();
        }
        for (uint256 index = 0; index < _newDomains.length; index++) {
            if (_index[index] >= domainCount) {
                revert InvalidDomainIndex();
            }
            domains[_index[index]] = _newDomains[index];
        }
    }

    /**
     * @notice sets maxRelayerFee which can be paid during bridge
     * @dev Should be set according to min relayerFee connext will charge for L2s(can be lower than cent)
     */
    function setMaxRelayerFee(
        uint256 _maxRelayerFee
    ) external onlyOwner {
        maxRelayerFee = _maxRelayerFee;        
    }

    /**
     * @notice sets location for connext
     */
    function setConnext(
        address _newConnextAdrress
    ) external onlyOwner {
        Connext = IConnext(_newConnextAdrress);       
    }

    /**
     * @notice sets which address registry to use
     */
    function setAddressRegistry(
        address _addressRegistry
    ) external onlyOwner {
        Registry = AddressRegistry(_addressRegistry);
    }

    /**
     * @notice Transfers funds from one chain to another.
     * @param _recipient The destination address (e.g. a wallet).
     * @param _destinationDomain The destination domain ID.
     * @param _tokenAddress Address of the token to transfer.
     * @param _amount The amount to transfer.
     * @param _slippage The maximum amount of slippage the user will accept in BPS.
     * @param _relayerFee The fee offered to relayers. On testnet, this can be 0.
     */
    function _xTransfer(
        address _recipient,
        uint32 _destinationDomain,
        address _tokenAddress,
        uint256 _amount,
        uint256 _slippage,
        uint256 _relayerFee
    ) internal {
        IERC20(_tokenAddress).approve(address(Connext), _amount);
        Connext.xcall{value: _relayerFee}(
            _destinationDomain, // _destination: Domain ID of the destination chain
            _recipient, // _to: address receiving the funds on the destination
            _tokenAddress, // _asset: address of the token contract
            msg.sender, // _delegate: address that can revert or forceLocal on destination
            _amount, // _amount: amount of tokens to transfer
            _slippage, // _slippage: the maximum amount of slippage the user will accept in BPS
            "" // _callData: empty because we're only sending funds
        );
    }


    /**
     * @notice Get DomainID from auxillary data
     * @param _auxData auxData param passed to convert() function
     * @dev appplied bit masking to retrieve first x bits to get index.
     *      The maps the index to domains map
     */
    function getDomainID(uint64 _auxData)
        public
        view
        returns (uint32 domainID)
    {
        uint32 domainIndex = uint32(_auxData & DEST_DOMAIN_MASK);

        if (domainIndex >= domainCount) {
            revert InvalidDomainID();
        }

        domainID = domains[domainIndex];
    }

    /**
     * @notice Get destination address from auxillary data
     * @param _auxData auxData param passed to convert() function
     * @dev applies bit shifting to first remove bits used by domainID,
     *      appplied bit masking to retrieve first x bits to get index.
     *      The maps the index to AddressRegistry
     */
    function getDestinationAddress(uint64 _auxData)
        public
        view
        returns (address destination)
    {
        _auxData = _auxData >> DEST_DOMAIN_LENGTH;
        uint64 toAddressID = (_auxData & TO_MASK);
        destination = Registry.addresses(toAddressID);
    }

    /**
     * @notice Get slippage from auxData
     * @param _auxData auxData param passed to convert() function
     * @dev applies bit shifting to first remove bits used by domainID, toAddress
     *      appplied bit masking to retrieve first x bits to get index.
     *      The maps the index to AddressRegistry
     */
    function getSlippage(uint64 _auxData)
        public
        pure
        returns (uint64 slippage)
    {
        _auxData = _auxData >> (DEST_DOMAIN_LENGTH + TO_MASK_LENGTH);
        slippage = (_auxData & SLIPPAGE_MASK);
    }

    /**
     * @notice Get relayer fee from auxData
     * @param _auxData auxData param passed to convert() function
     * @dev applies bit shifting to first remove bits used by domainID, toAddress, slippage
     *      appplied bit masking to retrieve first x bits to get index.
     *      The maps the index to AddressRegistry
     */
    function getRelayerFee(uint64 _auxData, uint256 _maxRelayerFee)
        public
        pure
        returns (uint256 relayerFeeAmountsIn)
    {
        _auxData = _auxData >> (DEST_DOMAIN_LENGTH + TO_MASK_LENGTH + SLIPPAGE_LENGTH);
        uint256 relayerFeeBPS = (_auxData & RELAYED_FEE_MASK);
        if (relayerFeeBPS > 10_000) {
            relayerFeeBPS = 10_000;
        }
        relayerFeeAmountsIn = (relayerFeeBPS * _maxRelayerFee) / 10_000;
    }

}
