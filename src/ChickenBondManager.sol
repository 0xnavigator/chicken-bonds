// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/ChickenMath.sol";
import "./Interfaces/IBondNFT.sol";
import "./Interfaces/IChickenBondManager.sol";
import "./RangePoolProxy.sol";
import "./SimpleStrategy.sol";
import "./BoostToken.sol";
import "./Token.sol";

contract ChickenBondManager is ChickenMath, IChickenBondManager {
  RangePoolProxy public immutable rangePoolProxy;
  Token public immutable token;
  IBondNFT public immutable bondNFT;
  BoostToken public immutable boostToken;

  uint256 public immutable CHICKEN_IN_AMM_FEE;

  uint256 private pendingAmount;
  uint256 private exitAmount;

  uint256 public ammStakingRewards;
  uint256 public firstChickenInTime;
  uint256 public totalWeightedStartTimes;
  uint256 public lastRedemptionTime;
  mapping(uint256 => BondData) private idToBondData;

  bool public migration;

  uint256 public countChickenIn;
  uint256 public countChickenOut;

  // --- Constants ---

  uint256 constant MAX_UINT256 = type(uint256).max;
  uint256 public constant SECONDS_IN_ONE_MINUTE = 60;
  uint256 public immutable BOOTSTRAP_PERIOD_CHICKEN_IN;
  uint256 public immutable BOOTSTRAP_PERIOD_REDEEM;
  uint256 public immutable MIN_BTOKEN_SUPPLY;
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

  event LastRedemptionTimeUpdated(uint256 _lastRedemptionFeeOpTime);
  event BondCreated(address indexed bonder, uint256 bondId, uint256 amount);
  event BondClaimed(
    address indexed bonder,
    uint256 bondId,
    uint256 bondedAmount,
    uint256 boostTokenAmount,
    uint256 tokenSurplus,
    uint256 chickenInFeeAmount,
    bool migration
  );

  event BondCancelled(address indexed bonder, uint256 bondId, uint256 principalTokenAmount);
  event BoostTokenRedeemed(address indexed redeemer, uint256 boostTokenAmount, uint256 bondedAmount);
  event MigrationTriggered(uint256 previousPermanentToken);
  event AccrualParameterUpdated(uint256 accrualParameter);

  constructor(DeployAddresses memory deployedAddresses, DeployParams memory params) {
    bondNFT = IBondNFT(deployedAddresses.bondNFT);
    rangePoolProxy = RangePoolProxy(deployedAddresses.rangePoolProxy);
    token = Token(address(rangePoolProxy.lpToken()));
    boostToken = new BoostToken(ERC20(token));

    deploymentTimestamp = block.timestamp;
    targetAverageAgeSeconds = params.targetAverageAgeSeconds;
    accrualParameter = params.initialAccrualParameter * DECIMAL_PRECISION;
    minimumAccrualParameter = params.minimumAccrualParameter * DECIMAL_PRECISION;
    require(minimumAccrualParameter != 0, "CBM: Min accrual parameter cannot be zero");

    accrualAdjustmentMultiplier = 1e18 - params.accrualAdjustmentRate;
    accrualAdjustmentPeriodSeconds = params.accrualAdjustmentPeriodSeconds;

    CHICKEN_IN_AMM_FEE = params.chickenInAMMFee;
    BOOTSTRAP_PERIOD_CHICKEN_IN = params.bootstrapPeriodChickenIn;
    BOOTSTRAP_PERIOD_REDEEM = params.bootstrapPeriodRedeem;
    MIN_BTOKEN_SUPPLY = params.minBoostTokenSupply;
    require(params.minBondAmount != 0, "CBM: MIN BOND AMOUNT parameter cannot be zero"); // We can still use 1e-18
    MIN_BOND_AMOUNT = params.minBondAmount;
  }

  // --- Getter convenience functions ---

  // Bond getters

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
    reserve = _reserveAmount();
    exit = exitAmount;
  }

  function calcAccruedBoostToken(uint256 _bondID) external view returns (uint256) {
    BondData memory bond = idToBondData[_bondID];

    if (bond.status != BondStatus.active) {
      return 0;
    }

    uint256 bondBoostTokenCap = _calcBondBoostTokenCap(
      _getBondAmountMinusChickenInFee(bond.bondedAmount),
      calcSystemBackingRatio()
    );

    (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);
    return _calcAccruedAmount(bond.startTime, bondBoostTokenCap, updatedAccrualParameter);
  }

  function calcBondBoostCap(uint256 _bondID) external view returns (uint256) {
    uint256 backingRatio = calcSystemBackingRatio();

    BondData memory bond = idToBondData[_bondID];

    return _calcBondBoostTokenCap(_getBondAmountMinusChickenInFee(bond.bondedAmount), backingRatio);
  }

  function calcSystemBackingRatio() public view returns (uint256) {
    uint256 totalBoostTokenSupply = boostToken.totalSupply();

    /* TODO: Determine how to define the backing ratio when there is 0 boostToken and 0 reserve,
     * i.e. before the first chickenIn. For now, return a backing ratio of 1. Note: Both quantities would be 0
     * also when the boostToken supply is fully redeemed.
     */
    //if (totalBoostedTokenSupply == 0  && reserve == 0) {return 1e18;}
    //if (totalBoostedTokenSupply == 0) {return MAX_UINT256;}
    if (totalBoostTokenSupply == 0) {
      return 1e18;
    }
    uint256 reserve = _reserveAmount() + SimpleStrategy(rangePoolProxy.strategy()).fees(); // This needs to be updated on the actual integration with RangePools
    return (reserve * 1e18) / totalBoostTokenSupply;
  }

  function createBond(uint256 _amountToBond) public returns (uint256) {
    _requireMinBond(_amountToBond);
    _requireMigrationNotActive();

    _updateAccrualParameter();

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

    idToBondData[_bondID].status = BondStatus.chickenedOut;
    idToBondData[_bondID].endTime = uint64(block.timestamp);

    countChickenOut += 1;
    pendingAmount -= bond.bondedAmount;
    totalWeightedStartTimes -= bond.bondedAmount * bond.startTime;

    // implicitly adds fees generated to the reserve.
    _withdraw(msg.sender, bond.bondedAmount);

    emit BondCancelled(msg.sender, _bondID, bond.bondedAmount);
  }

  function chickenIn(uint256 _bondID) external {
    BondData memory bond = idToBondData[_bondID];

    _requireCallerOwnsBond(_bondID);
    _requireActiveStatus(bond.status);

    uint256 updatedAccrualParameter = _updateAccrualParameter();
    uint256 reserve = _updateReserve(); // compound fees;

    /* Upon the first chicken-in after a) system deployment or b) redemption of the full boostToken supply, divert
     * any earned fees converted to lp to the bTKN-TKN AMM for fairness.
     *
     * This is not done in migration mode since there is no need to send rewards to the staking contract.
     */
    if (boostToken.totalSupply() == 0 && !migration) {
      _firstChickenIn(bond.startTime, reserve);
    }

    (uint256 chickenInFeeAmount, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(
      bond.bondedAmount
    );

    // Get token amount to acquire from the bond in proportion to the system's current backing ratio, in order to maintain said ratio.
    uint256 tokenToAcquire = _calcAccruedAmount(bond.startTime, bondAmountMinusChickenInFee, updatedAccrualParameter);
    uint256 backingRatio = calcSystemBackingRatio(); // Get backing ratio and accrued bTKN
    uint256 accruedBoostToken = (tokenToAcquire * 1e18) / backingRatio;
    idToBondData[_bondID].claimedBoostedToken = uint64(Math.min(accruedBoostToken / 1e18, type(uint64).max)); // to units and uint64
    idToBondData[_bondID].status = BondStatus.chickenedIn;
    idToBondData[_bondID].endTime = uint64(block.timestamp);

    countChickenIn += 1;
    pendingAmount -= bond.bondedAmount; // Subtract the bonded amount from the total pending tokens (and implicitly increase the total reserve)
    totalWeightedStartTimes -= bond.bondedAmount * bond.startTime;
    uint256 tokenSurplus = bondAmountMinusChickenInFee - tokenToAcquire; // Get the remaining tokenSurplus from the lpAmount to acquire from the bond

    // Handle the tokenSurplus from the chicken-in:
    if (!migration) {
      // In normal mode, add the tokenSurplus to the exit bucket by increasing the permament tracker. This implicitly decreases the reserve.
      exitAmount += tokenSurplus;
    } else {
      // In migration mode, withdraw tokenSurplus from reserve and refund to bonder
      uint256 tokenToRefund = Math.min(tokenSurplus, _reserveAmount());
      if (tokenToRefund != 0) {
        _withdraw(msg.sender, tokenToRefund);
      }
    }

    boostToken.mint(msg.sender, accruedBoostToken);

    // Transfer the chicken in fee to the TKN/bTKN AMM LP Rewards staking contract during normal mode.
    if (!migration && _reserveAmount() >= chickenInFeeAmount) {
      _distributeStakingContractRewards(chickenInFeeAmount);
    }

    emit BondClaimed(
      msg.sender,
      _bondID,
      bond.bondedAmount,
      accruedBoostToken,
      tokenSurplus,
      chickenInFeeAmount,
      migration
    );
  }

  function redeem(uint256 amountToRedeem) external returns (uint256 lpAmount) {
    _requireNonZeroAmount(amountToRedeem);
    _requireRedemptionNotDepletingBoostToken(amountToRedeem);

    require(
      block.timestamp >= firstChickenInTime + BOOTSTRAP_PERIOD_REDEEM,
      "CBM: Redemption after first chicken in must wait until bootstrap period is over"
    );

    uint256 reserve = _updateReserve();

    uint256 fractionToRedeem = (amountToRedeem * 1e18) / boostToken.totalSupply();
    lpAmount = (reserve * fractionToRedeem) / 1e18;
    _requireNonZeroAmount(lpAmount);

    // Burn the redeemed boostedToken
    boostToken.burn(msg.sender, amountToRedeem);
    if (lpAmount != 0) _withdraw(msg.sender, lpAmount);

    emit BoostTokenRedeemed(msg.sender, amountToRedeem, lpAmount);
  }

  // --- Helper functions ---
  /* Divert acquired yield to TKN/bTKN AMM LP rewards staking contract
   * It happens on the very first chicken in event of the system, or any time that redemptions deplete bTKN total supply to zero
   * Assumption: When there have been no chicken ins since the bTKN supply was set to 0 (either due to system deployment, or full bTKN redemption),
   * all acquired TKN must necessarily be pure yield.
   */
  function _firstChickenIn(uint256 _bondStartTime, uint256 _cacheReserve) internal {
    //assert(!migration); // we leave it as a comment so we can uncomment it for automated testing tools

    require(
      block.timestamp >= _bondStartTime + BOOTSTRAP_PERIOD_CHICKEN_IN,
      "CBM: First chicken in must wait until bootstrap period is over"
    );
    firstChickenInTime = block.timestamp;

    if (_cacheReserve > 0) {
      _distributeStakingContractRewards(_cacheReserve);
    }
  }

  function _updateReserve() internal returns (uint256) {
    if (rangePoolProxy.fees() != 0) rangePoolProxy.compound();
    return _reserveAmount();
  }

  function _reserveAmount() internal view returns (uint256) {
    return token.balanceOf(address(this)) - (pendingAmount + exitAmount);
  }

  function _distributeStakingContractRewards(uint256 amount) internal {
    ammStakingRewards += amount;
    token.burn(address(this), amount);
  }

  // Internal getter for calculating the bond boostToken cap based on bonded amount and backing ratio
  function _calcBondBoostTokenCap(uint256 _bondedAmount, uint256 _backingRatio) internal pure returns (uint256) {
    // TODO: potentially refactor this -  i.e. have a (1 / backingRatio) function for more precision
    return (_bondedAmount * 1e18) / _backingRatio;
  }

  function _getBondAmountMinusChickenInFee(uint256 _bondTokenAmount) internal view returns (uint256) {
    (, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(_bondTokenAmount);
    return bondAmountMinusChickenInFee;
  }

  function _getBondWithChickenInFeeApplied(uint256 _bondTokenAmount) internal view returns (uint256, uint256) {
    // Apply zero fee in migration mode
    if (migration) {
      return (0, _bondTokenAmount);
    }

    // Otherwise, apply the constant fee rate
    uint256 chickenInFeeAmount = (_bondTokenAmount * CHICKEN_IN_AMM_FEE) / 1e18;
    uint256 bondAmountMinusChickenInFee = _bondTokenAmount - chickenInFeeAmount;

    return (chickenInFeeAmount, bondAmountMinusChickenInFee);
  }

  /* _calcAccruedAmount: internal getter for calculating accrued token amount for a given bond.
   *
   * This function is unit-agnostic. It can be used to calculate a bonder's accrrued boostedToken, or the token that the
   * CB system would acquire (i.e. receive to the reserve bucket) if the bond were Chickened In now.
   *
   * For the bonder, _capAmount is their boostToken cap.
   * For the CB system, _capAmount is the token bond amount (less the Chicken In fee).
   */
  function _calcAccruedAmount(
    uint256 _startTime,
    uint256 _capAmount,
    uint256 _accrualParameter
  ) internal view returns (uint256) {
    // All bonds have a non-zero creation timestamp, so return accrued bTKN 0 if the startTime is 0
    if (_startTime == 0) {
      return 0;
    }

    // Scale `bondDuration` up to an 18 digit fixed-point number.
    // This lets us add it to `accrualParameter`, which is also an 18-digit FP.
    uint256 bondDuration = 1e18 * (block.timestamp - _startTime);

    uint256 accruedAmount = (_capAmount * bondDuration) / (bondDuration + _accrualParameter);
    //assert(accruedAmount < _capAmount); // we leave it as a comment so we can uncomment it for automated testing tools

    return accruedAmount;
  }

  function _minutesPassedSinceLastRedemption() internal view returns (uint256) {
    return (block.timestamp - lastRedemptionTime) / SECONDS_IN_ONE_MINUTE;
  }

  function _withdraw(address _to, uint256 _amount) internal {
    uint256 amountToWithdraw = Math.min(_amount, token.balanceOf(address(this)));
    token.transfer(_to, amountToWithdraw);
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

  // --- 'require' functions

  function _requireNonZeroAmount(uint256 _amount) internal pure {
    require(_amount != 0, "CBM: Amount must be > 0");
  }

  function _requireRedemptionNotDepletingBoostToken(uint256 amountToRedeem) internal view {
    if (!migration) {
      require(amountToRedeem + MIN_BTOKEN_SUPPLY <= boostToken.totalSupply(), "CBM: Cannot redeem below min supply");
    }
  }

  function _requireCallerOwnsBond(uint256 _bondID) internal view {
    require(msg.sender == bondNFT.ownerOf(_bondID), "CBM: Caller must own the bond");
  }

  function _requireMinBond(uint256 _amount) internal view {
    require(_amount >= MIN_BOND_AMOUNT, "CBM: Bond minimum amount not reached");
  }

  function _requireMigrationNotActive() internal view {
    require(!migration, "CBM: Migration must be not be active");
  }

  function _requireActiveStatus(BondStatus status) internal pure {
    require(status == BondStatus.active, "CBM: Bond must be active");
  }
}
