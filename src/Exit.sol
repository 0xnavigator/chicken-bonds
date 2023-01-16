// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// pragma abicoder v2;

import "./Token.sol";

contract Exit is Token {
  uint256 public immutable MAX_SUPPLY;

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 max_supply_
  ) Token(name_, symbol_) {
    MAX_SUPPLY = max_supply_;
  }
}
