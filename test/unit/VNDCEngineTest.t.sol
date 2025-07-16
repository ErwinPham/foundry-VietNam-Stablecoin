//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {VietNamStableCoin} from "../../src/VietNamStableCoin.sol";
import {VNDCEngine} from "../../src/VNDCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {DeployVNDC} from "../../script/DeployVNDC.s.sol";

contract VNDCEngineTest is Test {
    VietNamStableCoin vndc;
    VNDCEngine vndce;
    HelperConfig config;
    DeployVNDC deployer;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    address user = makeAddr("user");
    address liquidator = makeAddr("liquidator");
    uint256 public constant SATRTING_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    function setUp() public {
        deployer = new DeployVNDC();
        (vndc, vndce, config) = deployer.run();
        (weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, SATRTING_BALANCE);
        ERC20Mock(weth).mint(liquidator, COLLATERAL_TO_COVER);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                     MODIFIER                                         //
    //////////////////////////////////////////////////////////////////////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(vndce), AMOUNT_COLLATERAL);
        vndce.despositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintVNDC() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(vndce), AMOUNT_COLLATERAL);
        vndce.depositCollateralAndMintVNDC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                  CONSTRUCTOR TESTS                                   //
    //////////////////////////////////////////////////////////////////////////////////////////

    address[] token;
    address[] tokenAddress;

    function testRevertIfTokenAndAddressNotSameLength() public {
        token = [weth];
        tokenAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.expectRevert(VNDCEngine.VNDCEngine__TokenAndTokenAddressMustBeTheSameLength.selector);
        new VNDCEngine(token, tokenAddress, address(vndc));
    }

    function testTokenPriceFeedPush() public {
        address wethPriceFeed = vndce.getCollateralTokenPriceFeed(address(weth));
        assertEq(wethPriceFeed, wethUsdPriceFeed);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                    Price Test                                        //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testGetTokenAmountFromUsd() public {
        uint256 amountInUsd = 100e18;
        uint256 expectedAmount = 0.05e18;
        assertEq(expectedAmount, vndce.getTokenAmountFromUsd(weth, amountInUsd));
    }

    function testGetUsdValue() public {
        uint256 amount = 10e18;
        uint256 expectedAmount = 20000e18;
        assertEq(expectedAmount, vndce.getValueInUsd(weth, amount));
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                              Deposit Collateral Test                                 //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testDespositCollateralLessThanZero() public {
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__NeedMoreThanZero.selector);
        vndce.despositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDespositCollateralNotAllowedToken() public {
        vm.startPrank(user);
        ERC20Mock fakeToken = new ERC20Mock("fake", "fake", user, 1000e8);
        ERC20Mock(fakeToken).approve(address(vndce), AMOUNT_COLLATERAL);
        vm.expectRevert(VNDCEngine.VNDCEngine__TokenNotAllowed.selector);
        vndce.despositCollateral(address(fakeToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDespositCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(vndce), AMOUNT_COLLATERAL);
        vndce.despositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(address(vndce)), AMOUNT_COLLATERAL);
        assertEq(vndce.getUserCollateralAmount(user, address(weth)), AMOUNT_COLLATERAL);
    }

    function testCanGetAccountInformationAfterDepositing() public depositedCollateral {
        (uint256 totalMinted, uint256 totalCollateralAmountInUsd) = vndce.getAccountInformation(user);
        assertEq(totalMinted, 0);
        assertEq(totalCollateralAmountInUsd, vndce.getValueInUsd(weth, AMOUNT_COLLATERAL));
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                      Deposit Collateral AND MINT VNDC Test                           //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testRevertIfMintVNDCBreakHealthFactor() public {
        uint256 amountCollateral = 10 ether;
        uint256 amountToMint = vndce.getValueInUsd(weth, amountCollateral);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(vndce), amountCollateral);
        vm.expectRevert(VNDCEngine.VNDCEngine__HealthFactorIsBroken.selector);
        vndce.depositCollateralAndMintVNDC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testCanDepositedCollateralAndMintVNDC() public depositedCollateralAndMintVNDC {
        (uint256 totalMinted, uint256 totalCollateralAmountInUsd) = vndce.getAccountInformation(user);
        assertEq(totalMinted, AMOUNT_TO_MINT);
        assertEq(totalCollateralAmountInUsd, vndce.getValueInUsd(weth, AMOUNT_COLLATERAL));
        assertEq(vndc.balanceOf(user), AMOUNT_TO_MINT);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                MINT VNDC Test                                        //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testMintRevertIfHealthFactorIsBroken() public depositedCollateral {
        uint256 amountToMint = vndce.getValueInUsd(weth, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__HealthFactorIsBroken.selector);
        vndce.mintVNDC(amountToMint);
        vm.stopPrank();
    }

    function testRevertIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__NeedMoreThanZero.selector);
        vndce.mintVNDC(0);
        vm.stopPrank();
    }

    function testCanMintVNDC() public depositedCollateral {
        vm.startPrank(user);
        vndce.mintVNDC(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(vndc.balanceOf(user), AMOUNT_TO_MINT);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                   Burn VNDC Test                                     //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testRevertIfAmountToBurnIsZero() public depositedCollateralAndMintVNDC {
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__NeedMoreThanZero.selector);
        vndce.burnVNDC(0);
        vm.stopPrank();
    }

    function testCanBurnVNDC() public depositedCollateralAndMintVNDC {
        vm.startPrank(user);
        vndc.approve(address(vndce), AMOUNT_TO_MINT);
        vndce.burnVNDC(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(vndce.getDebtOfUser(user), 0);
        assertEq(vndc.balanceOf(user), 0);
    }

    function testCantBurnMoreThanUserHas() public depositedCollateralAndMintVNDC {
        vm.prank(user);
        vm.expectRevert();
        vndce.burnVNDC(AMOUNT_TO_MINT * 10);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                              Redeem Collateral Test                                  //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testRedeemCollateralAmountIsZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__NeedMoreThanZero.selector);
        vndce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemNotAllowedCollateral() public depositedCollateral {
        ERC20Mock fakeToken = new ERC20Mock("ff", "ff", user, 1000e8);
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__TokenNotAllowed.selector);
        vndce.redeemCollateral(address(fakeToken), 100);
        vm.stopPrank();
    }

    function testRedeemRevertIfBrokenHealthFactor() public depositedCollateralAndMintVNDC {
        uint256 amountToRedeem = 9.96 ether;
        vm.startPrank(user);
        vm.expectRevert(VNDCEngine.VNDCEngine__HealthFactorIsBroken.selector);
        vndce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateralAndMintVNDC {
        uint256 amountToRedeem = 1 ether;
        vm.startPrank(user);
        vndce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(user), amountToRedeem);
        assertEq(vndce.getUserCollateralAmount(user, weth), AMOUNT_COLLATERAL - amountToRedeem);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                       Redeem Collateral For VNDC Test                                //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testRedeemCallateralAmountIsZero() public depositedCollateralAndMintVNDC {
        vm.startPrank(user);
        vndc.approve(address(vndce), AMOUNT_TO_MINT);
        vm.expectRevert(VNDCEngine.VNDCEngine__NeedMoreThanZero.selector);
        vndce.redeemCollateralAndBurnVNDC(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertIfUserRedeemMoreThanTheyHave() public depositedCollateralAndMintVNDC {
        vm.startPrank(user);
        vndc.approve(address(vndce), AMOUNT_TO_MINT);
        vm.expectRevert();
        vndce.redeemCollateralAndBurnVNDC(weth, AMOUNT_COLLATERAL + 1, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForVNDC() public depositedCollateralAndMintVNDC {
        vm.startPrank(user);
        vndc.approve(address(vndce), AMOUNT_TO_MINT);
        vndce.redeemCollateralAndBurnVNDC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(user), AMOUNT_COLLATERAL);
        assertEq(vndce.getUserCollateralAmount(user, weth), 0);
        assertEq(vndce.getDebtOfUser(user), 0);
        assertEq(vndc.balanceOf(user), 0);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                Health Factor Test                                    //
    //////////////////////////////////////////////////////////////////////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintVNDC {
        uint256 expectedHealthFactor = 100e18;
        uint256 actual = vndce.getHealthFactor(user);
        assertEq(actual, expectedHealthFactor);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                Liquidation Test                                      //
    //////////////////////////////////////////////////////////////////////////////////////////

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(vndce), AMOUNT_COLLATERAL);
        vndce.depositCollateralAndMintVNDC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        int256 ethNewPrice = 15e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethNewPrice);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(vndce), COLLATERAL_TO_COVER);
        vndce.depositCollateralAndMintVNDC(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        vndc.approve(address(vndce), AMOUNT_TO_MINT);
        vndce.liquidate(user, weth, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintVNDC {
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(vndce), COLLATERAL_TO_COVER);
        vndce.depositCollateralAndMintVNDC(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        vm.expectRevert(VNDCEngine.VNDCEngine__UserNotInTheLiquidatedState.selector);
        vndce.liquidate(user, weth, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 expectedRewardCollaterall = vndce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT)
            + ((vndce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) * 10) / 100);

        uint256 userBalance = ERC20Mock(weth).balanceOf(liquidator);
        assertEq(userBalance, expectedRewardCollaterall);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        uint256 moneyLeft = AMOUNT_COLLATERAL
            - (
                vndce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT)
                    + ((vndce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) * 10) / 100)
            );
        assertEq(moneyLeft, vndce.getUserCollateralAmount(user, weth));
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        assertEq(vndce.getDebtOfUser(liquidator), AMOUNT_TO_MINT);
        assertEq(vndce.getDebtOfUser(user), 0);
    }
}
