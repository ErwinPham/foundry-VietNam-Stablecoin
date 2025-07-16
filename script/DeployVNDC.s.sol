//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {VietNamStableCoin} from "../src/VietNamStableCoin.sol";
import {VNDCEngine} from "../src/VNDCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployVNDC is Script {
    VietNamStableCoin public vndc;
    VNDCEngine public vndce;
    HelperConfig public config;

    address[] public tokenAddresses;
    address[] public tokenPriceFeedAddresses;

    function run() public returns (VietNamStableCoin, VNDCEngine, HelperConfig) {
        config = new HelperConfig();
        (address weth, address wbtc, address wethUsdPriceFeed, address wbtcUsdPriceFeed, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        tokenPriceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        vndc = new VietNamStableCoin();
        vndce = new VNDCEngine(tokenAddresses, tokenPriceFeedAddresses, address(vndc));
        vndc.transferOwnership(address(vndce));
        vm.stopBroadcast();

        return (vndc, vndce, config);
    }
}
