// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

contract FeeGenerator {
  uint256 public collectedFees0;
  uint256 public collectedFees1;  
  
  uint256 public cumulativeFees0;
  uint256 public cumulativeFees1;

  uint256 public lastTimeStamp;
  uint256 public constant FEE_MULTIPLIER = 1e18;
  uint256 public constant RATIO = 2;

  constructor() {
    lastTimeStamp = block.timestamp;
  }

  function unclaimedFees() public view returns (uint256 amount0, uint256 amount1) {
    amount0 = ((block.timestamp - lastTimeStamp)) * FEE_MULTIPLIER; 
    amount1 = amount0 / RATIO;
  }

  function claim() external returns (uint256 claimedFee0, uint256 claimedFee1) {
    return _claim();
  }

  function _claim() internal returns (uint256 _claimedFee0, uint256 _claimedFee1) {
    
    (_claimedFee0, _claimedFee1) = unclaimedFees();
    cumulativeFees0 += _claimedFee0;
    cumulativeFees1 += _claimedFee1;
    lastTimeStamp = block.timestamp;
  }
}
