// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

interface IWrappedETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}
