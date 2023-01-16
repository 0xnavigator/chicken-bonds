// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./Interfaces/IChickenBondController.sol";
import "./FeeGenerator.sol";

contract ChickenBondController is FeeGenerator {
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
  ) external {
    af.accPending += pending * unclaimedFees() - af.accPendingDebt;
    af.accReserve += reserve * unclaimedFees() - af.accReserveDebt;
    af.accExit += exit * unclaimedFees() - af.accExitDebt;
  }

  function distributeFees() external returns (uint256) {
    uint256 fee = _claim();
    af.accPendingDebt += af.accPending;
    af.accReserveDebt += af.accReserve;
    af.accExitDebt += af.accExit;
    return fee;
  }

  function exitCheck() external view returns (bool) {}
}
