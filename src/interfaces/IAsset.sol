// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IAsset is IERC4626 {

    function wrap(uint256) external payable;

}
