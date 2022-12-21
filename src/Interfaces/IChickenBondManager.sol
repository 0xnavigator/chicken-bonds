// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface IChickenBondManager {
  struct DeployAddresses {
    address bondNFT;
    address rangePoolProxy;
  }

  struct DeployParams {
    uint256 targetAverageAgeSeconds; // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual
    uint256 initialAccrualParameter; // Initial value for `accrualParameter`
    uint256 minimumAccrualParameter; // Stop adjusting `accrualParameter` when this value is reached
    uint256 accrualAdjustmentRate; // `accrualParameter` is multiplied `1 - accrualAdjustmentRate` every time there's an adjustment
    uint256 accrualAdjustmentPeriodSeconds; // The duration of an adjustment period in seconds
    uint256 chickenInAMMFee; // Fraction of bonded amount that is sent to Curve Liquidity Gauge to incentivize LUSD-bLUSD liquidity
    uint256 bootstrapPeriodChickenIn; // Min duration of first chicken-in
    uint256 bootstrapPeriodRedeem; // Redemption lock period after first chicken in
    uint256 minBoostTokenSupply; // Minimum amount of bond supply that must remain after a redemption
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

  function getTreasury()
    external
    view
    returns (
      uint256 pending,
      uint256 reserve,
      uint256 permanent
    );

  function calcAccruedBoostToken(uint256 _bondID) external view returns (uint256);

  function calcBondBoostCap(uint256 _bondID) external view returns (uint256);

  function calcSystemBackingRatio() external view returns (uint256);

  function createBond(uint256 _amountToBond) external returns (uint256);

  function createBondWithPermit(
    address owner,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint256);

  function chickenOut(uint256 _bondID) external;

  function chickenIn(uint256 _bondID) external;

  function redeem(uint256 amountToRedeem) external returns (uint256);
}
