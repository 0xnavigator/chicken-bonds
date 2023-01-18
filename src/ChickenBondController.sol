// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./Interfaces/IChickenBondController.sol";

contract ChickenBondController {
  struct AccumulatedFees {
    uint256 accPending;
    uint256 accPendingDebt;
    uint256 accReserve;
    uint256 accReserveDebt;
    uint256 accExit;
    uint256 accExitDebt;
  }

  AccumulatedFees af;

  constructor() {}

  function updateRatio(
    uint256 pending,
    uint256 reserve,
    uint256 exit
  ) external {}

  function distributeFees() external returns (uint256) {}

  function exitCheck() external view returns (bool) {}
}
