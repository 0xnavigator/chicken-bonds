// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";

contract ChickenBondControllerTest is BaseTest {
  struct Fees {
    uint256 pending;
    uint256 reserve;
    uint256 exit;
    uint256 accountedFees;
  }

  Fees fees;

  function setUp() public virtual override {
    super.setUp();
    _resertFees();
  }

  function testAccumulatedAmounts() public {
    uint256 pendingAmount = 1 ether;
    uint256 reserveAmount = pendingAmount * 2;
    uint256 exitAmount = pendingAmount / 2;
    uint256 timeSkip = 10 seconds;

    uint256 lastTimeStamp = block.timestamp;
    skip(timeSkip);

    controller.updateRatio(pendingAmount, reserveAmount, exitAmount);
    (uint256 accPending, uint256 accReserve, uint256 accExit, , , ) = controller.af();
    uint256 total = pendingAmount + reserveAmount + exitAmount;
    assertTrue(
      accPending == (pendingAmount * (block.timestamp - lastTimeStamp) * controller.FEE_MULTIPLIER()) / total,
      "AccPending Check"
    );
    assertTrue(
      accReserve == (reserveAmount * (block.timestamp - lastTimeStamp) * controller.FEE_MULTIPLIER()) / total,
      "AccReserve Check"
    );
    assertTrue(
      accExit == (exitAmount * (block.timestamp - lastTimeStamp) * controller.FEE_MULTIPLIER()) / total,
      "AccExit Check"
    );
  }

  function testRatioFees() public {
    _increaseFees(10 seconds, 1, 0, 0);
    _increaseFees(20 seconds, 6, 4, 0);
    _increaseFees(30 seconds, 0, 0, 10);

    (uint256 pendingBucket, uint256 reserveBucket, uint256 exitBucket) = controller.distributeBuckets();
    assertTrue(fees.pending == pendingBucket, "Pending Fees Check");
    assertTrue(fees.reserve == reserveBucket, "Reserve Fees Check");
    assertTrue(fees.exit == exitBucket, "Exit Fees Check");

    console.log("fees.pending :", fees.pending);
    console.log("pendingBucket :", pendingBucket);
    console.log("fees.reserve :", fees.reserve);
    console.log("reserveBucket :", reserveBucket);
    console.log("fees.exit :", fees.exit);
    console.log("exitBucket :", exitBucket);
  }

  function _increaseFees(
    uint256 timeSkip,
    uint256 pen,
    uint256 res,
    uint256 ext
  ) internal {
    skip(timeSkip);
    controller.updateRatio(pen, res, ext);
    uint256 total = pen + res + ext;
    uint256 fee = controller.unclaimedFees() - fees.accountedFees;

    console.log("feesAccumulated :", fee);

    fees.pending += (fee * pen) / total;
    fees.reserve += (fee * res) / total;
    fees.exit += (fee * ext) / total;

    fees.accountedFees += fee;
  }

  function _resertFees() internal {
    fees.pending = 0;
    fees.reserve = 0;
    fees.exit = 0;
  }
}
