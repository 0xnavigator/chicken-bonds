// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./Interfaces/IChickenBondController.sol";

contract ChickenBondController is IChickenBondController {
  function updateRatio(
    uint256 pending,
    uint256 reserve,
    uint256 exit
  ) external {
    pending;
    reserve;
    exit;
  }

  function exitCheck() external view returns (bool) {}
}
