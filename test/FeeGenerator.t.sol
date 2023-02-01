// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";

contract FeeGeneratorTest is BaseTest {
  function testUnclaimedFees() public {
    uint256 timeSkip = 100;
    skip(timeSkip);

    (uint amount0, uint amount1) = fg.unclaimedFees();

    assert(amount0 == timeSkip * DECIMAL_PRECISION);
    assert(amount1 == amount0 / fg.RATIO());
  }

  // function testClaim() public {
  //   uint256 timeSkip = 100;
  //   skip(timeSkip);
  //   fg.claim();

  //   assert(fg.cumulativeFees() == timeSkip * DECIMAL_PRECISION);
  // }

  // function testClaimsAndUnclaimedFees() public {
  //   uint256 timeSkip = 100;
  //   skip(timeSkip);
  //   fg.claim();
  //   skip(timeSkip);

  //   assert(fg.unclaimedFees() == timeSkip * DECIMAL_PRECISION);
  //   assert(fg.cumulativeFees() == timeSkip * DECIMAL_PRECISION);
  // }
}
