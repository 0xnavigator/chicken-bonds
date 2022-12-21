// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import './Interfaces/IChickenBondManager.sol';

//import "forge-std/console.sol";

contract BondNFT is ERC721Enumerable, Ownable {
  IChickenBondManager public chickenBondManager;
  uint256 public immutable transferLockoutPeriodSeconds;

  modifier onlyBondsManager() {
    require(msg.sender == address(chickenBondManager), 'BondNFT: Caller must be ChickenBondManager');
    _;
  }

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 _transferLockoutPeriodSeconds
  ) ERC721(name_, symbol_) {
    transferLockoutPeriodSeconds = _transferLockoutPeriodSeconds;
  }

  function setChickenBondManager(address _chickenBondManager) external onlyOwner {
    require(_chickenBondManager != address(0), 'BondNFT: _chickenBondManagerAddress must be non-zero');
    require(address(chickenBondManager) == address(0), 'BondNFT: setAddresses() can only be called once');

    chickenBondManager = IChickenBondManager(_chickenBondManager);
    renounceOwnership();
  }

  function mint(address _bonder) external onlyBondsManager returns (uint256 tokenID) {
    // We actually increase totalSupply in `ERC721Enumerable._beforeTokenTransfer` when we `_mint`.
    tokenID = totalSupply() + 1;

    _mint(_bonder, tokenID);
  }

  function tokenURI(uint256 _tokenID) public view virtual override returns (string memory) {
    require(_exists(_tokenID), 'BondNFT: URI query for nonexistent token');

    return ('uri');
  }

  // Prevent transfers for a period of time after chickening in or out
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenID
  ) internal virtual override {
    if (_from != address(0)) {
      (, , , uint256 endTime, uint8 status) = chickenBondManager.getBondData(_tokenID);

      require(
        status == uint8(IChickenBondManager.BondStatus.active) ||
          block.timestamp >= endTime + transferLockoutPeriodSeconds,
        'BondNFT: cannot transfer during lockout period'
      );
    }

    super._beforeTokenTransfer(_from, _to, _tokenID);
  }

  function getBondAmount(uint256 _tokenID) external view returns (uint256 tokenAmount) {
    (tokenAmount, , , , ) = chickenBondManager.getBondData(_tokenID);
  }

  function getBondClaimed(uint256 _tokenID) external view returns (uint256 claimedBoostedToken) {
    (, claimedBoostedToken, , , ) = chickenBondManager.getBondData(_tokenID);
  }

  function getBondStartTime(uint256 _tokenID) external view returns (uint256 startTime) {
    (, , startTime, , ) = chickenBondManager.getBondData(_tokenID);
  }

  function getBondEndTime(uint256 _tokenID) external view returns (uint256 endTime) {
    (, , , endTime, ) = chickenBondManager.getBondData(_tokenID);
  }

  function getBondStatus(uint256 _tokenID) external view returns (uint8 status) {
    (, , , , status) = chickenBondManager.getBondData(_tokenID);
  }
}
