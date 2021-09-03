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


contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public bridge;
    uint256 public pendingProfit;
    uint256 public minSend;
    uint256 public maxSend;

    bool public fourthreeprotection;

    constructor(address _vault, address _bridge, uint256 _minSend, uint256 _maxSend) public BaseStrategy(_vault) {

        bridge = _bridge;
        minSend = _minSend;
        maxSend = _maxSend;
    }

    function name() external view override returns (string memory) {
        return "BridgeStrategy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return totalDebt().add(pendingProfit);
    }

    function totalDebt() public view returns (uint256) {
        return vault.strategies(address(this)).totalDebt;
    }

    function _wantBalance() internal view returns (uint256){
        return IERC20(want).balanceOf(address(this));
    }

    function setBridge(address _bridge) external onlyGovernance {
        bridge = _bridge;
    }

    function setMinSend(uint256 _minSend) external onlyEmergencyAuthorized {
        minSend = _minSend;
    }

    function setMaxSend(uint256 _maxSend) external onlyEmergencyAuthorized {
        maxSend = _maxSend;
    }

    function incrementPendingProfit(uint256 _newProfit) external onlyEmergencyAuthorized {
        pendingProfit = pendingProfit.add(_newProfit);
    }

    //for use if a mistake is made
    function clearPendingProfit() external onlyEmergencyAuthorized {
        pendingProfit = 0;
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
        uint256 wantBal = _wantBalance();

        if(wantBal == 0){
            return (0,0,0);
        }

        _debtPayment = Math.min(wantBal, _debtOutstanding);

        wantBal = wantBal.sub(_debtPayment);

        if(pendingProfit > 0 && wantBal > 0){
            _profit = Math.min(pendingProfit, wantBal);
            pendingProfit = pendingProfit.sub(_profit);
        }
        
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        uint256 balance = _wantBalance();
        if (_debtOutstanding >= balance) {
            return;
        }
        balance = balance.sub(_debtOutstanding);

        if(balance > minSend){
            want.safeTransfer(bridge, Math.min(balance, maxSend));
        }


    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        
        liquidatePosition(type(uint256).max);
        _amountFreed = _wantBalance();
        require(_amountFreed >= totalDebt(), "Money in bridge");
    }

    //we dont use this as harvest trigger is overriden
    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {
        return(_amtInWei);
    }

    //should never really be called as we keep late in queue
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 totalAssets = _wantBalance();
        _liquidatedAmount = Math.min(totalAssets, _amountNeeded);

        //sub 43 protection
        if(fourthreeprotection){
            require(_amountNeeded == _liquidatedAmount, "fourthreeprotection");
        }
    }

    //simplified harvest function
    function harvestTrigger(uint256 gasCost) public override view returns (bool) {
        
        StrategyParams memory params = vault.strategies(address(this));

        // Should not trigger if strategy is not activated
        if (params.activation == 0) return false;

        // Check for profits and losses
        uint256 wantBal = _wantBalance();
        bool harvest;
        if(wantBal > debtThreshold){
            harvest = vault.debtOutstanding() >= debtThreshold;
            harvest = pendingProfit >= debtThreshold;
        }

        return harvest;
    }


    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}
}
