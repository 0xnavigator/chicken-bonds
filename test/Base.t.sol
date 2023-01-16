// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/Token.sol";
import "../src/BondNFT.sol";
import "../src/BoostToken.sol";
import "../src/FeeGenerator.sol";

import "../src/utils/ChickenMath.sol";
import "../src/ChickenBondController.sol";
import "../src/ChickenBondManager.sol";
import "../src/Interfaces/IChickenBondManager.sol";

import "forge-std/Test.sol";

contract BaseTest is Test, ChickenMath {
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
  FeeGenerator fg;

  uint256 deployTime;

  // ChickenBond Parameters
  uint256 targetAverageAgeSeconds = 1 days;
  uint256 initialAccrualParameter = 4217 seconds;
  uint256 minimumAccrualParameter = 1 seconds;
  uint256 accrualAdjustmentRate = 0.01 ether; // equeals to 1%
  uint256 accrualAdjustmentPeriodSeconds = 1 days;
  uint256 bootstrapPeriod = 1 hours;
  uint256 lpPerUSD = vm.envUint("LP_PER_USD") * 1 ether;
  uint256 exitMaxSupply = vm.envUint("EXIT_MAX_SUPPLY") * 1 ether;
  uint256 minBondAmount = lpPerUSD;

  function setUp() public virtual {
    bondNFT = new BondNFT("BondNFT", "BNFT", 0);
    token = new Token("Token", "TKN");
    controller = new ChickenBondController();
    fg = new FeeGenerator();

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
      minBondAmount: minBondAmount,
      lpPerUSD: lpPerUSD,
      exitMaxSupply: exitMaxSupply
    });

    cb = new ChickenBondManager(params);
    boostToken = cb.boostToken();
    bondNFT.setChickenBondManager(address(cb));
    deployTime = block.timestamp;
  }

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
    assertTrue(_lockedAmount == bondAmount, "Check bond amount");
    assertTrue(_claimedBondToken == claimedBoostAmount, "Check claimed boosted tokens");
    assertTrue(_startTime == startTime, "Check startTime");
    assertTrue(_endTime == endTime, "Check endTime");
    assertTrue(_status == status, "Check status");
  }
}
