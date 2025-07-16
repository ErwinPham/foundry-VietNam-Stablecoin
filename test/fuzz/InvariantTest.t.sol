//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {VietNamStableCoin} from "../../src/VietNamStableCoin.sol";
import {VNDCEngine} from "../../src/VNDCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployVNDC} from "../../script/DeployVNDC.s.sol";

contract InvariantTest is StdInvariant, Test {
    VietNamStableCoin vndc;
    VNDCEngine vndce;
    HelperConfig config;
    DeployVNDC deployer;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployVNDC();
        (vndc, vndce, config) = deployer.run();
        (weth, wbtc,,,) = config.activeNetworkConfig();
        handler = new Handler(vndc, vndce);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = vndc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(vndce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(vndce));

        uint256 totalWethInUsd = vndce.getValueInUsd(weth, totalWethDeposited);
        uint256 totalWbtcInUsd = vndce.getValueInUsd(wbtc, totalWbtcDeposited);

        console.log("Total Supply: ", totalSupply);
        console.log("Weth: ", totalWethInUsd);
        console.log("Wbtc: ", totalWbtcInUsd);

        assert(totalSupply <= totalWethInUsd + totalWbtcInUsd);
    }

    function invariant_getterUnchange() public view {
        vndce.getLiquidationBonus();
        vndce.getPrecision();
    }
}
