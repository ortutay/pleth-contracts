// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Vault } from  "../src/Vault.sol";
import { Router } from  "../src/Router.sol";

import { BaseScript } from "./BaseScript.sol";
import { FakeOracle } from  "../test/helpers/FakeOracle.sol";
import { IStEth } from "../src/interfaces/IStEth.sol";
import { StETHERC4626 } from "../src/assets/StETHERC4626.sol";

// Uniswap interfaces
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";
import { IWrappedETH } from "../src/interfaces/IWrappedETH.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";

contract DeployScript is BaseScript {
    using SafeERC20 for IERC20;

    Vault public vault;

    uint64 strike1 = 5000_00000000;
    uint64 strike2 = 10000_00000000;
    uint64 strike3 = 15000_00000000;

    // Uniswap mainnet addresses
    address public mainnet_UniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public mainnet_NonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public mainnet_SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public mainnet_QuoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address public mainnet_weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public mainnet_aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    IUniswapV3Pool public uniswapV3Pool;
    INonfungiblePositionManager public manager;

    function run() public {
        init();

        vm.startBroadcast(pk);

        FakeOracle oracle = new FakeOracle();
        oracle.setPrice(1999_00000000);

        StETHERC4626 asset = new StETHERC4626(steth);
        vault = new Vault(address(asset), address(oracle));

        if (true) {
            deployUniswap(strike1, 73044756656988589698425290750, 85935007831751276823975034880);
            deployUniswap(strike2, 68613601432514894825936388100, 91484801910019859767915184130);
            deployUniswap(strike3, 63875786711408440335392571390, 98270441094474503294235443200);
        }

        Router router = new Router(address(vault),
                                   address(weth),
                                   address(steth),
                                   address(wsteth),
                                   mainnet_UniswapV3Factory,
                                   mainnet_SwapRouter,
                                   mainnet_QuoterV2,
                                   mainnet_aavePool);

        vm.stopBroadcast();

        {
            string memory objName = string.concat("deploy");
            string memory json;

            json = vm.serializeAddress(objName, "address_oracle", address(oracle));
            json = vm.serializeAddress(objName, "address_vault", address(vault));
            json = vm.serializeAddress(objName, "address_router", address(router));
            json = vm.serializeAddress(objName, "address_yMulti", address(vault.yMulti()));
            json = vm.serializeAddress(objName, "address_hodlMulti", address(vault.hodlMulti()));

            json = vm.serializeString(objName, "contractName_oracle", "FakeOracle");
            json = vm.serializeString(objName, "contractName_vault", "Vault");
            json = vm.serializeString(objName, "contractName_router", "Router");
            json = vm.serializeString(objName, "contractName_yMulti", "YMultiToken");
            json = vm.serializeString(objName, "contractName_hodlMulti", "HodlMultiToken");

            vm.writeJson(json, string.concat("./json/deploy-eth.",
                                             vm.envString("NETWORK"),
                                             ".json"));
        }
    }

    function deployUniswap(uint64 strike, uint160 initPrice, uint160 initPriceInv) public {
        address hodl1 = vault.deployERC20(strike);

        (address token0, address token1) = hodl1 < weth
            ? (hodl1, weth)
            : (weth, hodl1);

        if (hodl1 > weth) {
            initPrice = initPriceInv;
        }

        uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(mainnet_UniswapV3Factory).getPool(token0, token1, 3000));

        if (address(uniswapV3Pool) == address(0)) {
            uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(mainnet_UniswapV3Factory).createPool(token0, token1, 3000));

            IUniswapV3Pool(uniswapV3Pool).initialize(initPrice);
        }

        // Get some tokens
        uint256 amount = 100 ether;

        IWrappedETH(address(weth)).deposit{value: amount}();
        vault.mint{value: amount + 100}(strike);  // Add 100 for stETH off-by-one

        // Add initial liquidity
        manager = INonfungiblePositionManager(mainnet_NonfungiblePositionManager);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000,
            tickLower: -180000,
            tickUpper: 222000,
            amount0Desired: amount,
            amount1Desired: amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployerAddress,
            deadline: block.timestamp + 1 days });
        IERC20(params.token0).approve(address(manager), amount);
        IERC20(params.token1).approve(address(manager), amount);
        manager.mint(params);
    }
}
