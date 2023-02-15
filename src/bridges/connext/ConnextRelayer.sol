pragma solidity >=0.8.4;

import {IConnext} from "../../interfaces/connext/IConnext.sol";
import {IXReceiver} from "../../interfaces/connext/IXReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";

/**
 * @title ConnextRelayer
 * @notice 
 */
contract ConnextRelayer is IXReceiver {

  error UnsupportedAsset(address);

  // The connext contract deployed on the same domain as this contract
  IConnext public immutable Connext;
  IRollupProcessor public Rollup;

  constructor(IConnext _connext, IRollupProcessor _rollup) {
    Connext = _connext;
    Rollup = _rollup;

  }

  /** 
   * @notice The receiver function as required by the IXReceiver interface.
   * @dev The "callback" function for this example. Will be triggered after Pong xcalls back.
   */
  function xReceive(
    bytes32 ,
    uint256 _amount,
    address _asset,
    address ,
    uint32 ,
    bytes memory _callData
  ) external returns (bytes memory) {
        uint256 assetId = getAssetId(_asset);
        IERC20(_asset).approve(address(Rollup), type(uint256).max);
        Rollup.depositPendingFunds(
            assetId,
            _amount,
            address(this),
            bytes32(_callData)
        );
  }


  /**
     * @notice Gets the id a given `_asset`
     * @dev if `_asset` is not supported will revert with `UnsupportedAsset(_asset)`
            Take from RollupEncoder.sol
     * @param _asset The address of the asset to fetch id for
     * @return The id matching `_asset`
     */
    function getAssetId(address _asset) public view returns (uint256) {
        if (_asset == address(0)) {
            return 0;
        }
        uint256 length = Rollup.getSupportedAssetsLength();
        for (uint256 i = 1; i <= length; i++) {
            address fetched = Rollup.getSupportedAsset(i);
            if (fetched == _asset) {
                return i;
            }
        }
        revert UnsupportedAsset(_asset);
    }
}