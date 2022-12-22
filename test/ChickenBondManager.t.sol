// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/Token.sol";
import "../src/BondNFT.sol";
import "../src/BoostToken.sol";
import "../src/SimpleStrategy.sol";

import "../src/ChickenBondController.sol";
import "../src/ChickenBondManager.sol";
import "../src/Interfaces/IChickenBondManager.sol";

import "forge-std/Test.sol";

contract ChickenBondManagerTest is Test {
  struct Treasury {
    uint256 pending;
    uint256 reserve;
    uint256 exit;
  }

  ChickenBondManager cb;
  Token token;
  BondNFT bondNFT;
  BoostToken boostToken;
  ChickenBondController controller;

  SimpleStrategy strategy;
  uint256 deployTime;

  // ChickenBond Parameters
  uint256 targetAverageAgeSeconds = 15 days;
  uint256 initialAccrualParameter = 4 days;
  uint256 minimumAccrualParameter = 1 days;
  uint256 accrualAdjustmentRate = 0.01 ether; // equeals to 1%
  uint256 accrualAdjustmentPeriodSeconds = 1 days;
  uint256 bootstrapPeriodChickenIn = 2 hours;
  uint256 bootstrapPeriodRedeem = 4 hours;
  uint256 minBondAmount = 1 ether;

  function setUp() public {
    bondNFT = new BondNFT("BondNFT", "BNFT", 0);
    strategy = new SimpleStrategy();
    token = new Token("Token", "TKN");
    controller = new ChickenBondController();

    IChickenBondManager.DeployParams memory params = IChickenBondManager.DeployParams({
      token: address(token),
      bondNFT: address(bondNFT),
      controller: address(controller),
      targetAverageAgeSeconds: targetAverageAgeSeconds,
      initialAccrualParameter: initialAccrualParameter,
      minimumAccrualParameter: minimumAccrualParameter,
      accrualAdjustmentRate: accrualAdjustmentRate, // equeals to 1%
      accrualAdjustmentPeriodSeconds: accrualAdjustmentPeriodSeconds,
      bootstrapPeriodChickenIn: bootstrapPeriodChickenIn,
      bootstrapPeriodRedeem: bootstrapPeriodRedeem,
      minBondAmount: minBondAmount
    });

    cb = new ChickenBondManager(params);
    boostToken = cb.boostToken();
    bondNFT.setChickenBondManager(address(cb));
    deployTime = block.timestamp;
  }

  // function testCompoundFees() public {
  //   skip(1 days);
  //   uint256 fees = ((block.timestamp - deployTime) / 1 days) * rangePoolProxy.strategy().FEE_MULTIPLIER();
  //   rangePoolProxy.compound();
  //   assertTrue(fees == token.balanceOf(address(cb)));
  // }

  // function testRangePoolProxy() public {
  //   uint256 amount = 10 ether;
  //   deposit(amount);
  //   uint256 currentBalance = token.balanceOf(address(this));
  //   assertTrue(amount == currentBalance, "balance match");
  //   withdraw(amount);
  //   assertTrue(token.balanceOf(address(this)) == currentBalance - amount, "balance match");
  // }

  // function testCreateBond() public {
  //   uint256 amount = 10 ether;
  //   uint256 bondId = createBond(amount);
  //   assertTrue(token.balanceOf(address(cb)) == amount, "LP balance check");
  //   checkBondData(bondId, amount, 0, uint64(block.timestamp), 0, uint8(IChickenBondManager.BondStatus.active));
  //   checkTreasury(amount, 0, 0);
  // }

  // function testChickenOut() public {
  //   uint256 amount = 10 ether;
  //   uint256 bondId = createBond(amount);
  //   uint256 startTime = block.timestamp;
  //   uint256 timeSkip = 1 days;
  //   skip(timeSkip);

  //   cb.chickenOut(bondId);

  //   assertTrue(token.balanceOf(address(this)) == amount, "LP balance check");
  //   checkTreasury(0, 0, 0);
  //   checkBondData(
  //     bondId,
  //     amount,
  //     0,
  //     uint64(startTime),
  //     uint64(startTime + timeSkip),
  //     uint8(IChickenBondManager.BondStatus.chickenedOut)
  //   );
  //   checkStakingRewards(0);
  // }

  // function testFirstChickenIn() public {
  //   uint256 amount = 10 ether;
  //   uint256 bondId = createBond(amount);
  //   uint256 startTime = block.timestamp;

  //   skip(initialAccrualParameter);

  //   uint256 btokenAccrued = cb.calcAccruedBoostToken(bondId);
  //   uint256 chickenInfee = ((chickenInAMMFee * amount) / 1e18);
  //   uint256 feeDiscountedAmount = amount - chickenInfee;
  //   uint256 expectedAccruedAmount = feeDiscountedAmount / 2;

  //   assertTrue(btokenAccrued == expectedAccruedAmount, "token half life");

  //   cb.chickenIn(bondId);

  //   checkTreasury(0, expectedAccruedAmount, amount - expectedAccruedAmount - chickenInfee);
  //   checkBondData(
  //     bondId,
  //     amount,
  //     uint64(btokenAccrued / 1e18),
  //     uint64(startTime),
  //     uint64(startTime + initialAccrualParameter),
  //     uint8(IChickenBondManager.BondStatus.chickenedIn)
  //   );
  //   checkStakingRewards(chickenInfee + strategy.cumulativeFees());
  // }

  // function testSecondChickenIn() public {
  //   uint256 amount = 10 ether;
  //   Treasury memory cacheTreasury;
  //   IChickenBondManager.BondData memory bondData;

  //   // First Bond
  //   {
  //     uint256 bond = createBond(amount);
  //     skip(1 days);
  //     cb.chickenIn(bond);
  //   }

  //   uint256 cacheBoostTokenBalance = boostToken.balanceOf(address(this));
  //   uint256 cacheAmmRewards = cb.ammStakingRewards();

  //   {
  //     (uint256 cachePending, uint256 cacheReserve, uint256 cacheExit) = cb.getTreasury();
  //     cacheTreasury.pending = cachePending;
  //     cacheTreasury.reserve = cacheReserve;
  //     cacheTreasury.exit = cacheExit;
  //   }

  //   // Second Bond
  //   bondData.startTime = uint64(block.timestamp);
  //   uint256 bondId = createBond(amount);
  //   skip(initialAccrualParameter);
  //   uint256 accruedFees = strategy.fees();
  //   uint256 accruedBoostTokens = cb.calcAccruedBoostToken(bondId);
  //   cb.chickenIn(bondId);

  //   uint256 chickenInfee = ((chickenInAMMFee * amount) / 1e18); // Rewards to AMM
  //   uint256 expectedBoostedAccruedAmount = (((amount - chickenInfee) / 2) * 1e18) / cb.calcSystemBackingRatio();

  //   assertTrue(
  //     boostToken.balanceOf(address(this)) == accruedBoostTokens + cacheBoostTokenBalance,
  //     "Boost token balance check"
  //   );
  //   assertTrue(accruedBoostTokens == expectedBoostedAccruedAmount, "Calculation of accrued boosted tokens");

  //   checkTreasury(
  //     0,
  //     (((amount - chickenInfee) / 2) + accruedFees + cacheTreasury.reserve),
  //     ((amount - chickenInfee) / 2) + cacheTreasury.exit
  //   );

  //   checkBondData(
  //     bondId,
  //     amount,
  //     uint64(expectedBoostedAccruedAmount / 1e18),
  //     uint64(bondData.startTime),
  //     uint64(bondData.startTime + initialAccrualParameter),
  //     uint8(IChickenBondManager.BondStatus.chickenedIn)
  //   );

  //   checkStakingRewards(cacheAmmRewards + chickenInfee);
  // }

  // function testRedeem() public {
  //   uint256 amount = 10 ether;
  //   uint256 bondId = createBond(amount);
  //   skip(initialAccrualParameter);
  //   cb.chickenIn(bondId);
  //   skip(1 days);
  //   uint256 accruedFees = strategy.fees();
  //   uint256 chickenInfee = ((chickenInAMMFee * amount) / 1e18); // Rewards to AMM
  //   uint256 expectedAccruedAmount = (amount - chickenInfee) / 2;
  //   cb.redeem(boostToken.balanceOf(address(this)));
  //   assertTrue(boostToken.balanceOf(address(this)) == 0, "boostToken balance check");
  //   assertTrue(token.balanceOf(address(this)) == expectedAccruedAmount + accruedFees, "LP balance check");
  //   checkTreasury(0, 0, expectedAccruedAmount);
  // }

  // function approve() public {
  //   token.approve(address(cb), type(uint256).max);
  // }

  // function deposit(uint256 amount) public {
  //   rangePoolProxy.deposit(amount);
  // }

  // function withdraw(uint256 amount) public {
  //   rangePoolProxy.withdraw(address(this), amount);
  // }

  // function createBond(uint256 amount) public returns (uint256 bondId) {
  //   deposit(amount);
  //   approve();
  //   bondId = cb.createBond(amount);
  // }

  // function checkTreasury(
  //   uint256 pending,
  //   uint256 reserve,
  //   uint256 exit
  // ) public {
  //   (uint256 _pending, uint256 _reserve, uint256 _exit) = cb.getTreasury();
  //   assertTrue(pending == _pending, "Pending bucket check");
  //   assertTrue(reserve == _reserve, "Reserve bucket check");
  //   assertTrue(exit == _exit, "Exit bucket check");
  // }

  // function checkBondData(
  //   uint256 bondId,
  //   uint256 bondedAmount,
  //   uint64 claimedBoostedToken,
  //   uint64 startTime,
  //   uint64 endTime,
  //   uint8 status
  // ) public {
  //   (uint256 _tokenAmount, uint64 _claimedBoostedToken, uint64 _startTime, uint64 _endTime, uint8 _status) = cb
  //     .getBondData(bondId);
  //   assertTrue(_tokenAmount == bondedAmount, "Check bondedAmount");
  //   assertTrue(_claimedBoostedToken == claimedBoostedToken, "Check claimedBoostedToken");
  //   assertTrue(_startTime == startTime, "Check startTime");
  //   assertTrue(_endTime == endTime, "Check endTime");
  //   assertTrue(_status == status, "Check status");
  // }

  // function checkStakingRewards(uint256 _stakingRewards) public {
  //   assertTrue(cb.ammStakingRewards() == _stakingRewards, "Staking rewards check");
  // }
}
