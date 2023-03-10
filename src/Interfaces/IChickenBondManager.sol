// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface IChickenBondManager {
  struct DeployParams {
    address token;
    address bondNFT;
    address controller;
    uint256 targetAverageAgeSeconds; // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual
    uint256 initialAccrualParameter; // Initial value for `accrualParameter`
    uint256 minimumAccrualParameter; // Stop adjusting `accrualParameter` when this value is reached
    uint256 accrualAdjustmentRate; // `accrualParameter` is multiplied `1 - accrualAdjustmentRate` every time there's an adjustment
    uint256 accrualAdjustmentPeriodSeconds; // The duration of an adjustment period in seconds
    uint256 bootstrapPeriod; // Min duration of first chicken-in
    uint256 minBondAmount; // Minimum amount of Token that needs to be bonded
    uint256 lpPerUSD; // Amount of LP per USD that is minted on the 500 - 10000 Range Pool
    uint256 exitMaxSupply;
  }

  struct BondData {
    uint256 bondAmount;
    uint256 claimedBoostAmount;
    uint64 startTime;
    uint64 endTime; // Timestamp of chicken in/out event
    BondStatus status;
  }

  // Valid values for `status` returned by `getBondData()`
  enum BondStatus {
    nonExistent,
    active,
    chickenedOut,
    chickenedIn
  }

  function getBondData(uint256 _bondID)
    external
    view
    returns (
      uint256 bondAmount,
      uint256 claimedBoostAmount,
      uint64 startTime,
      uint64 endTime,
      uint8 status
    );

  function getTreasury()
    external
    view
    returns (
      uint256 pending,
      uint256 reserve,
      uint256 exi
    );
}
