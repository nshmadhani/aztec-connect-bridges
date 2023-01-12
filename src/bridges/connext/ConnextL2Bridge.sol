// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
contract ConnextL2Bridge is BridgeBase {
    IConnext public immutable connext;

    AddressRegistry public registry;

    uint64 public constant DEST_DOMAIN_LENGTH = 5;
    uint64 public constant TO_MASK_LENGTH = 24;
    uint64 public constant SLIPPAGE_LENGTH = 10;
    uint64 public constant RELAYED_FEE_LENGTH = 20;

    /// @dev The following masks are used to decode slippage, destination domain, relayerfee multiplier and destination address from 1 uint64
    // Binary number 11111 (last 5 bits)
    uint64 public constant DEST_DOMAIN_MASK = 0x1F;

    // Binary number 111111111111111111111111 (last 24 bits)
    uint64 public constant TO_MASK = 0xFFFFFF;

    // Binary number 1111111111 (last 10 bits)
    uint64 public constant SLIPPAGE_MASK = 0x3FF;

    // Binary number 11111111111111111111 (last 20 bits)
    uint64 public constant RELAYED_FEE_MASK = 0xFFFFF;

    uint64 public domainCount;

    mapping(uint64 => uint32) public domains;

    address public owner;

    modifier onlyOwner() {
        require(owner == msg.sender, "onlOwner");
        _;
    }

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(
        address _rollupProcessor,
        address _connext,
        address _registry,
        address _onwer
    ) BridgeBase(_rollupProcessor) {
        connext = IConnext(_connext);
        registry = AddressRegistry(_registry);
        owner = _onwer;
    }

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
        require(
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20,
            ErrorLib.InvalidInputA()
        );

        address tokenAddress = _inputAssetA.erc20Address;
        uint256 amount = _totalInputValue;

        uint64 domainID = _auxData & DEST_DOMAIN_MASK;
        uint64 toAddressID = (_auxData >> DEST_DOMAIN_MASK) & TO_MASK;
        uint64 slippageAndFee = ((_auxData >> DEST_DOMAIN_MASK) >>
            TO_MASK_LENGTH);

        _xTransfer(
            registry.addresses(toAddressID),
            domains[domainID],”
            tokenAddress,
            amount,
            slippageAndFee & SLIPPAGE_MASK,
            (slippageAndFee >> SLIPPAGE_LENGTH) & RELAYED_FEE_MASK
        );
    }

    function transferOwnership(address _owner) external onlyOwner {
        owner = _owner;
    }

    function addDomain(uint32[] calldata _domainIDs) external onlyOwner {
        for (uint64 index = 0; index < _domainIDs.length; index++) {
            domains[domainCount] = _domainIDs[index];
            domainCount = domainCount + 1;
        }
    }

    function updateDomain(
        uint64[] calldata _index,
        uint32[] calldata _newDomains
    ) external onlyOwner {
        require(_index.length == _newDomains.length, "inconisten values");
        for (uint64 index = 0; index < _newDomains.length; index++) {
            domains[_index[index]] = _newDomains[index];
        }
    }

    /**
     * @notice Transfers funds from one chain to another.
     * @param recipient The destination address (e.g. a wallet).
     * @param destinationDomain The destination domain ID.
     * @param tokenAddress Address of the token to transfer.
     * @param amount The amount to transfer.
     * @param slippage The maximum amount of slippage the user will accept in BPS.
     * @param relayerFee The fee offered to relayers. On testnet, this can be 0.
     */
    function _xTransfer(
        address recipient,
        uint32 destinationDomain,
        address tokenAddress,
        uint256 amount,
        uint256 slippage,
        uint256 relayerFee
    ) internal {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "User must approve amount"
        );
        // User sends funds to this contract
        token.transferFrom(msg.sender, address(this), amount);
        // This contract approves transfer to Connext
        token.approve(address(connext), amount);
        connext.xcall{value: relayerFee}(
            destinationDomain, // _destination: Domain ID of the destination chain
            recipient, // _to: address receiving the funds on the destination
            tokenAddress, // _asset: address of the token contract
            msg.sender, // _delegate: address that can revert or forceLocal on destination
            amount, // _amount: amount of tokens to transfer
            slippage, // _slippage: the maximum amount of slippage the user will accept in BPS
            "" // _callData: empty because we're only sending funds
        );
    }
}
