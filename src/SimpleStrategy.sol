// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

contract SimpleStrategy {
  uint256 lastTimeStamp;
  uint256 public constant FEE_MULTIPLIER = 1e18;
  uint256 public cumulativeFees;

  constructor() {
    lastTimeStamp = block.timestamp;
  }

  function fees() public view returns (uint256) {
    return ((block.timestamp - lastTimeStamp) / 1 days) * FEE_MULTIPLIER;
  }

  function compound() external returns (uint256) {
    return _compound();
  }

  function _compound() internal returns (uint256 fee) {
    fee = fees();
    cumulativeFees += fee;
    lastTimeStamp = block.timestamp;
  }
}
