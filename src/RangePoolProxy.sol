// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./LPToken.sol";
import "./SimpleStrategy.sol";
import "./ChickenBondManager.sol";

contract RangePoolProxy is Ownable {
  LPToken public lpToken;
  SimpleStrategy public strategy;
  address public chickenBondManager;

  constructor(address strategy_) {
    lpToken = new LPToken("UNI_V3_LP_ID", "LP_ID");
    strategy = SimpleStrategy(strategy_);
  }

  function setChickenBondManager(address chickenBondManager_) external onlyOwner {
    chickenBondManager = chickenBondManager_;
    renounceOwnership();
  }

  function fees() external view returns (uint256) {
    return strategy.fees();
  }

  function compound() external returns (uint256 amountCompounded) {
    require(chickenBondManager != address(0), "RangePoolProxy: ChickenBondManager not set");
    amountCompounded = strategy.compound();
    lpToken.mint(chickenBondManager, amountCompounded);
  }

  function deposit(uint256 amount) external returns (uint256) {
    lpToken.mint(msg.sender, amount);
    return amount;
  }

  function withdraw(address to, uint256 amount) external returns (uint256) {
    lpToken.burn(to, amount);
    return amount;
  }
}
