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
    uint256 accountedFees;
  }

  AccumulatedFees public af0;
  AccumulatedFees public af1;

  constructor() {}

  function updateRatio(
    uint256 pending,
    uint256 reserve,
    uint256 exit
  ) external {
    (uint unclaimedFees0, uint unclaimedFees1) = unclaimedFees();
    _updateRatio(pending, reserve, exit, unclaimedFees0, af0);
    _updateRatio(pending, reserve, exit, unclaimedFees1, af1);
  }

  function _updateRatio(
    uint256 pending,
    uint256 reserve,
    uint256 exit,
    uint256 unclaimedFees,
    AccumulatedFees storage af
  ) internal {
    if (unclaimedFees == af.accountedFees) return;

    uint256 fees = unclaimedFees - af.accountedFees;

    uint256 total = pending + reserve + exit;

    if (total == 0) return;

    af.accPending += (pending * fees) / total;
    af.accReserve += (reserve * fees) / total;
    af.accExit += (exit * fees) / total;

    af.accountedFees = unclaimedFees;
  }

  function distributeFees() external returns( uint256 stakingPool,
      uint256 stabilityPool,
      uint256 bootstrap,
      uint256 team) {
      (uint256 fee0, uint fee1)  = _claim();
      (stakingPool, stabilityPool, bootstrap, team ) = _distributeFees(af0, fee0);
      _distributeFees(af1, fee1);
  }

  function distributeBuckets() public returns (uint256 pendingBucket,
      uint256 reserveBucket,
      uint256 exitBucket) {
    (uint256 fee0, uint fee1)  = _claim();

  }

  function _distributeBuckets(AccumulatedFees storage _af, uint256 _fee)
    internal
    returns (
      uint256 pendingBucket,
      uint256 reserveBucket,
      uint256 exitBucket
    )
  {
    pendingBucket = _af.accPending - _af.accPendingDebt;
    reserveBucket = _af.accReserve - _af.accReserveDebt;
    exitBucket = _af.accExit - _af.accExitDebt;

    assert(pendingBucket + reserveBucket + exitBucket == _fee);

    _af.accPendingDebt += _af.accPending;
    _af.accReserveDebt += _af.accReserve;
    _af.accExitDebt += _af.accExit;

  }

  function _distributeFees(AccumulatedFees storage _af, uint _fee)
    internal
    returns (
      uint256 stakingPool,
      uint256 stabilityPool,
      uint256 bootstrap,
      uint256 team
    )
  {
    (uint256 pendingFee, uint256 reserveFee, uint256 exitFee) = _distributeBuckets(_af, _fee);

    stakingPool = ((pendingFee * 4) / 10) + reserveFee + exitFee;
    stabilityPool = ((pendingFee * 2) / 10);
    bootstrap = stabilityPool;
    team = stabilityPool;
  }

  function exitCheck() external view returns (bool) {}
}
