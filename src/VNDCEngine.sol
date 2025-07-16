//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VietNamStableCoin} from "./VietNamStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 *  @title VNDCEngine
 *  @author Huy Pham
 *
 *  The system is designed to be as minimal as possible, has the token maintain
 *  a 1 token == $1 peg.
 *  This stablecoin has the properties:
 *  - Exogenous Collateral
 *  - Dollar Pegged
 *  - Algorithmically stable
 *
 *  It is similar to DAI if DAI has no governace, no fees, and was only backed
 *  by WETH and WBTC.
 *
 *  My VNDC system should always be "overcollateralized". At no point, should the value of
 *  all collateral <= the $ backed value of all the VNDC.
 *
 *  @notice This contract is the core of the VNDC system. It handles all the logic for
 *  mining and redeemingDSC,
 *  @notice This contract is Very loosely based on the MakerDAO DSS (DAI) system.
 */
contract VNDCEngine is ReentrancyGuard {
    /**
     * ERROR
     */
    error VNDCEngine__TokenAndTokenAddressMustBeTheSameLength();
    error VNDCEngine__NeedMoreThanZero();
    error VNDCEngine__TokenNotAllowed();
    error VNDCEngine__TransferFailed();
    error VNDCEngine__MintFailed();
    error VNDCEngine__HealthFactorIsBroken();
    error VNDCEngine__UserNotInTheLiquidatedState();
    error VNDCEngine__HealthFactorNotBetter();

    /**
     * TYPE
     */
    using OracleLib for AggregatorV3Interface;

    /**
     * MAPPING
     */
    mapping(address token => address priceFeed) private s_tokenPriceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_VNDCMinted;

    /**
     * VARIABLES
     */
    address[] private s_tokenCollaterals;
    VietNamStableCoin public immutable i_vndc;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    /**
     * EVENTS
     */
    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amountCollateral);
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed tokenCollateral, uint256 amountCollateral
    );

    /**
     * MODIFIER
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert VNDCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenCollateral) {
        if (s_tokenPriceFeed[tokenCollateral] == address(0)) {
            revert VNDCEngine__TokenNotAllowed();
        }
        _;
    }

    /**
     * CONSTRUCTOR
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address vndc) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert VNDCEngine__TokenAndTokenAddressMustBeTheSameLength();
        }

        for (uint256 index = 0; index < tokenAddresses.length; index++) {
            s_tokenPriceFeed[tokenAddresses[index]] = priceFeedAddresses[index];
            s_tokenCollaterals.push(tokenAddresses[index]);
        }

        i_vndc = VietNamStableCoin(vndc);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                           PUBLIC AND EXTERNAL FUNCTIONS                              //
    //////////////////////////////////////////////////////////////////////////////////////////

    /*
    * @notice This function will deposit your collateral and mint VNDC in one transaction.
    * @param tokenCollateral: The address of the token to deposit as collateral.
    * @param amoutCollateral: The amount of collateral to deposit.
    * @param amountVNDCToMint: The amount of VNDC to mint.
    */
    function depositCollateralAndMintVNDC(address tokenCollateral, uint256 amountCollateral, uint256 amountVNDCToMint)
        external
    {
        despositCollateral(tokenCollateral, amountCollateral);
        mintVNDC(amountVNDCToMint);
    }

    /*
    * @notice follows CEI: Check, Effect, Interaction
    * @param tokenCollateral: The address of the token to deposit as collateral.
    * @param amountCollateral: The amount of collateral to deposit
    */
    function despositCollateral(address tokenCollateral, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateral)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateral] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateral, amountCollateral);
        bool success = IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert VNDCEngine__TransferFailed();
        }
    }

    /*
    * @notice follows CEI: Check, Effect, Interaction
    * @param amountVNDCToMint: The amount of vndc to mint.
    * @notice They must have more collateral value than the minimun threshold.
    */
    function mintVNDC(uint256 amountVNDCToMint) public moreThanZero(amountVNDCToMint) nonReentrant {
        s_VNDCMinted[msg.sender] += amountVNDCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_vndc.mint(msg.sender, amountVNDCToMint);
        if (!minted) {
            revert VNDCEngine__MintFailed();
        }
    }

    /*
    * @notice This function will redeem your collateral and burn VNDC in one transaction.
    * @param tokenCollateral: The address of the token to redeem.
    * @param amountToRedeem: The amount of collateral to redeem.
    * @param amountToBurn: The amount of VNDC to burn.
    */
    function redeemCollateralAndBurnVNDC(address tokenCollateral, uint256 amountToRedeem, uint256 amountToBurn)
        external
    {
        burnVNDC(amountToBurn);
        redeemCollateral(tokenCollateral, amountToRedeem);
    }

    function redeemCollateral(address tokenCollateral, uint256 amountToRedeem)
        public
        moreThanZero(amountToRedeem)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateral, amountToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnVNDC(uint256 amountToBurn) public moreThanZero(amountToBurn) {
        _burnVNDC(msg.sender, msg.sender, amountToBurn);
    }

    /*
    * @param tokenCollateralToRedeem: The ERC20 token address of the collateral you're using to make the protocol solvent again.
    * This is collateral that you're going to take from the user who is insolvent.
    * In return, you have to burn your VNDC to pay off their debt, but you don't pay off your own.
    * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
    * @param debtToCover: The amount of VNDC you want to burn to cover the user's debt.
    *
    * @notice: You can partially liquidate a user.
    * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
    * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */
    function liquidate(address user, address tokenCollateralToRedeem, uint256 debtToCover)
        external
        nonReentrant
        moreThanZero(debtToCover)
        isAllowedToken(tokenCollateralToRedeem)
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor > MIN_HEALTH_FACTOR) {
            revert VNDCEngine__UserNotInTheLiquidatedState();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralToRedeem, debtToCover);
        uint256 amountBonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + amountBonusCollateral;
        _burnVNDC(user, msg.sender, debtToCover);
        _redeemCollateral(user, msg.sender, tokenCollateralToRedeem, totalCollateralToRedeem);
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert VNDCEngine__HealthFactorNotBetter();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                           PRIVATE AND INTERNAL FUNCTIONS                             //
    //////////////////////////////////////////////////////////////////////////////////////////

    function _redeemCollateral(address from, address to, address tokenCollateral, uint256 amountToRedeem)
        private
        moreThanZero(amountToRedeem)
    {
        s_collateralDeposited[from][tokenCollateral] -= amountToRedeem;
        emit CollateralRedeemed(from, to, tokenCollateral, amountToRedeem);
        bool success = IERC20(tokenCollateral).transfer(to, amountToRedeem);
        if (!success) {
            revert VNDCEngine__TransferFailed();
        }
    }

    function _burnVNDC(address onBeHalfOf, address vndcFrom, uint256 amountToBurn) private moreThanZero(amountToBurn) {
        s_VNDCMinted[onBeHalfOf] -= amountToBurn;
        bool success = i_vndc.transferFrom(vndcFrom, address(this), amountToBurn);
        if (!success) {
            revert VNDCEngine__TransferFailed();
        }
        i_vndc.burn(amountToBurn);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                         HEALTH FACTOR CALCULATING FUNCTIONS                          //
    //////////////////////////////////////////////////////////////////////////////////////////

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert VNDCEngine__HealthFactorIsBroken();
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMinted, uint256 totalCollateralAmountInUsd) = _getAccountInformation(user);
        return _calculatingHealthFactor(totalMinted, totalCollateralAmountInUsd);
    }

    function _calculatingHealthFactor(uint256 totalMinted, uint256 totalCollateralAmountInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold =
            (totalCollateralAmountInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold / totalMinted) * PRECISION;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalMinted, uint256 totalCollateralAmountInUsd)
    {
        totalMinted = s_VNDCMinted[user];
        totalCollateralAmountInUsd = getCollateralAmountInUsd(user);
        return (totalMinted, totalCollateralAmountInUsd);
    }

    function getCollateralAmountInUsd(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_tokenCollaterals.length; i++) {
            uint256 amount = s_collateralDeposited[user][s_tokenCollaterals[i]];
            uint256 amountValueInUsd = getValueInUsd(s_tokenCollaterals[i], amount);
            totalCollateralValueInUsd += amountValueInUsd;
        }
        return totalCollateralValueInUsd;
    }

    function getValueInUsd(address tokenAddress, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenPriceFeed[tokenAddress]);
        (, int256 answer,,,) = priceFeed.staleCheckLastestRoundData();
        uint256 amountInUsd = (amount * (uint256(answer) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
        return amountInUsd;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //                                   GETTER FUNCTIONS                                   //
    //////////////////////////////////////////////////////////////////////////////////////////

    function getTokenAmountFromUsd(address tokenAddress, uint256 amountInUsd) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenPriceFeed[tokenAddress]);
        (, int256 answer,,,) = priceFeed.staleCheckLastestRoundData();
        uint256 tokenAmount = ((amountInUsd * PRECISION) / (uint256(answer) * ADDITIONAL_FEED_PRECISION));
        return tokenAmount;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalMinted, uint256 totalCollateralAmountInUsd)
    {
        totalMinted = s_VNDCMinted[user];
        totalCollateralAmountInUsd = getCollateralAmountInUsd(user);
        return (totalMinted, totalCollateralAmountInUsd);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getDebtOfUser(address user) external view returns (uint256) {
        return s_VNDCMinted[user];
    }

    function getUserCollateralAmount(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_tokenCollaterals;
    }

    function getCollateralTokenPriceFeed(address token) external returns (address) {
        return s_tokenPriceFeed[token];
    }

    function getLiquidationBonus() external view returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getPrecision() external view returns (uint256) {
        return PRECISION;
    }
}
//chau nguyen de thuong
