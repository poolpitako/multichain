// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
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

contract EthEthVaultProxy {
    using SafeERC20 for IERC20;
    using Address for address;

    IVault public constant vault =
        IVault(address(0x9cBdd0f1d9FB5D1ea6f3d022D0896E57aF5f087f));
    address public constant anyEth =
	address(0x6F817a0cE8F7640Add3bC0c1C2298635043c2423);
    address public constant eth =
        address(0x2170ed0880ac9a755fd29b2688956bd959f933f8);
    address public constant anyEthWithdrawl =
        address(0x533e3c0e6b48010873B947bddC4721b1bDFF9648);
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
	if (balanceOfAnyEth() > 0) {
	    // Swap on nerve
	}

        if (balanceOfEth() > 0) {
            vault.deposit();
        }
    }

    function sendBack() external onlyGuardians {
        vault.withdraw();

	// Swap to eth to anyEth
	// Swapout
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
