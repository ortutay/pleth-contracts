// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { HodlMultiToken } from "../multi/HodlMultiToken.sol";

contract HodlToken is IERC20 {

    mapping(address => mapping(address => uint256)) private _allowances;

    HodlMultiToken public immutable hodlMulti;
    uint256 public immutable strike;

    string private _name;
    string private _symbol;

    constructor(address hodlMulti_, uint256 strike_) {
        hodlMulti = HodlMultiToken(hodlMulti_);
        strike = strike_;

        _name = hodlMulti.name(strike);
        _symbol = hodlMulti.symbol(strike);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view returns (uint256) {
        return hodlMulti.totalSupply(strike);
    }

    function balanceOf(address user) public view returns (uint256) {
        return hodlMulti.balanceOf(user, strike);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        hodlMulti.safeTransferFrom(msg.sender, to, strike, amount, "");

        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "approve zero address");
        _allowances[msg.sender][spender] = amount;

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(from == msg.sender || _allowances[from][msg.sender] >= amount, "not authorized");
        _allowances[from][msg.sender] -= amount;

        hodlMulti.safeTransferFrom(from, to, strike, amount, "");

        return true;
    }
}
