pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DEX {

  using SafeMath for uint256;
  IERC20 token;
  uint256 public totalLiquidity;
  mapping (address => uint256) public liquidity;

  constructor(address token_addr) {
    token = IERC20(token_addr);
  }

  function init(uint256 tokens) external payable returns (uint256) {
    // ETH comes in via payable (msg.value)
    // tokens come in via argument
    require(totalLiquidity == 0, "DEX: init - already has liquidity");

    totalLiquidity = address(this).balance;  // be careful! can go out of alignment if pre-sent eth is here
    liquidity[msg.sender] = totalLiquidity;

    require(token.transferFrom(msg.sender, address(this), tokens));
    return totalLiquidity;
  }

  function price(uint256 input_amount, uint256 input_reserve, uint256 output_reserve) public pure returns (uint256) {
    // Derivation of the formula:
    // x*y = k
    // converting to variable names:
    // (input_reserve) * (output_reserve) = k
    // this equality must stay true even after adding/selling x (and thus removing/buying y):
    // (input_reserve + input_amount) * (output_reserve - output_amount) = k
    // let's equate them since they both equal k:
    // (input_reserve) * (output_reserve) = (input_reserve + input_amount) * (output_reserve - output_amount)
    // output_amount = output_reserve - (input_reserve * output_reserve) / (input_reserve + input_amount * fee)
    // output_amount = output_reserve * (input_reserve + input_amount * fee) - (input_reserve * output_reserve) / (input_reserve + input_amount * fee)
    // preliminary result -- this gives us the correct form:
    // output_amount = output_reserve * input_amount * fee / (input_reserve + input_amount * fee)
    // let's now handle the "997" thingy which is just related to the fee, like this:
    // since fee is like 0.3% = 0.003 = 3/1000
    // we can account for the fee like this:
    // output_amount = output_reserve * input_amount * (1 - 3/1000) / (input_reserve + input_amount * (1 - 3/1000))
    // but 1 - 3/1000 = 0.997
    // but we also don't like floats, so let's multiply that by 1000 in numerator and denominator,
    // to get 997 (and the 1000 for the input_reserve b/c that does not get modified by the fee).
    // output_amount = output_reserve * input_amount * 997 / (input_reserve * 1000 + input_amount * 997)
    uint256 input_amount_with_fee = input_amount.mul(997);
    uint256 numerator = input_amount_with_fee.mul(output_reserve);
    uint256 denominator = input_reserve.mul(1000).add(input_amount_with_fee);

    return numerator.div(denominator);
  }

  function ethToToken() external payable returns (uint256) {
    uint256 token_reserve = token.balanceOf(address(this));  // how many BAL tokens does the DEX hold?
    uint256 tokens_bought = price(msg.value, address(this).balance.sub(msg.value), token_reserve);
    require(token.transfer(msg.sender, tokens_bought));

    return tokens_bought;
  }

  function tokenToEth(uint256 tokens) external returns (uint256) {
    if(tokens == 0) return 0;

    // tokens come in, eth goes out

    // tokens = input_amount
    uint256 input_reserve = token.balanceOf(address(this));  // in = tokens
    uint256 output_reserve = address(this).balance;  // out = ETH

    uint256 eth_bought = price(tokens, input_reserve, output_reserve);

    // first send tokens from user to us
    require(token.transferFrom(msg.sender, address(this), tokens));  // transfer the tokens from the user/sender to us/this address
    require(token.balanceOf(address(this)) >= input_reserve + tokens);  // make sure we got funds from the user

    // now send ETH back to the user
    payable(msg.sender).transfer(eth_bought);

    return eth_bought;
  }

  function deposit() public payable returns (uint256) {
    // deposit liquidity into the DEX
    uint256 eth_reserve = address(this).balance.sub(msg.value);
    uint256 token_reserve = token.balanceOf(address(this));

    uint256 token_amount = (msg.value.mul(token_reserve) / eth_reserve).add(1);
    uint256 liquidity_minted = msg.value.mul(totalLiquidity) / eth_reserve;

    liquidity[msg.sender] = liquidity[msg.sender].add(liquidity_minted);
    totalLiquidity = totalLiquidity.add(liquidity_minted);

    require(token.transferFrom(msg.sender, address(this), token_amount));

    return liquidity_minted;
  }

  function withdraw(uint256 amount) public returns (uint256, uint256) {
    uint256 token_reserve = token.balanceOf(address(this));

    uint256 eth_amount = amount.mul(address(this).balance) / totalLiquidity;
    uint256 token_amount = amount.mul(token_reserve) / totalLiquidity;

    liquidity[msg.sender] = liquidity[msg.sender].sub(eth_amount);
    totalLiquidity = totalLiquidity.sub(eth_amount);
    payable(msg.sender).transfer(eth_amount);
    require(token.transfer(msg.sender, token_amount));
    
    return (eth_amount, token_amount);
  }
}
