// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { IAsset } from "./interfaces/IAsset.sol";

import { HodlMultiToken } from "./multi/HodlMultiToken.sol";
import { YMultiToken } from "./multi/YMultiToken.sol";
import { HodlToken } from  "./single/HodlToken.sol";

import { StETHERC4626 } from "./assets/StETHERC4626.sol";


contract Vault {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION_FACTOR = 1 ether;

    uint32 public nextId = 1;

    IOracle public immutable oracle;

    IAsset public immutable asset;

    HodlMultiToken public immutable hodlMulti;
    YMultiToken public immutable yMulti;

    // keep track of deployed erc20 hodl tokens
    mapping (uint64 strike => address token) public deployments;

    // track staked hodl tokens, which are eligible for redemption
    struct HodlStake {
        address user;
        uint64 strike;
        uint32 epochId;
        uint256 amount;
    }
    mapping (uint32 stakedId => HodlStake) public hodlStakes;

    struct YStake {
        address user;
        uint64 strike;
        uint32 epochId;
        uint256 amount;
        uint256 claimed;
        uint256 acc;
    }
    mapping (uint32 stakeId => YStake) public yStakes;

    // amount of y tokens staked in an epoch
    mapping (uint32 epochId => uint256 amount) public yStaked;

    // amount of y tokens staked in total
    uint256 public yStakedTotal;

    // for terminated epoch, the final yield per token
    mapping (uint32 epochId => uint256 ypt) public terminalYieldPerToken;

    // amount of total deposits
    uint256 public deposits;

    // amount of yield claimed
    uint256 public claimed;

    // checkpointed yield per token, updated when deposits go up/down
    uint256 public yieldPerTokenAcc;

    // checkpointed cumulative yield, updated when deposits go up/down
    uint256 public cumulativeYieldAcc;

    // track yield per token and cumulative yield on a per epoch basis
    struct EpochInfo {
        uint64 strike;
        uint256 yieldPerTokenAcc;
        uint256 cumulativeYieldAcc;
    }
    mapping (uint32 epochId => EpochInfo) infos;

    // Map strike to active epoch ID
    mapping (uint64 staked => uint32 epochId) public epochs;

    // Events
    event Triggered(uint64 indexed strike,
                    uint32 indexed epoch,
                    uint256 timestamp);

    event Mint(address indexed user,
               uint256 indexed strike,
               uint256 amount);

    event HodlStaked(address indexed user,
                     uint64 indexed strike,
                     uint32 indexed stakeId,
                     uint256 amount);

    event HodlUnstaked(address indexed user,
                       uint64 indexed strike,
                       uint32 indexed stakeId,
                       uint256 amount);

    event HodlRedeemed(address indexed user,
                       uint64 indexed strike,
                       uint32 indexed stakeId,
                       uint256 amount);

    event YStaked(address indexed user,
                  uint64 indexed strike,
                  uint32 indexed stakeId,
                  uint256 amount);

    event YUnstaked(address indexed user,
                    uint64 indexed strike,
                    uint32 indexed stakeId,
                    uint256 amount);

    constructor(address asset_, address oracle_) {
        require(oracle_ != address(0));

        asset = IAsset(asset_);
        oracle = IOracle(oracle_);

        hodlMulti = new HodlMultiToken("");
        yMulti = new YMultiToken("", address(this));
    }

    function deployERC20(uint64 strike) public returns (address) {
        if (deployments[strike] != address(0)) {
            return deployments[strike];
        }

        HodlToken hodl = new HodlToken(address(hodlMulti), strike);
        hodlMulti.authorize(address(hodl));

        deployments[strike] = address(hodl);

        return address(hodl);
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function _checkpoint(uint32 epochId) internal {
        uint256 ypt = yieldPerToken();
        uint256 total = totalCumulativeYield();

        infos[epochId].cumulativeYieldAcc = cumulativeYield(epochId);
        infos[epochId].yieldPerTokenAcc = ypt;

        yieldPerTokenAcc = ypt;
        cumulativeYieldAcc = total;
    }

    function mint(uint64 strike) external payable {
        require(oracle.price(0) <= strike, "strike too low");

        IERC20 token = IERC20(asset.asset());

        uint256 before = token.balanceOf(address(this));
        asset.wrap{value: msg.value}(0);
        /* token.safeTransferFrom(msg.sender, address(this), amount); */
        uint256 amount = token.balanceOf(address(this)) - before;

        token.approve(address(asset), amount);
        asset.deposit(amount, address(this));
        deposits += amount;

        // create the epoch if needed
        if (epochs[strike] == 0) {
            infos[nextId].strike = strike;
            epochs[strike] = nextId++;
        }

        // mint hodl + y
        hodlMulti.mint(msg.sender, strike, amount);
        yMulti.mint(msg.sender, strike, amount);

        emit Mint(msg.sender, strike, amount);
    }

    function canRedeem(uint32 stakeId) public view returns (bool) {
        HodlStake storage stk = hodlStakes[stakeId];

        // Check if there is anything to redeem
        if (stk.amount == 0) {
            return false;
        }

        // Check if price is currently above strike
        if (oracle.price(0) >= stk.strike) {
            return true;
        }

        // Check if this is a passed epoch
        if (stk.epochId != epochs[stk.strike]) {
            return true;
        }

        return false;
    }

    function _withdraw(uint256 amount, address user) private returns (uint256) {
        asset.withdraw(_min(amount, asset.maxWithdraw(address(this))),
                       user,
                       address(this));
        return amount;
    }

    function merge(uint64 strike, uint256 amount) external {
        require(hodlMulti.balanceOf(msg.sender, strike) >= amount);
        require(yMulti.balanceOf(msg.sender, strike) >= amount);

        hodlMulti.burn(msg.sender, strike, amount);
        yMulti.burn(msg.sender, strike, amount);

        amount = _withdraw(amount, msg.sender);

        deposits -= amount;
    }

    function redeem(uint256 amount, uint32 stakeId) external {
        // Redeem via staked hodl token
        HodlStake storage stk = hodlStakes[stakeId];

        require(stk.user == msg.sender, "redeem user");
        require(stk.amount >= amount, "redeem amount");
        require(canRedeem(stakeId), "cannot redeem");

        // burn the specified hodl stake
        stk.amount -= amount;

        uint32 epochId = epochs[stk.strike];

        if (epochId != 0) {
            // checkpoint this strike, to prevent yield accumulation
            _checkpoint(epochId);

            // record the ypt at redemption time
            terminalYieldPerToken[epochId] = yieldPerToken();

            // update accounting for staked y tokens
            yStakedTotal -= yStaked[epochId];
            yStaked[epochId] = 0;

            // don't checkpoint again, trigger new epoch
            epochs[stk.strike] = 0;
        }

        // burn all staked y tokens at that strike
        yMulti.burnStrike(stk.strike);

        amount = _withdraw(amount, msg.sender);
        deposits -= amount;

        emit HodlRedeemed(msg.sender, stk.strike, stakeId, amount);
    }

    function yStake(uint64 strike, uint256 amount, address user) public returns (uint32) {

        require(yMulti.balanceOf(msg.sender, strike) >= amount, "y stake balance");
        uint32 epochId = epochs[strike];

        _checkpoint(epochId);

        yMulti.burn(msg.sender, strike, amount);
        uint32 id = nextId++;

        uint256 ypt = yieldPerToken();
        yStakes[id] = YStake({
            user: user,
            strike: strike,
            epochId: epochId,
            amount: amount,
            claimed: ypt * amount / PRECISION_FACTOR,
            acc: 0 });

        yStaked[epochId] += amount;
        yStakedTotal += amount;

        emit YStaked(user, strike, id, amount);

        return id;
    }

    function yUnstake(uint32 stakeId, address user) public {
        YStake storage stk = yStakes[stakeId];
        require(stk.user == msg.sender, "y unstake user");
        require(stk.amount > 0, "y unstake zero");

        _checkpoint(stk.epochId);
        stk.acc = stk.claimed + claimable(stakeId);

        yStaked[stk.epochId] -= stk.amount;
        yStakedTotal -= stk.amount;
        yMulti.mint(user, stk.strike, stk.amount);

        stk.amount = 0;

        emit YUnstaked(user, stk.strike, stakeId, stk.amount);
    }

    function _stakeYpt(uint32 stakeId) internal view returns (uint256) {
        YStake storage stk = yStakes[stakeId];
        if (epochs[stk.strike] == stk.epochId) {
            // active epoch
            return yieldPerToken();
        } else {
            // passed epoch
            return terminalYieldPerToken[stk.epochId];
        }
    }

    function claimable(uint32 stakeId) public view returns (uint256) {
        YStake storage stk = yStakes[stakeId];

        uint256 c;
        if (stk.amount == 0) {
            // unstaked, use saved value
            c = stk.acc;
        } else {
            // staked, use live value
            assert(stk.acc == 0);  // only set when unstaking
            uint256 ypt = _stakeYpt(stakeId);
            c = ypt * stk.amount / PRECISION_FACTOR;
        }

        return c - stk.claimed;
    }

    function claim(uint32 stakeId) public {
        YStake storage stk = yStakes[stakeId];
        require(stk.user == msg.sender, "y claim user");

        uint256 amount = _withdraw(claimable(stakeId), msg.sender);
        stk.claimed += amount;
        claimed += amount;
    }

    function hodlStake(uint64 strike, uint256 amount, address user) public returns (uint32) {
        require(hodlMulti.balanceOf(msg.sender, strike) >= amount, "hodl stake balance");

        hodlMulti.burn(msg.sender, strike, amount);

        uint32 id = nextId++;
        hodlStakes[id] = HodlStake({
            user: user,
            strike: strike,
            epochId: epochs[strike],
            amount: amount });

        emit HodlStaked(user, strike, id, amount);

        return id;
    }

    function hodlUnstake(uint32 stakeId, uint256 amount, address user) public {
        HodlStake storage stk = hodlStakes[stakeId];
        require(stk.user == msg.sender, "hodl unstake user");
        require(stk.amount >= amount, "hodl unstake zero");

        hodlMulti.mint(user, stk.strike, amount);

        stk.amount -= amount;

        emit HodlUnstaked(user, stk.strike, stakeId, amount);
    }

    function yieldPerToken() public view returns (uint256) {
        uint256 deltaCumulative = totalCumulativeYield() - cumulativeYieldAcc;
        
        if (yStakedTotal == 0) return yieldPerTokenAcc;
        uint256 incr = deltaCumulative * PRECISION_FACTOR / yStakedTotal;
        return yieldPerTokenAcc + incr;
    }

    function cumulativeYield(uint32 epochId) public view returns (uint256) {
        require(epochId < nextId, "invalid epoch");

        uint256 ypt;
        uint64 strike = infos[epochId].strike;
        if (epochs[strike] == epochId) {
            // active epoch
            ypt = yieldPerToken() - infos[epochId].yieldPerTokenAcc;
        } else {
            // passed epoch
            ypt = terminalYieldPerToken[epochId] - infos[epochId].yieldPerTokenAcc;
        }

        return (infos[epochId].cumulativeYieldAcc +
                yStaked[epochId] * ypt / PRECISION_FACTOR);
    }

    function totalCumulativeYield() public view returns (uint256) {
        uint256 balance = asset.convertToAssets(asset.balanceOf(address(this)));
        uint256 delta = balance < deposits ? 0 : balance - deposits;
        uint256 result = delta + claimed;
        return result;
    }
}
