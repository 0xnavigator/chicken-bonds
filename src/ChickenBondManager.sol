// SPDX-License-Identifier: GPL-3.0
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
    uint256 bondedAmount,
    uint256 boostTokenAmount,
    uint256 exitLiquidity
  );

  event BondCancelled(address indexed bonder, uint256 bondId, uint256 principalTokenAmount);
  event BoostTokenRedeemed(address indexed redeemer, uint256 amount);
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

  function getBondData(uint256 _bondID)
    external
    view
    returns (
      uint256 bondedAmount,
      uint64 claimedBoostedToken,
      uint64 startTime,
      uint64 endTime,
      uint8 status
    )
  {
    BondData memory bond = idToBondData[_bondID];
    return (bond.bondedAmount, bond.claimedBoostedToken, bond.startTime, bond.endTime, uint8(bond.status));
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

  function createBond(uint256 _amountToBond) public returns (uint256) {
    require(_amountToBond >= MIN_BOND_AMOUNT, "CBM: Bond minimum amount not reached");

    _updateAccrualParameter();
    _updateRatio();

    uint256 bondID = bondNFT.mint(msg.sender);

    BondData memory bondData;
    bondData.bondedAmount = _amountToBond;
    bondData.startTime = uint64(block.timestamp);
    bondData.status = BondStatus.active;
    idToBondData[bondID] = bondData;

    pendingAmount += _amountToBond;
    totalWeightedStartTimes += _amountToBond * block.timestamp;

    token.transferFrom(msg.sender, address(this), _amountToBond);

    emit BondCreated(msg.sender, bondID, _amountToBond);

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

  function chickenOut(uint256 _bondID) external {
    BondData memory bond = idToBondData[_bondID];

    _requireCallerOwnsBond(_bondID);
    _requireActiveStatus(bond.status);

    _updateAccrualParameter();
    _updateRatio();

    idToBondData[_bondID].status = BondStatus.chickenedOut;
    idToBondData[_bondID].endTime = uint64(block.timestamp);

    countChickenOut += 1;
    pendingAmount -= bond.bondedAmount;
    totalWeightedStartTimes -= bond.bondedAmount * bond.startTime;

    _withdraw(msg.sender, bond.bondedAmount);
    emit BondCancelled(msg.sender, _bondID, bond.bondedAmount);
  }

  function chickenIn(uint256 _bondID) external {
    require(!inExitMode, "ChickenBondManager: Only chicken out allowed in exit mode");

    BondData memory bond = idToBondData[_bondID];

    _requireCallerOwnsBond(_bondID);
    _requireActiveStatus(bond.status);

    require(
      block.timestamp >= bond.startTime + BOOTSTRAP_PERIOD,
      "ChickenBondManager: First chicken in must wait until bootstrap period is over"
    );

    uint256 updatedAccrualParameter = _updateAccrualParameter();
    _updateRatio();

    uint256 accruedBoostToken = _calcAccruedAmount(bond.startTime, bond.bondedAmount, updatedAccrualParameter);
    idToBondData[_bondID].claimedBoostedToken = uint64(Math.min(accruedBoostToken / 1e18, type(uint64).max)); // to units and uint64
    idToBondData[_bondID].status = BondStatus.chickenedIn;
    idToBondData[_bondID].endTime = uint64(block.timestamp);

    countChickenIn += 1;
    pendingAmount -= bond.bondedAmount; // Subtract the bonded amount from the total pending tokens
    reserveAmount += accruedBoostToken; // Increase the amount of the reserve
    totalWeightedStartTimes -= bond.bondedAmount * bond.startTime;
    boostToken.mint(msg.sender, accruedBoostToken);
    uint256 exitLiquidity = accruedBoostToken - bond.bondedAmount;

    emit BondClaimed(msg.sender, _bondID, bond.bondedAmount, accruedBoostToken, exitLiquidity);
  }

  function redeem(uint256 amount) external {
    require(amount != 0, "CBM: Amount must be > 0");

    require(boostToken.balanceOf(msg.sender) >= amount, "ChickenBondManager: You do not own enough boost tokens");

    _updateRatio();

    reserveAmount -= amount;
    boostToken.burn(msg.sender, amount);
    _withdraw(msg.sender, amount);

    emit BoostTokenRedeemed(msg.sender, amount);
  }

  function _requireCallerOwnsBond(uint256 _bondID) internal view {
    require(msg.sender == bondNFT.ownerOf(_bondID), "CBM: Caller must own the bond");
  }

  function _requireActiveStatus(BondStatus status) internal pure {
    require(status == BondStatus.active, "CBM: Bond must be active");
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

    // We want to calculate the period when the average age will have reached or exceeded the
    // target average age, to be used later in a check against the actual current period.
    //
    // At any given timestamp `t`, the average age can be calculated as:
    //   averageAge(t) = t - averageStartTime
    //
    // For any period `n`, the average age is evaluated at the following timestamp:
    //   tSample(n) = deploymentTimestamp + n * accrualAdjustmentPeriodSeconds
    //
    // Hence we're looking for the smallest integer `n` such that:
    //   averageAge(tSample(n)) >= targetAverageAgeSeconds
    //
    // If `n` is the smallest integer for which the above inequality stands, then:
    //   averageAge(tSample(n - 1)) < targetAverageAgeSeconds
    //
    // Combining the two inequalities:
    //   averageAge(tSample(n - 1)) < targetAverageAgeSeconds <= averageAge(tSample(n))
    //
    // Substituting and rearranging:
    //   1.    deploymentTimestamp + (n - 1) * accrualAdjustmentPeriodSeconds - averageStartTime
    //       < targetAverageAgeSeconds
    //      <= deploymentTimestamp + n * accrualAdjustmentPeriodSeconds - averageStartTime
    //
    //   2.    (n - 1) * accrualAdjustmentPeriodSeconds
    //       < averageStartTime + targetAverageAgeSeconds - deploymentTimestamp
    //      <= n * accrualAdjustmentPeriodSeconds
    //
    //   3. n - 1 < (averageStartTime + targetAverageAgeSeconds - deploymentTimestamp) / accrualAdjustmentPeriodSeconds <= n
    //
    // Using equivalence `n = ceil(x) <=> n - 1 < x <= n` we arrive at:
    //   n = ceil((averageStartTime + targetAverageAgeSeconds - deploymentTimestamp) / accrualAdjustmentPeriodSeconds)
    //
    // We can calculate `ceil(a / b)` using `Math.ceilDiv(a, b)`.
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
