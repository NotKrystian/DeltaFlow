// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Tracks USDC fee surplus (accounting + optional real USDC held here) as a first-loss buffer.
/// @dev Strict “always profitable” is impossible on-chain; buffers + conservative fees **target** net surplus.
contract FeeSurplus {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    address public strategist;
    /// @dev Sovereign AMM pool this surplus account is bound to (also used for authorization alongside `swapFeeModule`).
    address public pool;
    /// @dev `DeltaFlowCompositeFeeModule` calls `accrueFromPool` after `SovereignPool` invokes `callbackOnSwapEnd` on the module (`msg.sender` to this contract is the fee module, not the pool).
    address public swapFeeModule;

    uint256 public surplusUsdc;

    event SurplusAccrued(uint256 amount);
    event SurplusConsumed(uint256 amount, string reason);
    event StrategistUpdated(address indexed s);
    event PoolUpdated(address indexed p);
    event SwapFeeModuleUpdated(address indexed m);

    error OnlyStrategist();
    error OnlyPool();

    modifier onlyStrategist() {
        if (msg.sender != strategist) revert OnlyStrategist();
        _;
    }

    modifier onlyPool() {
        if (msg.sender != pool) revert OnlyPool();
        _;
    }

    modifier onlyPoolOrSwapFeeModule() {
        if (msg.sender != pool && msg.sender != swapFeeModule) revert OnlyPool();
        _;
    }

    constructor(address _usdc, address _strategist) {
        usdc = IERC20(_usdc);
        strategist = _strategist;
    }

    function setPool(address p) external onlyStrategist {
        pool = p;
        emit PoolUpdated(p);
    }

    function setSwapFeeModule(address m) external onlyStrategist {
        swapFeeModule = m;
        emit SwapFeeModuleUpdated(m);
    }

    function setStrategist(address s) external onlyStrategist {
        strategist = s;
        emit StrategistUpdated(s);
    }

    function depositFrom(address from, uint256 amount) external onlyStrategist {
        if (amount == 0) return;
        usdc.safeTransferFrom(from, address(this), amount);
        surplusUsdc += amount;
        emit SurplusAccrued(amount);
    }

    /// @notice Accounting accrual attributed to swap fees (USDC units, same decimals as token).
    function accrueFromPool(uint256 amount) external onlyPoolOrSwapFeeModule {
        if (amount == 0) return;
        surplusUsdc += amount;
        emit SurplusAccrued(amount);
    }

    function consume(uint256 amount, address to, string calldata reason) external onlyStrategist {
        if (amount == 0) return;
        require(amount <= surplusUsdc, "surplus");
        surplusUsdc -= amount;
        if (to != address(0)) {
            usdc.safeTransfer(to, amount);
        }
        emit SurplusConsumed(amount, reason);
    }
}
