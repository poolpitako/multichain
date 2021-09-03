// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IVault {
    function deposit() external;

    function withdraw() external;
    function token() external view returns(address);
    function decimals() external view returns(uint256);
    function balanceOf(address) external view returns(uint256);
    function pricePerShare() external view returns(uint256);
    function withdraw(uint256 amount) external;
    function withdraw(
        uint256 amount,
        address account,
        uint256 maxLoss
    ) external returns (uint256);
}

interface IAny {
    function Swapout(uint256 amount, address bindaddr) external;
}

contract GenericVaultProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IVault public vault;
    address public want;

    address public strategist;
    address public keeper;
    address public governance;
    address public pendingGovernance;
    uint256 public maxLoss;

    constructor(address _keeper, address _gov, address _vault) public {
        vault = IVault(_vault);
        want = vault.token();
        keeper = _keeper;
        governance = _gov;
        strategist = msg.sender;
        maxLoss = 1;
        IERC20(want).safeApprove(address(vault), type(uint256).max);
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

    // Move yvDAI funds to a new yVault
  function migrateToNewDaiYVault(IVault newYVault) external onlyGov {
      uint256 balanceOfYVault = vault.balanceOf(address(this));
      if (balanceOfYVault > 0) {
          vault.withdraw(balanceOfYVault, address(this), maxLoss);
      }
      IERC20(want).safeApprove(address(vault), 0);

      vault = newYVault;
      IERC20(want).safeApprove(address(vault), type(uint256).max);
      vault.deposit();
  }

    function name() external view returns (string memory) {
        return "BridgeVaultProxy";
    }

    function _wantBalance() internal view returns (uint256){
        return IERC20(want).balanceOf(address(this));
    }
    function _vaultBalance() internal view returns (uint256){
        return vault.balanceOf(address(this)).mul(vault.pricePerShare()).div(10 ** vault.decimals());
    }

    function acceptGovernor() external {
        require(msg.sender == pendingGovernance);
        governance = pendingGovernance;
        pendingGovernance = address(0);
    }

    function setPendingGovernance(address _pendingGovernance) external onlyGov {
        pendingGovernance = _pendingGovernance;
    }
    function setMaxLoss(uint256 _maxLoss) external onlyGuardians {
        maxLoss = _maxLoss;
    }

    function totalAssets() public view returns (uint256) {
        return _vaultBalance().add(_wantBalance());
    }

    function deposit() external onlyGuardians {
        if (_wantBalance() > 0) {
            vault.deposit();
        }
    }

    function sendAllBack() external onlyGuardians {
        uint256 balanceOfYVault = vault.balanceOf(address(this));
        if (balanceOfYVault > 0) {
            vault.withdraw(balanceOfYVault, address(this), maxLoss);
        }
        IAny(want).Swapout(_wantBalance(), address(this));
    }

    function sendWantBack(uint256 amount) external onlyGuardians {
        uint256 wantBal = _wantBalance();
        if(wantBal < amount){
            uint256 toWithdraw = amount.sub(wantBal);
            vault.withdraw(toWithdraw.mul(10 ** vault.decimals()).div(vault.pricePerShare()), address(this), maxLoss);
        }

        IAny(want).Swapout(Math.min(_wantBalance(), amount), address(this));
    }

    //sweep function in case bridge breaks and we are trapped
    function sweep(address token, uint256 amount) external onlyGov {
        IERC20(token).safeTransfer(governance, amount);
    }

}