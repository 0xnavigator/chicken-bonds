// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;
import '@openzeppelin/contracts/utils/Strings.sol';
import './Token.sol';

//import "forge-std/console.sol";

contract BoostToken is Token {
  constructor(ERC20 lpToken)
    Token(string(abi.encodePacked('BOOST_', lpToken.name())), string(abi.encodePacked('BOOST_', lpToken.symbol())))
  {}

  function mint(address _to, uint256 _amount) external override onlyOwner {
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external override onlyOwner {
    _burn(_from, _amount);
  }
}
