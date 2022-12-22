// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface IChickenBondController {
  function updateRatio(
    uint256 pending,
    uint256 reserve,
    uint256 exit
  ) external;

  function exitCheck() external view returns (bool);
}
