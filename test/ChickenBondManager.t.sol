// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/Token.sol";
import "../src/BondNFT.sol";
import "../src/BoostToken.sol";
import "../src/SimpleStrategy.sol";

import "../src/utils/BaseMath.sol";
import "../src/ChickenBondController.sol";
import "../src/ChickenBondManager.sol";
import "../src/Interfaces/IChickenBondManager.sol";

import "forge-std/Test.sol";

contract ChickenBondManagerTest is Test, BaseMath {
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
  uint256 targetAverageAgeSeconds = 1 days;
  uint256 initialAccrualParameter = 4217 seconds;
  uint256 minimumAccrualParameter = 0.1 days;
  uint256 accrualAdjustmentRate = 0.01 ether; // equeals to 1%
  uint256 accrualAdjustmentPeriodSeconds = 1 days;
  uint256 bootstrapPeriod = 1 hours;
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
      bootstrapPeriod: bootstrapPeriod,
      minBondAmount: minBondAmount
    });

    cb = new ChickenBondManager(params);
    boostToken = cb.boostToken();
    bondNFT.setChickenBondManager(address(cb));
    deployTime = block.timestamp;
  }

  function testDeployment() public {
    assertTrue(address(cb.token()) == address(token), "Token address check");
    assertTrue(address(cb.boostToken()) == address(boostToken), "Bond Token address check");
    assertTrue(address(cb.bondNFT()) == address(bondNFT), "NFT address check");
  }

  function testLockToken() public {
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    assertTrue(token.balanceOf(address(cb)) == amount, "Token balance check");
    checkBondData(bondId, amount, 0, uint64(block.timestamp), 0, uint8(IChickenBondManager.BondStatus.active));
    checkTreasury(amount, 0, 0);
  }

  function testLockBootstrapRevert() public {
    uint256 amount = 1 ether;
    mintAndApprove(amount);
    vm.expectRevert(bytes("ChickenBondManager: Must wait until bootstrap period is over"));
    cb.createBond(amount);
  }

  function testLockMinimumAmountRevert() public {
    uint256 amount = 0.9 ether;
    mintAndApprove(amount);
    skip(bootstrapPeriod);
    vm.expectRevert(bytes("ChickenBondManager: Minimum bond amount not reached"));
    cb.createBond(amount);
  }

  function testAccrualCurve() public {
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    skip(initialAccrualParameter);
    assertTrue(cb.calcAccruedAmount(bondId) == amount / 2);
  }

  function testBreakevenTimeUpper() public {
    uint256 premium = 1.1 ether;
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    uint256 redeemTime = (initialAccrualParameter * DECIMAL_PRECISION) / (premium - 1 ether);
    skip(redeemTime + 1);
    assertTrue((cb.calcAccruedAmount(bondId) * premium) / DECIMAL_PRECISION > 1 ether);
  }

  function testBreakevenTimeLower() public {
    uint256 premium = 1.1 ether;
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    uint256 redeemTime = (initialAccrualParameter * DECIMAL_PRECISION) / (premium - 1 ether);
    skip(redeemTime);
    assertTrue((cb.calcAccruedAmount(bondId) * premium) / DECIMAL_PRECISION < 1 ether);
  }

  function testChickenOut() public {
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    uint256 startTime = block.timestamp;
    uint256 timeSkip = 1 days;
    skip(timeSkip);

    cb.chickenOut(bondId);

    assertTrue(token.balanceOf(address(this)) == amount, "Token balance check");
    checkTreasury(0, 0, 0);
    checkBondData(
      bondId,
      amount,
      0,
      uint64(startTime),
      uint64(startTime + timeSkip),
      uint8(IChickenBondManager.BondStatus.chickenedOut)
    );
  }

  function testChickenIn() public {
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    uint256 startTime = block.timestamp;
    uint256 timeSkip = initialAccrualParameter;
    skip(timeSkip);

    cb.chickenIn(bondId);

    assertTrue(token.balanceOf(address(this)) == 0, "Token balance check");
    assertTrue(token.balanceOf(address(cb)) == amount, "Bond token cb balance check");
    assertTrue(boostToken.balanceOf(address(this)) == amount / 2, "Bond token this balance check");
    checkTreasury(0, amount / 2, amount / 2);
    checkBondData(
      bondId,
      amount,
      amount / 2,
      uint64(startTime),
      uint64(startTime + timeSkip),
      uint8(IChickenBondManager.BondStatus.chickenedIn)
    );
  }

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

  function mintAndApprove(uint256 amount) internal {
    token.mint(address(this), amount);
    token.approve(address(cb), amount);
  }

  function createBond(uint256 amount) internal returns (uint256 bondId) {
    mintAndApprove(amount);
    skip(bootstrapPeriod);
    bondId = cb.createBond(amount);
  }

  function checkTreasury(
    uint256 pending,
    uint256 reserve,
    uint256 exit
  ) internal {
    (uint256 _pending, uint256 _reserve, uint256 _exit) = cb.getTreasury();
    assertTrue(pending == _pending, "Pending bucket check");
    assertTrue(reserve == _reserve, "Reserve bucket check");
    assertTrue(exit == _exit, "Exit bucket check");
  }

  function checkBondData(
    uint256 bondId,
    uint256 bondAmount,
    uint256 claimedBoostAmount,
    uint64 startTime,
    uint64 endTime,
    uint8 status
  ) internal {
    (uint256 _lockedAmount, uint256 _claimedBondToken, uint64 _startTime, uint64 _endTime, uint8 _status) = cb
      .getBondData(bondId);
    assertTrue(_lockedAmount == bondAmount, "Check locekd amount");
    assertTrue(_claimedBondToken == claimedBoostAmount, "Check claimed createBond tokens");
    assertTrue(_startTime == startTime, "Check startTime");
    assertTrue(_endTime == endTime, "Check endTime");
    assertTrue(_status == status, "Check status");
  }
}
