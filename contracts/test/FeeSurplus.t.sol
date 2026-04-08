// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {FeeSurplus} from "../src/deltaflow/FeeSurplus.sol";

contract FeeSurplusTest is Test {
    address usdc = address(0x1001);
    address strategist = address(0xA11);
    address pool = address(0x2002);
    address feeModule = address(0x3003);

    function test_accrueFromPool_calledBySwapFeeModule_notSovereignPool() public {
        vm.prank(strategist);
        FeeSurplus fs = new FeeSurplus(usdc, strategist);

        vm.startPrank(strategist);
        fs.setPool(pool);
        fs.setSwapFeeModule(feeModule);
        vm.stopPrank();

        vm.prank(feeModule);
        fs.accrueFromPool(123);
        assertEq(fs.surplusUsdc(), 123);
    }

    function test_accrueFromPool_revertsIfUnauthorized() public {
        vm.prank(strategist);
        FeeSurplus fs = new FeeSurplus(usdc, strategist);

        vm.prank(strategist);
        fs.setPool(pool);
        // swapFeeModule not set

        vm.prank(address(0xBAD));
        vm.expectRevert(FeeSurplus.OnlyPool.selector);
        fs.accrueFromPool(1);
    }
}
