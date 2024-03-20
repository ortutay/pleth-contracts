// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YToken is ERC20, Ownable {

    uint256 public immutable strike;

    string private _name;
    string private _symbol;

    constructor(uint256 strike_) ERC20("", "") Ownable(msg.sender) {
        strike = strike_;

        _name = "y token"; // todo
        _symbol = "yt"; // todo
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return 18;
    }

    function mint(address user, uint256 amount) public onlyOwner {
        _mint(user, amount);
    }

}
