//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {VietNamStableCoin} from "../../src/VietNamStableCoin.sol";
import {VNDCEngine} from "../../src/VNDCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    VietNamStableCoin vndc;
    VNDCEngine vndce;

    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator wethUsdPriceFeed;
    MockV3Aggregator wbtcUsdPriceFeed;

    address[] tokenCollateralList;
    address[] userThatDepositedCollateral;
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(VietNamStableCoin _vndc, VNDCEngine _vndce) {
        vndc = _vndc;
        vndce = _vndce;

        tokenCollateralList = vndce.getCollateralTokens();
        weth = ERC20Mock(tokenCollateralList[0]);
        wbtc = ERC20Mock(tokenCollateralList[1]);
        wethUsdPriceFeed = MockV3Aggregator(vndce.getCollateralTokenPriceFeed(address(weth)));
        wbtcUsdPriceFeed = MockV3Aggregator(vndce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 tokenCollateralSeed, uint256 amountCollateral) public {
        ERC20Mock tokenCollateral = _getCollateralFromSeed(tokenCollateralSeed);
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        ERC20Mock(tokenCollateral).mint(msg.sender, amountCollateral);
        ERC20Mock(tokenCollateral).approve(address(vndce), amountCollateral);
        vndce.despositCollateral(address(tokenCollateral), amountCollateral);
        userThatDepositedCollateral.push(msg.sender);
        vm.stopPrank();
    }

    function mintVNDC(uint256 amount, uint256 addressSeed) public {
        if (userThatDepositedCollateral.length == 0) {
            return;
        }
        address user = userThatDepositedCollateral[addressSeed % userThatDepositedCollateral.length];
        (uint256 totalMinted, uint256 totalCollateralAmountInUsd) = vndce.getAccountInformation(user);
        uint256 maxCanMint = (totalCollateralAmountInUsd / 2) - totalMinted;
        if (maxCanMint < 0) {
            return;
        }
        amount = bound(amount, 0, maxCanMint);

        vm.startPrank(user);
        vndce.mintVNDC(amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 tokenCollateralSeed, uint256 amountCollateral, uint256 addressSeed) public {
        if (userThatDepositedCollateral.length == 0) {
            return;
        }
        address user = userThatDepositedCollateral[addressSeed % userThatDepositedCollateral.length];
        ERC20Mock tokenCollateral = _getCollateralFromSeed(tokenCollateralSeed);
        uint256 maxCanRedeem = vndce.getUserCollateralAmount(user, address(tokenCollateral));
        amountCollateral = bound(amountCollateral, 0, maxCanRedeem);
        if (amountCollateral == 0) {
            return;
        }

        vm.startPrank(user);
        vndce.redeemCollateral(address(tokenCollateral), amountCollateral);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 tokenCollateralSeed) private returns (ERC20Mock) {
        if (tokenCollateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
