// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";

contract FeeGeneratorTest is BaseTest {
  function testUnclaimedFees() public {
    uint256 timeSkip = 100;
    skip(timeSkip);

    assert(fg.unclaimedFees() == timeSkip * DECIMAL_PRECISION);
  }

  function testClaim() public {
    uint256 timeSkip = 100;
    skip(timeSkip);
    fg.claim();

    assert(fg.cumulativeFees() == timeSkip * DECIMAL_PRECISION);
  }
}
