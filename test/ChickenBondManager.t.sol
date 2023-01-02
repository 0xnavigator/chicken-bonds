// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";

contract ChickenBondManagerTest is BaseTest {
  function testDeployment() public {
    assertTrue(address(cb.token()) == address(token), "Token address check");
    assertTrue(address(cb.boostToken()) == address(boostToken), "Boost Token address check");
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
    assertTrue(token.balanceOf(address(cb)) == amount, "Boost token cb balance check");
    assertTrue(boostToken.balanceOf(address(this)) == amount / 2, "Boost token this balance check");
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

  function testRedeem() public {
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    uint256 timeSkip = initialAccrualParameter;
    skip(timeSkip);
    cb.chickenIn(bondId);
    cb.redeem(boostToken.balanceOf(address(this)));
    assertTrue(boostToken.balanceOf(address(this)) == 0, "Boost token balance check");
    assertTrue(token.balanceOf(address(this)) == 1 ether / 2, "Token balance check");
    checkTreasury(0, 0, 1 ether / 2);
  }

  function testRedeemRevert() public {
    uint256 amount = 1 ether;
    uint256 bondId = createBond(amount);
    uint256 timeSkip = initialAccrualParameter;
    skip(timeSkip);
    cb.chickenIn(bondId);
    vm.expectRevert(bytes("ChickenBondManager: You do not own enough bond tokens"));
    cb.redeem(1 ether);
  }

  function testAccrualParameterUpdate() public {
    uint256 amount = 1 ether;
    uint256 numberOfAdjustments = 10;
    uint256 bondId = createBond(amount);
    uint256 timeSkip = accrualAdjustmentPeriodSeconds * numberOfAdjustments;
    skip(timeSkip);
    uint256 accrualAdjustmentMultiplier = 1e18 - accrualAdjustmentRate;
    uint256 expectedUpdatedAccuralParamterer = (initialAccrualParameter *
      DECIMAL_PRECISION *
      decPow(accrualAdjustmentMultiplier, (numberOfAdjustments - 1))) / 1e18;
    cb.chickenOut(bondId);
    assertTrue(expectedUpdatedAccuralParamterer == cb.accrualParameter(), "Accrual Parameter Check");
  }
}
