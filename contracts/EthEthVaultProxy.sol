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

contract EthEthVaultProxy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    IVault public constant vault =
        IVault(address(0x9cBdd0f1d9FB5D1ea6f3d022D0896E57aF5f087f));
    address public constant anyEth =
        address(0x6F817a0cE8F7640Add3bC0c1C2298635043c2423);
    address public constant eth =
        address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    IAnyEth public constant anyEthWithdrawl =
        IAnyEth(anyEth);
    INrvSwap public constant nrvAnyEthSwap =
	    INrvSwap(address(0x146CD24dCc9f4EB224DFd010c5Bf2b0D25aFA9C0));
    address public strategist;
    address public keeper;
    address public governance;
    address public pendingGovernance;

    constructor(address _strategist, address _keeper) public {
        governance = msg.sender;
        strategist = _strategist;
        keeper = _keeper;
        IERC20(eth).safeApprove(address(vault), type(uint256).max);
    }

    modifier onlyGov {
        require(msg.sender == governance);
        _;
    }

    modifier onlyGuardians {
        require(
            msg.sender == strategist ||
                msg.sender == keeper ||
                msg.sender == governance
        );
        _;
    }

    function name() external view returns (string memory) {
        return "EthEthVaultProxy";
    }

    function deposit() external onlyGuardians {
	uint256 anyEthBalance = balanceOfAnyEth();
        if (anyEthBalance > 0) {
            uint256 minAccepted = anyEthBalance.sub(anyEthBalance.mul(1000).div(100_000));
            nrvAnyEthSwap.swap(
        		nrvAnyEthSwap.getTokenIndex(anyEth),
		        nrvAnyEthSwap.getTokenIndex(eth),
		        anyEthBalance, 
                minAccepted, 
		        now
	        );
        }

        if (balanceOfEth() > 0) {
            vault.deposit();
        }
    }

    function sendBack() external onlyGuardians {
        vault.withdraw();

        uint256 ethBalance = balanceOfEth();
        if (ethBalance > 0) {
            uint256 minAccepted = ethBalance.sub(ethBalance.mul(1000).div(100_000));
            nrvAnyEthSwap.swap(
        		nrvAnyEthSwap.getTokenIndex(eth),
		        nrvAnyEthSwap.getTokenIndex(anyEth),
		        ethBalance, 
                minAccepted, 
		        now
	        );
        }
        
        uint256 anyEthBalance = balanceOfAnyEth();
        if (anyEthBalance > 0) {
            anyEthWithdrawl.Swapout(anyEthBalance, address(this));
        }
    }

    function setStrategist(address _strategist) external onlyGov {
        strategist = _strategist;
    }

    function setKeeper(address _keeper) external onlyGov {
        keeper = _keeper;
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
        return IERC20(eth).balanceOf(address(this));
    }
}
