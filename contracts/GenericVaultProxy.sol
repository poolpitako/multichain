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
    uint256 public dustThreshold;

    constructor(address _keeper, address _gov, address _vault, uint256 _dustThreshold) public {
        vault = IVault(_vault);
        want = vault.token();
        keeper = _keeper;
        governance = _gov;
        strategist = msg.sender;
        dustThreshold = _dustThreshold;
        maxLoss = 1;
        IERC20(want).safeApprove(address(vault), type(uint256).max);
    }

    modifier onlyGov {
        require(msg.sender == governance);
        _;
    }

    modifier onlyManagers {
        require(msg.sender == strategist ||
                msg.sender == governance);
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

    function name() external pure returns (string memory) {
        return "BridgeVaultProxyV2";
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
    function setKeeper(address _keeper) external onlyManagers {
        keeper = _keeper;
    }
    function setStrategist(address _strategist) external onlyManagers {
        strategist = _strategist;
    }
    function setMaxLoss(uint256 _maxLoss) external onlyManagers {
        maxLoss = _maxLoss;
    }

    function totalAssets() public view returns (uint256) {
        return _vaultBalance().add(_wantBalance());
    }

    //to mimic harvest on normal strats
    function harvest() external onlyGuardians {
        if (_wantBalance() > 0) {
            vault.deposit();
        }
    }

    function harvestTrigger(uint256 callCost) public view returns (bool) {
        return _wantBalance() > dustThreshold;
    }

    function sendAllBack() external onlyManagers {
        uint256 balanceOfYVault = vault.balanceOf(address(this));
        if (balanceOfYVault > 0) {
            vault.withdraw(balanceOfYVault, address(this), maxLoss);
        }
        IAny(want).Swapout(_wantBalance(), address(this));
    }

    function sendWantBack(uint256 amount) external onlyManagers {
        uint256 wantBal = _wantBalance();
        if(wantBal < amount){
            uint256 toWithdraw = amount.sub(wantBal);
            vault.withdraw(toWithdraw.mul(10 ** vault.decimals()).div(vault.pricePerShare()), address(this), maxLoss);
        }

        IAny(want).Swapout(Math.min(_wantBalance(), amount), address(this));
    }

    //sweep function in case bridge breaks and we are trapped
    function sweep(address token, uint256 amount) external onlyGov {
        assert(token != want && token != address(vault));
        IERC20(token).safeTransfer(governance, amount);
    }

    function migrate(address newStrategy) external onlyGov {
        uint256 balanceWant = _wantBalance();

        if(balanceWant > 0){
            IERC20(want).safeTransfer(newStrategy, balanceWant);
        }
        uint256 ytokens = vault.balanceOf(address(this));
        if(ytokens >0){
            IERC20(address(vault)).safeTransfer(newStrategy, ytokens);
        }
        
    }

}