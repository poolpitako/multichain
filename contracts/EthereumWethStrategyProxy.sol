// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IVault {
    function deposit() external;

    function withdraw() external;
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

    function sendBack() external onlyGovOrStrategist {
        vault.withdraw();

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
            IAnyEth(anyEth).Swapout(anyEthBalance, address(this));
        }
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
}
