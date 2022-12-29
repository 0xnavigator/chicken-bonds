// SPDX-License-Identifier: GPL-3.0
// Forked from https://github.com/liquity/ChickenBond/blob/main/LUSDChickenBonds/src/ChickenBondManager.sol

pragma solidity ^0.8.10;
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/ChickenMath.sol";
import "./Interfaces/IBondNFT.sol";
import "./Interfaces/IChickenBondManager.sol";
import "./Interfaces/IChickenBondController.sol";
import "./BoostToken.sol";
import "./Token.sol";

contract ChickenBondManager is ChickenMath, IChickenBondManager {
  Token public immutable token;
  IBondNFT public immutable bondNFT;
  BoostToken public immutable boostToken;
  IChickenBondController public immutable controller;

  uint256 private pendingAmount;
  uint256 private reserveAmount;

  uint256 public totalWeightedStartTimes;
  uint256 public countChickenIn;
  uint256 public countChickenOut;

  mapping(uint256 => BondData) private idToBondData;

  bool public inExitMode;

  // --- Constants ---
  uint256 constant MAX_UINT256 = type(uint256).max;
  uint256 public immutable BOOTSTRAP_PERIOD;
  uint256 public immutable MIN_BOND_AMOUNT;

  // --- Accrual control variables ---
  uint256 public immutable deploymentTimestamp;
  uint256 public immutable targetAverageAgeSeconds; // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual.
  uint256 public immutable minimumAccrualParameter; // Stop adjusting `accrualParameter` when this value is reached.
  uint256 public immutable accrualAdjustmentMultiplier; // Number between 0 and 1. `accrualParameter` is multiplied by this every time there's an adjustment.
  uint256 public immutable accrualAdjustmentPeriodSeconds; // The duration of an adjustment period in seconds. The controller performs at most one adjustment per every period.
  uint256 public accrualParameter; // The number of seconds it takes to accrue 50% of the cap, represented as an 18 digit fixed-point number.

  // Counts the number of adjustment periods since deployment.
  // Updated by operations that change the average outstanding bond age (createBond, chickenIn, chickenOut).
  // Used by `_calcUpdatedAccrualParameter` to tell whether it's time to perform adjustments, and if so, how many times
  // (in case the time elapsed since the last adjustment is more than one adjustment period).
  uint256 public accrualAdjustmentPeriodCount;

  // --- Events ---
  event BondCreated(address indexed bonder, uint256 bondId, uint256 amount);
  event BondClaimed(
    address indexed bonder,
    uint256 bondId,
    uint256 bondAmount,
    uint256 boostTokenClaimed,
    uint256 exitLiquidityAmount
  );

  event BondCancelled(address indexed bonder, uint256 bondId, uint256 amountReturned);
  event TokenRedeemed(address indexed redeemer, uint256 amount);
  event AccrualParameterUpdated(uint256 accrualParameter);

  constructor(DeployParams memory params) {
    bondNFT = IBondNFT(params.bondNFT);
    token = Token(params.token);
    controller = IChickenBondController(params.controller);
    boostToken = new BoostToken(address(token));

    deploymentTimestamp = block.timestamp;
    targetAverageAgeSeconds = params.targetAverageAgeSeconds;
    accrualParameter = params.initialAccrualParameter * DECIMAL_PRECISION;
    minimumAccrualParameter = params.minimumAccrualParameter * DECIMAL_PRECISION;
    require(minimumAccrualParameter != 0, "ChickenBondManager: Min accrual parameter cannot be zero");

    accrualAdjustmentMultiplier = 1e18 - params.accrualAdjustmentRate;
    accrualAdjustmentPeriodSeconds = params.accrualAdjustmentPeriodSeconds;

    BOOTSTRAP_PERIOD = params.bootstrapPeriod;
    require(params.minBondAmount != 0, "ChickenBondManager: MIN BOND AMOUNT parameter cannot be zero"); // We can still use 1e-18
    MIN_BOND_AMOUNT = params.minBondAmount;
  }

  function getBondData(uint256 bondID)
    external
    view
    returns (
      uint256 bondAmount,
      uint256 claimedBoostAmount,
      uint64 startTime,
      uint64 endTime,
      uint8 status
    )
  {
    BondData memory bond = idToBondData[bondID];
    return (bond.bondAmount, bond.claimedBoostAmount, bond.startTime, bond.endTime, uint8(bond.status));
  }

  function getTreasury()
    external
    view
    returns (
      uint256 pending,
      uint256 reserve,
      uint256 exit
    )
  {
    pending = pendingAmount;
    reserve = reserveAmount;
    exit = _exitAmount();
  }

  function calcAccruedAmount(uint256 bondID) external view returns (uint256) {
    BondData memory bond = idToBondData[bondID];

    if (bond.status != BondStatus.active) {
      return 0;
    }

    (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

    return _calcAccruedAmount(bond.startTime, bond.bondAmount, updatedAccrualParameter);
  }

  function getOpenBondCount() external view returns (uint256) {
    return bondNFT.totalSupply() - (countChickenIn + countChickenOut);
  }

  function createBond(uint256 amount) public returns (uint256) {
    require(
      block.timestamp >= deploymentTimestamp + BOOTSTRAP_PERIOD,
      "ChickenBondManager: Must wait until bootstrap period is over"
    );
    require(amount >= MIN_BOND_AMOUNT, "ChickenBondManager: Minimum bond amount not reached");

    _updateAccrualParameter();
    _updateRatio();

    uint256 bondID = bondNFT.mint(msg.sender);

    BondData memory bondData;
    bondData.bondAmount = amount;
    bondData.startTime = uint64(block.timestamp);
    bondData.status = BondStatus.active;
    idToBondData[bondID] = bondData;

    pendingAmount += amount;
    totalWeightedStartTimes += amount * block.timestamp;

    token.transferFrom(msg.sender, address(this), amount);

    emit BondCreated(msg.sender, bondID, amount);

    return bondID;
  }

  function createBondWithPermit(
    address owner,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint256) {
    if (token.allowance(owner, address(this)) < amount) {
      token.permit(owner, address(this), amount, deadline, v, r, s);
    }
    return createBond(amount);
  }

  function chickenOut(uint256 bondID) external {
    BondData memory bond = idToBondData[bondID];

    _requireCallerOwnsBond(bondID);
    _requireActiveStatus(bond.status);

    _updateAccrualParameter();
    _updateRatio();

    idToBondData[bondID].status = BondStatus.chickenedOut;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    countChickenOut += 1;
    pendingAmount -= bond.bondAmount;
    totalWeightedStartTimes -= bond.bondAmount * bond.startTime;

    _withdraw(msg.sender, bond.bondAmount);
    emit BondCancelled(msg.sender, bondID, bond.bondAmount);
  }

  function chickenIn(uint256 bondID) external {
    require(!inExitMode, "ChickenBondManager: Only chicken out allowed in exit mode");

    BondData memory bond = idToBondData[bondID];

    _requireCallerOwnsBond(bondID);
    _requireActiveStatus(bond.status);

    _updateRatio();

    uint256 accruedbondToken = _calcAccruedAmount(bond.startTime, bond.bondAmount, _updateAccrualParameter());
    idToBondData[bondID].claimedBoostAmount = accruedbondToken;
    idToBondData[bondID].status = BondStatus.chickenedIn;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    countChickenIn += 1;
    pendingAmount -= bond.bondAmount; // Subtract the bonded amount from the total pending tokens
    reserveAmount += accruedbondToken; // Increase the amount of the reserve
    totalWeightedStartTimes -= bond.bondAmount * bond.startTime;
    boostToken.mint(msg.sender, accruedbondToken);

    // assert(bond.bondAmount > accruedbondToken); // Uncomment for tests.
    uint256 exitLiquidity = bond.bondAmount - accruedbondToken;

    emit BondClaimed(msg.sender, bondID, bond.bondAmount, accruedbondToken, exitLiquidity);
  }

  function redeem(uint256 amount) external {
    require(amount != 0, "ChickenBondManager: Amount must be > 0");

    require(boostToken.balanceOf(msg.sender) >= amount, "ChickenBondManager: You do not own enough bond tokens");

    _updateRatio();

    reserveAmount -= amount;
    boostToken.burn(msg.sender, amount);
    _withdraw(msg.sender, amount);

    emit TokenRedeemed(msg.sender, amount);
  }

  function _requireCallerOwnsBond(uint256 _bondID) internal view {
    require(msg.sender == bondNFT.ownerOf(_bondID), "ChickenBondManager: Caller must own the bond");
  }

  function _requireActiveStatus(BondStatus _status) internal pure {
    require(_status == BondStatus.active, "ChickenBondManager: Bond must be active");
  }

  function _exitAmount() internal view returns (uint256) {
    return token.balanceOf(address(this)) - (pendingAmount + reserveAmount);
  }

  function _withdraw(address _to, uint256 _amount) internal {
    uint256 amountToWithdraw = Math.min(_amount, token.balanceOf(address(this)));
    token.transfer(_to, amountToWithdraw);
  }

  function _updateRatio() internal {
    controller.updateRatio(pendingAmount, reserveAmount, _exitAmount());
  }

  function _calcAccruedAmount(
    uint256 _startTime,
    uint256 _capAmount,
    uint256 _accrualParameter
  ) internal view returns (uint256) {
    if (_startTime == 0) {
      return 0;
    }
    uint256 bondDuration = 1e18 * (block.timestamp - _startTime);
    uint256 accruedAmount = (_capAmount * bondDuration) / (bondDuration + _accrualParameter);
    //assert(accruedAmount < _capAmount); // we leave it as a comment so we can uncomment it for automated testing tools
    return accruedAmount;
  }

  function _updateAccrualParameter() internal returns (uint256) {
    uint256 storedAccrualParameter = accrualParameter;
    uint256 storedAccrualAdjustmentPeriodCount = accrualAdjustmentPeriodCount;

    (uint256 updatedAccrualParameter, uint256 updatedAccrualAdjustmentPeriodCount) = _calcUpdatedAccrualParameter(
      storedAccrualParameter,
      storedAccrualAdjustmentPeriodCount
    );

    if (updatedAccrualAdjustmentPeriodCount != storedAccrualAdjustmentPeriodCount) {
      accrualAdjustmentPeriodCount = updatedAccrualAdjustmentPeriodCount;

      if (updatedAccrualParameter != storedAccrualParameter) {
        accrualParameter = updatedAccrualParameter;
        emit AccrualParameterUpdated(updatedAccrualParameter);
      }
    }

    return updatedAccrualParameter;
  }

  function _calcUpdatedAccrualParameter(uint256 _storedAccrualParameter, uint256 _storedAccrualAdjustmentCount)
    internal
    view
    returns (uint256 updatedAccrualParameter, uint256 updatedAccrualAdjustmentPeriodCount)
  {
    updatedAccrualAdjustmentPeriodCount = (block.timestamp - deploymentTimestamp) / accrualAdjustmentPeriodSeconds;

    if (
      // There hasn't been enough time since the last update to warrant another update
      updatedAccrualAdjustmentPeriodCount == _storedAccrualAdjustmentCount ||
      // or `accrualParameter` is already bottomed-out
      _storedAccrualParameter == minimumAccrualParameter ||
      // or there are no outstanding bonds (avoid division by zero)
      pendingAmount == 0
    ) {
      return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
    }

    uint256 averageStartTime = totalWeightedStartTimes / pendingAmount;

    // Detailed explanation - https://github.com/liquity/ChickenBond/blob/af398985900cde68a9099a5149eca773a365e93a/LUSDChickenBonds/src/ChickenBondManager.sol#L834

    uint256 adjustmentPeriodCountWhenTargetIsExceeded = Math.ceilDiv(
      averageStartTime + targetAverageAgeSeconds - deploymentTimestamp,
      accrualAdjustmentPeriodSeconds
    );

    if (updatedAccrualAdjustmentPeriodCount < adjustmentPeriodCountWhenTargetIsExceeded) {
      // No adjustment needed; target average age hasn't been exceeded yet
      return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
    }

    uint256 numberOfAdjustments = updatedAccrualAdjustmentPeriodCount -
      Math.max(_storedAccrualAdjustmentCount, adjustmentPeriodCountWhenTargetIsExceeded - 1);

    updatedAccrualParameter = Math.max(
      (_storedAccrualParameter * decPow(accrualAdjustmentMultiplier, numberOfAdjustments)) / 1e18,
      minimumAccrualParameter
    );
  }
}
