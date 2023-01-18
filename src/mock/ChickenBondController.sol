// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "../Interfaces/IChickenBondController.sol";
import "./FeeGenerator.sol";
import "forge-std/Test.sol";

contract ChickenBondController is FeeGenerator {
  struct AccumulatedFees {
    uint256 accPending;
    uint256 accReserve;
    uint256 accExit;
    uint256 accPendingDebt;
    uint256 accReserveDebt;
    uint256 accExitDebt;
  }

  uint256 accountedFees;
  AccumulatedFees public af;

  constructor() {}

  function updateRatio(
    uint256 pending,
    uint256 reserve,
    uint256 exit
  ) external {
    if (unclaimedFees() == accountedFees) return;

    uint256 fees = unclaimedFees() - accountedFees;

    uint256 total = pending + reserve + exit;

    if (total == 0) return;

    af.accPending += (pending * fees) / total;
    af.accReserve += (reserve * fees) / total;
    af.accExit += (exit * fees) / total;

    accountedFees = unclaimedFees();
  }

  function distributeBuckets()
    public
    returns (
      uint256 pendingBucket,
      uint256 reserveBucket,
      uint256 exitBucket
    )
  {
    uint256 fee = _claim();

    pendingBucket = af.accPending - af.accPendingDebt;
    reserveBucket = af.accReserve - af.accReserveDebt;
    exitBucket = af.accExit - af.accExitDebt;

    assert(pendingBucket + reserveBucket + exitBucket == fee);

    af.accPendingDebt += af.accPending;
    af.accReserveDebt += af.accReserve;
    af.accExitDebt += af.accExit;
  }

  function distributeFees()
    external
    returns (
      uint256 stakingPool,
      uint256 stabilityPool,
      uint256 bootstrap,
      uint256 team
    )
  {
    (uint256 pendingFee, uint256 reserveFee, uint256 exitFee) = distributeBuckets();

    stakingPool = ((pendingFee * 4) / 10) + reserveFee + exitFee;
    stabilityPool = ((pendingFee * 2) / 10);
    bootstrap = stabilityPool;
    team = stabilityPool;
  }

  function exitCheck() external view returns (bool) {}
}
