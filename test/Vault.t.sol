// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from  "./BaseTest.sol";
import { FakeOracle } from  "./helpers/FakeOracle.sol";

import { IStEth } from "../src/interfaces/IStEth.sol";
import { ILiquidityPool } from "../src/interfaces/ILiquidityPool.sol";
import { Vault } from  "../src/Vault.sol";
import { Router } from  "../src/Router.sol";
import { StETHERC4626 } from "../src/assets/StETHERC4626.sol";
import { HodlToken } from  "../src/single/HodlToken.sol";


contract VaultTest is BaseTest {
    Vault vault;

    FakeOracle oracle;

    uint64 strike1 = 2000_00000000;
    uint64 strike2 = 3000_00000000;
    uint64 strike3 = 4000_00000000;

    function setUp() public {
        init();
    }

    function initVault() public {
        oracle = new FakeOracle();
        oracle.setPrice(1999_00000000);
        StETHERC4626 asset = new StETHERC4626(steth);
        vault = new Vault(address(asset), address(oracle));
    }

    function testVault() public {
        initVault();

        // mint hodl tokens
        vm.startPrank(alice);
        uint32 epoch1 = vault.nextId();
        vault.mint{value: 3 ether}(strike1);
        vm.stopPrank();

        vm.startPrank(bob);

        uint32 epoch2 = vault.nextId();
        vault.mint{value: 4 ether}(strike2);
        vm.stopPrank();

        vm.startPrank(chad);
        uint32 epoch3 = vault.nextId();
        vault.mint{value: 8 ether}(strike3);
        vm.stopPrank();

        assertClose(vault.hodlMulti().balanceOf(alice, strike1), 3 ether, 10);
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), 0);
        assertClose(vault.yMulti().balanceOf(alice, strike1), 3 ether, 10);
        assertEq(vault.yMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike1), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike2), 0);
        assertClose(vault.hodlMulti().balanceOf(bob, strike2), 4 ether, 10);
        assertEq(vault.hodlMulti().balanceOf(chad, strike2), 0);
        assertEq(vault.yMulti().balanceOf(alice, strike2), 0);
        assertClose(vault.yMulti().balanceOf(bob, strike2), 4 ether, 10);
        assertEq(vault.yMulti().balanceOf(chad, strike2), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike3), 0);
        assertClose(vault.hodlMulti().balanceOf(chad, strike3), 8 ether, 10);
        assertEq(vault.yMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike3), 0);
        assertClose(vault.yMulti().balanceOf(chad, strike3), 8 ether, 10);

        // stake hodl tokens
        vm.startPrank(alice);
        uint32 stake1 = vault.hodlStake(strike1, 2 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.hodlStake(strike2, 4 ether - 2, bob);
        vm.stopPrank();

        vm.startPrank(chad);
        uint32 stake3 = vault.hodlStake(strike3, 8 ether - 2, chad);
        vm.stopPrank();

        assertClose(vault.hodlMulti().balanceOf(alice, strike1), 1 ether, 10);
        assertClose(vault.yMulti().balanceOf(alice, strike1), 3 ether, 10);

        assertClose(vault.hodlMulti().balanceOf(bob, strike2), 0, 10);
        assertClose(vault.yMulti().balanceOf(bob, strike2), 4 ether, 10);

        assertClose(vault.hodlMulti().balanceOf(chad, strike3), 0, 10);
        assertClose(vault.yMulti().balanceOf(chad, strike3), 8 ether, 10);

        // stake y token
        vm.startPrank(alice);
        uint32 stake4 = vault.yStake(strike1, 1 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        uint32 stake5 = vault.yStake(strike2, 4 ether - 2, bob);
        vm.stopPrank();

        vm.startPrank(chad);
        uint32 stake6 = vault.yStake(strike3, 8 ether, chad);
        vm.stopPrank();

        assertClose(vault.yMulti().balanceOf(alice, strike1), 2 ether, 10);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);

        assertClose(vault.yStakedTotal(), 13 ether, 10);

        // simulate yield, stETH balance grows, verify y token receives yield

        simulateYield(0.13 ether + 1);

        assertClose(vault.totalCumulativeYield(), 0.13 ether, 10);
        assertClose(vault.cumulativeYield(epoch1), 0.01 ether, 10);
        assertClose(vault.cumulativeYield(epoch2), 0.04 ether, 10);
        assertClose(vault.cumulativeYield(epoch3), 0.08 ether, 10);

        // verify claimable yields + claim
        assertClose(vault.claimable(stake4), 0.01 ether, 10);
        assertClose(vault.claimable(stake5), 0.04 ether, 10);
        assertClose(vault.claimable(stake6), 0.08 ether, 10);

        vm.expectRevert("y claim user");
        vault.claim(stake4);

        claimAndVerify(stake4, alice, 0.01 ether, true);
        claimAndVerify(stake5, bob, 0.04 ether, true);
        claimAndVerify(stake6, chad, 0.08 ether, true);

        // move price above strike1, verify redeem via hodl token

        vm.startPrank(alice);
        vm.expectRevert("cannot redeem");
        vault.redeem(1 ether, stake1);
        vm.stopPrank();

        oracle.setPrice(strike1 + 1);

        assertClose(IERC20(steth).balanceOf(alice), 0 ether, 10);

        vm.startPrank(alice);
        vault.redeem(1 ether, stake1);
        vm.stopPrank();

        assertClose(vault.yStakedTotal(), 12 ether, 10);

        // unstaked y tokens should be burned

        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);

        assertClose(IERC20(steth).balanceOf(alice), 1 ether, 10);
        assertClose(IERC20(steth).balanceOf(bob), 0, 10);
        assertClose(IERC20(steth).balanceOf(chad), 0, 10);


        // simulate more yield, verify only epoch2 and epoch3 get it

        simulateYield(0.12 ether);

        assertClose(vault.cumulativeYield(epoch1), 0.01 ether, 10);
        assertClose(vault.cumulativeYield(epoch2), 0.08 ether, 10);
        assertClose(vault.cumulativeYield(epoch3), 0.16 ether, 100);

        // move price above both strike2 and strike3, but only strike3 claims

        oracle.setPrice(strike3 + 1);

        assertClose(IERC20(steth).balanceOf(chad), 0 ether, 10);

        assertEq(vault.yStaked(epoch1), 0);
        assertClose(vault.yStaked(epoch2), 4 ether, 10);
        assertClose(vault.yStaked(epoch3), 8 ether, 10);
        assertClose(vault.yStakedTotal(), 12 ether, 10);

        vm.startPrank(chad);
        vault.redeem(4 ether, stake3);
        vm.stopPrank();

        assertEq(vault.yStaked(epoch1), 0);
        assertClose(vault.yStaked(epoch2), 4 ether, 10);
        assertEq(vault.yStaked(epoch3), 0);
        assertClose(vault.yStakedTotal(), 4 ether, 10);

        assertClose(IERC20(steth).balanceOf(alice), 1 ether, 10);
        assertClose(IERC20(steth).balanceOf(bob), 0, 10);
        assertClose(IERC20(steth).balanceOf(chad), 4 ether, 10);

        simulateYield(0.08 ether);

        assertClose(vault.cumulativeYield(epoch1), 0.01 ether, 100);
        assertClose(vault.cumulativeYield(epoch2), 0.16 ether, 100);  // not redeemed, gets all the increase
        assertClose(vault.cumulativeYield(epoch3), 0.16 ether, 100);  // [strike3] redeemed, so no increase

        // can mint at strike3 again, but only once price goes down
        vm.startPrank(chad);
        vm.expectRevert("strike too low");
        vault.mint{value: 4 ether}(strike3);
        vm.stopPrank();

        oracle.setPrice(strike3 - 1);

        vm.startPrank(chad);
        uint32 epoch4 = vault.nextId();
        vault.mint{value: 8 ether}(strike3);
        assertClose(vault.hodlMulti().balanceOf(chad, strike3), 8 ether, 10);
        vm.stopPrank();

        // epoch for strike3 unchanged until redeem
        assertClose(vault.cumulativeYield(epoch3), 0.16 ether, 100);

        // degen gets some yield, verify address level accounting
        
        simulateYield(0.08 ether);

        assertEq(vault.yStaked(epoch1), 0);
        assertClose(vault.yStaked(epoch2), 4 ether, 10);
        assertEq(vault.yStaked(epoch3), 0);

        assertClose(vault.cumulativeYield(epoch1), 0.01 ether, 100);
        assertClose(vault.cumulativeYield(epoch2), 0.24 ether, 100);
        assertClose(vault.cumulativeYield(epoch3), 0.16 ether, 100);  // [strike3] redeemed, so no increase
        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        // transfer y tokens, verify address level accounting

        vm.startPrank(chad);
        assertClose(vault.yMulti().balanceOf(chad, strike3), 8 ether, 100);
        vault.hodlStake(strike3, 8 ether - 1, chad);
        vault.yMulti().safeTransferFrom(chad, degen, strike3, 4 ether, "");
        assertClose(vault.yMulti().balanceOf(chad, strike3), 4 ether, 100);
        assertClose(vault.yMulti().balanceOf(degen, strike3), 4 ether, 100);
        vm.stopPrank();

        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        // simulate yield after y token transfer, verify address level accounting
        vm.startPrank(degen);
        vault.yStake(strike3, 4 ether, degen);
        vm.stopPrank();

        assertClose(vault.yStakedTotal(), 8 ether, 10);
        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        simulateYield(0.08 ether);

        assertEq(vault.yStaked(epoch1), 0);
        assertClose(vault.yStaked(epoch2), 4 ether, 10);
        assertEq(vault.yStaked(epoch3), 0);
        assertClose(vault.yStaked(epoch4), 4 ether, 10);
        assertClose(vault.yStakedTotal(), 8 ether, 10);

        assertClose(vault.cumulativeYield(epoch1), 0.01 ether, 100);
        assertClose(vault.cumulativeYield(epoch2), 0.28 ether, 100);
        assertClose(vault.cumulativeYield(epoch3), 0.16 ether, 100);  // [strike3] redeemed, so no increase
        assertClose(vault.cumulativeYield(epoch4), 0.04 ether, 100);  // [strike3] staked in new epoch
    }

    function testERC20() public {
        initVault();

        // mint hodl tokens
        vm.startPrank(alice);
        vault.mint{value: 1 ether}(strike1);
        vm.stopPrank();

        address hodl1Address = vault.deployERC20(strike1);

        // deploys should be saved
        assertEq(hodl1Address, vault.deployERC20(strike1));

        HodlToken hodl1 = HodlToken(hodl1Address);

        assertEq(vault.hodlMulti().totalSupply(strike1), hodl1.totalSupply());

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), 1 ether - 2);

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), hodl1.balanceOf(alice));
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), hodl1.balanceOf(bob));
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), hodl1.balanceOf(chad));
        assertEq(vault.hodlMulti().balanceOf(degen, strike1), hodl1.balanceOf(degen));

        vm.startPrank(alice);
        hodl1.transfer(bob, 0.1 ether);
        vm.stopPrank();

        assertEq(hodl1.balanceOf(alice), 0.9 ether - 2);
        assertEq(hodl1.balanceOf(bob), 0.1 ether);

        vm.startPrank(degen);
        vm.expectRevert("not authorized");
        hodl1.transferFrom(alice, chad, 0.2 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        hodl1.approve(degen, 0.2 ether);
        vm.stopPrank();

        assertEq(hodl1.allowance(alice, degen), 0.2 ether);

        vm.startPrank(degen);
        vm.expectRevert("not authorized");
        hodl1.transferFrom(alice, chad, 0.3 ether);

        hodl1.transferFrom(alice, chad, 0.2 ether);

        vm.expectRevert("not authorized");
        hodl1.transferFrom(alice, chad, 0.2 ether);
        vm.stopPrank();

        assertEq(hodl1.balanceOf(alice), 0.7 ether - 2);
        assertEq(hodl1.balanceOf(bob), 0.1 ether);
        assertEq(hodl1.balanceOf(chad), 0.2 ether);
        assertEq(hodl1.balanceOf(degen), 0);

        assertEq(vault.hodlMulti().totalSupply(strike1), hodl1.totalSupply());

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), hodl1.balanceOf(alice));
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), hodl1.balanceOf(bob));
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), hodl1.balanceOf(chad));
        assertEq(vault.hodlMulti().balanceOf(degen, strike1), hodl1.balanceOf(degen));
    }

    function testStrikeReuse() public {
        initVault();

        vm.startPrank(alice);

        // mint hodl tokens
        vault.mint{value: 4 ether}(strike1);

        // stake 2 of 4 before strike hits
        uint32 stake1 = vault.hodlStake(strike1, 2 ether, alice);

        // strike hits
        oracle.setPrice(strike1 + 1);

        // redeem 1 of 2 staked
        vault.redeem(1 ether, stake1);

        // go below strike
        oracle.setPrice(strike1 - 1);

        // redeem 1 remaining staked
        vault.redeem(1 ether, stake1);

        // stake 1 at same strike
        uint32 stake2 = vault.hodlStake(strike1, 1 ether, alice);

        // the newly staked tokens cannot be redeemed
        vm.expectRevert("cannot redeem");
        vault.redeem(1 ether, stake2);

        // strike hits
        oracle.setPrice(strike1 + 1);

        // redeem the one we staked, now that they hit the strike
        vault.redeem(1 ether, stake2);

        // stake and redeem last 1 at that strike
        uint32 stake3 = vault.hodlStake(strike1, 1 ether - 10, alice);
        vault.redeem(1 ether - 10, stake3);

        assertClose(IERC20(steth).balanceOf(alice), 4 ether, 100);

        vm.stopPrank();
    }

    function testUnstakeY() public {
        initVault();

        // mint hodl tokens
        vm.startPrank(alice);
        vault.mint{value: 4 ether}(strike1);
        vm.stopPrank();

        // stake y token
        vm.startPrank(alice);
        uint32 stake1 = vault.yStake(strike1, 1 ether, alice);
        vm.stopPrank();

        // verify it gets yield
        simulateYield(0.1 ether);

        assertClose(vault.totalCumulativeYield(), 0.1 ether, 100);
        assertClose(vault.claimable(stake1), 0.1 ether, 100);
        assertClose(vault.yMulti().balanceOf(alice, strike1), 3 ether, 100);

        // unstake and verify no yield
        vm.startPrank(alice);
        vault.yUnstake(stake1, alice);
        vm.stopPrank();

        assertClose(vault.yMulti().balanceOf(alice, strike1), 4 ether, 100);

        simulateYield(0.1 ether);

        assertClose(vault.totalCumulativeYield(), 0.2 ether, 10);
        assertClose(vault.claimable(stake1), 0.1 ether, 10);

        // lets do a bit more complicated: two stakes + unstake + multi yield events
        vm.startPrank(alice);
        vault.yMulti().safeTransferFrom(alice, bob, strike1, 2 ether, "");
        vm.stopPrank();

        assertClose(vault.yMulti().balanceOf(alice, strike1), 2 ether, 100);
        assertClose(vault.yMulti().balanceOf(bob, strike1), 2 ether, 100);

        // alice stakes 2, bob stakes 1n
        vm.startPrank(alice);
        uint32 stake2 = vault.yStake(strike1, 2 ether - 2, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        uint32 stake3 = vault.yStake(strike1, 1 ether, bob);
        vm.stopPrank();

        assertClose(vault.yMulti().balanceOf(alice, strike1), 0, 100);
        assertClose(vault.yMulti().balanceOf(bob, strike1), 1 ether, 100);

        // check yield distributes and claims correctly
        simulateYield(0.3 ether);

        assertClose(vault.totalCumulativeYield(), 0.5 ether, 100);

        assertClose(vault.claimable(stake1), 0.1 ether, 100);
        assertClose(vault.claimable(stake2), 0.2 ether, 100);
        assertClose(vault.claimable(stake3), 0.1 ether, 100);

        // alice claims
        claimAndVerify(stake1, alice, 0.1 ether, true);
        claimAndVerify(stake2, alice, 0.2 ether, true);

        assertClose(vault.claimable(stake1), 0, 0);
        assertClose(vault.claimable(stake2), 0, 0);
        assertClose(vault.claimable(stake3), 0.1 ether, 100);

        // alice unstakes her tokens, check that it still works
        vm.startPrank(alice);
        vault.yUnstake(stake2, alice);
        vm.stopPrank();

        assertClose(vault.claimable(stake1), 0, 0);
        assertClose(vault.claimable(stake2), 0, 0);
        assertClose(vault.claimable(stake3), 0.1 ether, 100);

        simulateYield(0.2 ether);

        assertClose(vault.claimable(stake1), 0, 0);
        assertClose(vault.claimable(stake2), 0, 100);
        assertClose(vault.claimable(stake3), 0.3 ether, 100);

        // bob claims, then alice stakes for chad
        claimAndVerify(stake3, bob, 0.3 ether, true);

        // stake y token
        vm.startPrank(alice);
        uint32 stake4 = vault.yStake(strike1, 1 ether, chad);
        vm.stopPrank();

        simulateYield(0.2 ether);

        assertClose(vault.claimable(stake1), 0, 0);
        assertClose(vault.claimable(stake2), 0, 100);
        assertClose(vault.claimable(stake3), 0.1 ether, 100);
        assertClose(vault.claimable(stake4), 0.1 ether, 100);

        // everyone claims
        claimAndVerify(stake3, bob, 0.1 ether, true);
        claimAndVerify(stake4, chad, 0.1 ether, true);

        assertClose(vault.claimable(stake1), 0, 100);
        assertClose(vault.claimable(stake2), 0, 100);
        assertClose(vault.claimable(stake3), 0, 100);
        assertClose(vault.claimable(stake4), 0, 100);
    }

    function testUnstakeHodl() public {
        initVault();

        // mint hodl tokens
        vm.startPrank(alice);
        vault.mint{value: 4 ether}(strike1);
        vm.stopPrank();

        // stake hodl token
        vm.startPrank(alice);
        uint32 stake1 = vault.hodlStake(strike1, 2 ether, alice);
        vm.stopPrank();

        assertClose(vault.hodlMulti().balanceOf(alice, strike1), 2 ether, 10);
        assertClose(vault.hodlMulti().balanceOf(bob, strike1), 0, 10);
        {
            ( , , , uint256 amount) = vault.hodlStakes(stake1);
            assertClose(amount, 2 ether, 10);
        }

        // unstake 1 hodl to bob, then hit strike and check redemption
        vm.startPrank(alice);
        vault.hodlUnstake(stake1, 1 ether, bob);
        vm.stopPrank();

        assertClose(vault.hodlMulti().balanceOf(alice, strike1), 2 ether, 10);
        assertClose(vault.hodlMulti().balanceOf(bob, strike1), 1 ether, 10);

        vm.startPrank(bob);
        uint32 stake2 = vault.hodlStake(strike1, 1 ether, bob);
        vm.stopPrank();

        assertClose(vault.hodlMulti().balanceOf(alice, strike1), 2 ether, 10);
        assertClose(vault.hodlMulti().balanceOf(bob, strike1), 0, 10);

        {
            ( , , , uint256 amount1) = vault.hodlStakes(stake1);
            ( , , , uint256 amount2) = vault.hodlStakes(stake2);
            assertClose(amount1, 1 ether, 10);
            assertClose(amount2, 1 ether, 10);
        }

        oracle.setPrice(2001_00000000);

        assertClose(IERC20(steth).balanceOf(alice), 0 ether, 10);
        assertClose(IERC20(steth).balanceOf(bob), 0 ether, 10);

        vm.startPrank(alice);
        vm.expectRevert("redeem amount");
        vault.redeem(1.1 ether, stake1);
        vault.redeem(1 ether, stake1);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.redeem(1 ether, stake2);
        vm.stopPrank();

        assertClose(IERC20(steth).balanceOf(alice), 1 ether, 10);
        assertClose(IERC20(steth).balanceOf(bob), 1 ether, 10);

        {
            ( , , , uint256 amount1) = vault.hodlStakes(stake1);
            ( , , , uint256 amount2) = vault.hodlStakes(stake2);
            assertClose(amount1, 0, 10);
            assertClose(amount2, 0, 10);
        }

        vm.startPrank(alice);
        vm.expectRevert("redeem amount");
        vault.redeem(1 ether, stake1);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("redeem amount");
        vault.redeem(1 ether, stake2);
        vm.stopPrank();
    }

    function simulateYield(uint256 amount) internal {
        IStEth(steth).submit{value: amount}(address(0));
        IERC20(steth).transfer(address(vault.asset()), amount);
    }

    function claimAndVerify(uint32 stakeId, address user, uint256 amount, bool dumpCoins) internal {
        assertClose(vault.claimable(stakeId), amount, 10);

        uint256 before = IERC20(steth).balanceOf(user);

        vm.startPrank(user);
        vault.claim(stakeId);
        vm.stopPrank();

        uint256 delta = IERC20(steth).balanceOf(user) - before;
        assertClose(delta, amount, 10);

        assertClose(vault.claimable(stakeId), 0, 10);

        vm.startPrank(user);
        vault.claim(stakeId);
        vm.stopPrank();

        delta = IERC20(steth).balanceOf(user) - before;
        assertClose(delta, amount, 10);

        if (dumpCoins) {
            vm.startPrank(user);
            IERC20(steth).transfer(address(123), delta);
            vm.stopPrank();
            assertClose(IERC20(steth).balanceOf(user), before, 10);
        }
    }
}
