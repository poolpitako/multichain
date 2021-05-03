// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

interface IVault is IERC20 {
    function deposit() external;

    function withdraw() external;

    function withdraw(uint256 maxShares) external;

    function pricePerShare() external view returns (uint256);

    function decimals() external view returns (uint256);
}

interface IAnyEth {
    function Swapout(uint256 amount, address bindaddr) external;
}

interface INrvSwap {
    function swap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external returns (uint256);

    function getTokenIndex(address tokenAddress) external view returns (uint8);
}

contract EthereumWethStrategyProxy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    IVault public constant vault =
        IVault(address(0x9cBdd0f1d9FB5D1ea6f3d022D0896E57aF5f087f));
    address public constant anyEth =
        address(0x6F817a0cE8F7640Add3bC0c1C2298635043c2423);
    address public constant binancePegEth =
        address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    INrvSwap public constant nrvAnyEthSwap =
        INrvSwap(address(0x146CD24dCc9f4EB224DFd010c5Bf2b0D25aFA9C0));

    // Default slippage is 0.1%
    uint256 public slippage = 1_000;
    uint256 public constant MAX_SLIPPAGE = 100_000;

    address public strategist;
    address public governance;
    address public pendingGovernance;

    constructor(address _strategist) public {
        governance = msg.sender;
        strategist = _strategist;
        IERC20(binancePegEth).safeApprove(address(vault), type(uint256).max);
        IERC20(binancePegEth).safeApprove(
            address(nrvAnyEthSwap),
            type(uint256).max
        );
        IERC20(anyEth).safeApprove(address(nrvAnyEthSwap), type(uint256).max);
    }

    modifier onlyGov {
        require(msg.sender == governance);
        _;
    }

    modifier onlyGovOrStrategist {
        require(msg.sender == strategist || msg.sender == governance);
        _;
    }

    function name() external view returns (string memory) {
        return "EthereumWethStrategyProxy";
    }

    function deposit() external onlyGovOrStrategist {
        uint256 anyEthBalance = balanceOfAnyEth();
        if (anyEthBalance > 0) {
            uint256 minAccepted =
                anyEthBalance.sub(
                    anyEthBalance.mul(slippage).div(MAX_SLIPPAGE)
                );
            nrvAnyEthSwap.swap(
                nrvAnyEthSwap.getTokenIndex(anyEth),
                nrvAnyEthSwap.getTokenIndex(binancePegEth),
                anyEthBalance,
                minAccepted,
                now
            );
        }

        if (balanceOfEth() > 0) {
            vault.deposit();
        }
    }

    function sendBack(uint256 _sendBackAmount) external onlyGovOrStrategist {
        require(_sendBackAmount <= estimatedTotalAssets());

        _sendBack(_sendBackAmount);
    }

    function sendBackAll() external onlyGovOrStrategist {
        _sendBack(type(uint256).max);
    }

    function setSlippage(uint256 _slippage) external onlyGovOrStrategist {
        slippage = _slippage;
    }

    function setStrategist(address _strategist) external onlyGov {
        strategist = _strategist;
    }

    function acceptGovernor() external {
        require(msg.sender == pendingGovernance);
        governance = pendingGovernance;
        pendingGovernance = address(0);
    }

    function setPendingGovernance(address _pendingGovernance) external onlyGov {
        pendingGovernance = _pendingGovernance;
    }

    function balanceOfAnyEth() public view returns (uint256) {
        return IERC20(anyEth).balanceOf(address(this));
    }

    function balanceOfEth() public view returns (uint256) {
        return IERC20(binancePegEth).balanceOf(address(this));
    }

    function balanceOfVaultSharesInEth() public view returns (uint256) {
        return _vaultSharesToInvestment(vault.balanceOf(address(this)));
    }

    function estimatedTotalAssets() public view returns (uint256) {
        return
            balanceOfEth().add(balanceOfAnyEth()).add(
                balanceOfVaultSharesInEth()
            );
    }

    function migrate(address _newStrategy) external onlyGov {
        IERC20(anyEth).safeTransfer(
            _newStrategy,
            IERC20(anyEth).balanceOf(address(this))
        );
        IERC20(binancePegEth).safeTransfer(
            _newStrategy,
            IERC20(binancePegEth).balanceOf(address(this))
        );
        IERC20(vault).safeTransfer(
            _newStrategy,
            vault.balanceOf(address(this))
        );
    }

    function sweep(address _token) external onlyGov {
        require(_token != address(anyEth), "!anyEth");
        require(_token != address(binancePegEth), "!binancePegEth");
        require(_token != address(vault), "!vault");

        IERC20(_token).safeTransfer(
            governance,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function _sendBack(uint256 _amount) internal {
        uint256 ethNeededFromVault =
            _amount.sub(balanceOfEth()).sub(balanceOfAnyEth());

        if (ethNeededFromVault < balanceOfVaultSharesInEth()) {
            vault.withdraw(_investmentToVaultShares(ethNeededFromVault));
        } else {
            vault.withdraw();
        }

        uint256 binancePegEthBalance = balanceOfEth();
        if (binancePegEthBalance > 0) {
            uint256 minAccepted =
                binancePegEthBalance.sub(
                    binancePegEthBalance.mul(slippage).div(MAX_SLIPPAGE)
                );

            nrvAnyEthSwap.swap(
                nrvAnyEthSwap.getTokenIndex(binancePegEth),
                nrvAnyEthSwap.getTokenIndex(anyEth),
                binancePegEthBalance,
                minAccepted,
                now
            );
        }

        uint256 anyEthBalance = balanceOfAnyEth();
        if (anyEthBalance > 0) {
            IAnyEth(anyEth).Swapout(
                Math.min(_amount, balanceOfAnyEth()),
                address(this)
            );
        }
    }

    function _investmentToVaultShares(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(10**vault.decimals()).div(vault.pricePerShare());
    }

    function _vaultSharesToInvestment(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(vault.pricePerShare()).div(10**vault.decimals());
    }
}
