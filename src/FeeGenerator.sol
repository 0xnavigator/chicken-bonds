// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

contract FeeGenerator {
  uint256 lastTimeStamp;
  uint256 public constant FEE_MULTIPLIER = 1e18;
  uint256 public cumulativeFees;

  constructor() {
    lastTimeStamp = block.timestamp;
  }

  function unclaimedFees() public view returns (uint256) {
    return ((block.timestamp - lastTimeStamp)) * FEE_MULTIPLIER;
  }

  function claim() external returns (uint256) {
    return _claim();
  }

  function _claim() internal returns (uint256 fee) {
    fee = unclaimedFees();
    cumulativeFees += fee;
    lastTimeStamp = block.timestamp;
  }
}
