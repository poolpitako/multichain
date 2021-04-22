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

contract BscFusdtVaultProxy {
    using SafeERC20 for IERC20;
    using Address for address;

    IVault public constant vault =
        IVault(address(0x7Da96a3891Add058AdA2E826306D812C638D87a7));
    address public constant usdt =
        address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address public constant fusdtDeposit =
        address(0x533e3c0e6b48010873B947bddC4721b1bDFF9648);
    address public strategist;
    address public keeper;
    address public governance;
    address public pendingGovernance;

    constructor(address _strategist, address _keeper) public {
        governance = msg.sender;
        strategist = _strategist;
        keeper = _keeper;
        IERC20(usdt).safeApprove(address(vault), type(uint256).max);
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
        return "BscFusdtVaultProxy";
    }

    function deposit() external onlyGuardians {
        if (balanceOfUsdt() > 0) {
            vault.deposit();
        }
    }

    function sendBack() external onlyGuardians {
        vault.withdraw();
        IERC20(usdt).safeTransfer(fusdtDeposit, balanceOfUsdt());
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

    function balanceOfUsdt() public view returns (uint256) {
        return IERC20(usdt).balanceOf(address(this));
    }
}
