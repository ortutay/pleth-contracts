// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStEth } from "../interfaces/IStEth.sol";
import { IAsset } from "../interfaces/IAsset.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";


contract StETHERC4626 is IAsset, ERC4626 {
    using SafeERC20 for IERC20;

    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("stETH erc4626", "stETH erc4626") {}

    function wrap(uint256) external payable {
        IStEth(asset()).submit{value: msg.value}(address(0));
        IERC20(asset()).transfer(msg.sender,
                                 IERC20(asset()).balanceOf(address(this)));
    }
}
