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
  }

  struct BondData {
    uint256 bondedAmount;
    uint64 claimedBoostedToken; // In unit amount without decimals
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
      uint256 bondedAmount,
      uint64 claimedBoostedToken,
      uint64 startTime,
      uint64 endTime,
      uint8 status
    );
}
