//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 *  @title: Decentralized Stable Coin - Viet Nam Stable Coin (VNDC)
 *  @author Huy Pham
 *  Collateral: Exogenous (ETH & BTC)
 *  Minting: Algorithmic
 *  Relative Stability: Pegged to USD => 1 VNDC = 1 USD
 *
 *  This contract meat to be governed by VNSCEngine. This contract is just the ERC20 
 implementation of stablecoin.
 */

contract VietNamStableCoin is ERC20Burnable, Ownable {
    /**
     * ERROR
     */
    error VietNamStableCoin__InvalidAddress();
    error VietNamStableCoin__NeedMoreThanZero();
    error VietNamStableCoin__BurnMoreThanZero();
    error VietNamStableCoin__NotEnoughBalance();

    constructor() ERC20("VietNamStableCoin", "VNDC") {}

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert VietNamStableCoin__InvalidAddress();
        }

        if (_amount <= 0) {
            revert VietNamStableCoin__NeedMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert VietNamStableCoin__BurnMoreThanZero();
        }

        if (balanceOf(msg.sender) < _amount) {
            revert VietNamStableCoin__NotEnoughBalance();
        }

        super.burn(_amount);
    }
}
