// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract WethToBscStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public ethDepositToBsc =
        address(0x13B432914A996b0A48695dF9B2d701edA45FF264);

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(address _vault) public BaseStrategy(_vault) {}

    function setEthDepositAddress(address _ethDepositToBsc)
        external
        onlyGovernance
    {
        ethDepositToBsc = _ethDepositToBsc;
    }

    function name() external view override returns (string memory) {
        return "WethToBscStrategy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return want.balanceOf(address(this));
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // If we got eth back from the proxy, let's convert to weth
        if (address(this).balance > 0) {
            IWETH(address(want)).deposit{value: address(this).balance}();
        }

        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 wantBalance = balanceOfWant();

        // Set profit or loss based on the initial debt
        if (debt <= wantBalance) {
            _profit = wantBalance - debt;
        } else {
            _loss = debt - wantBalance;
        }

        // Repay debt. Amount will depend if we had profit or loss
        if (_debtOutstanding > 0) {
            if (_profit >= 0) {
                _debtPayment = Math.min(
                    _debtOutstanding,
                    wantBalance.sub(_profit)
                );
            } else {
                _debtPayment = Math.min(
                    _debtOutstanding,
                    wantBalance.sub(_loss)
                );
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        uint256 balance = balanceOfWant();
        if (_debtOutstanding >= balance) {
            return;
        }

        IWETH(address(want)).withdraw(balanceOfWant());

	uint256 balanceToTransfer = address(this).balance;
        payable(ethDepositToBsc).transfer(balanceToTransfer);
	emit Transfer(address(this), ethDepositToBsc, balanceToTransfer);
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    receive() external payable {}
}
