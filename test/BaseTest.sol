// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BaseTest is Test {
    using SafeERC20 for IERC20;

    // Tokens
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
 
     // Uniswap
    address public uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public quoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    // Aave
    address public aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    address public alice;
    address public bob;
    address public chad;
    address public degen;
    address public eve;
    address public whale;

    function createUser(uint32 i) public returns (address) {
        string memory mnemonic = "test test test test test test test test test test test junk";
        uint256 privateKey = vm.deriveKey(mnemonic, i);
        address user = vm.addr(privateKey);
        vm.deal(user, 100 ether);
        return user;
    }

    function eq(string memory str1, string memory str2) public pure returns (bool) {
        return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
    }

    function init() public {
        init(0xdeadbeef);

        alice = createUser(0);
        bob = createUser(1);
        chad = createUser(2);
        degen = createUser(3);
        eve = createUser(4);

        whale = createUser(100);
    }

    function init(uint256 fork) public {
        if (fork == 0xdeadbeef) {
            fork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 18260000);
        }

        vm.selectFork(fork);
    }

    function assertClose(uint256 x, uint256 target, uint256 tolerance) public {
        if (x > target) assertTrue(x - target <= tolerance);
        else assertTrue(target - x <= tolerance);
    }
}
