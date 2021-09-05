import pytest
import brownie
from brownie import Contract, Wei, accounts, chain

def test_deploy(
    chain,
    whale,
    interface,
    Strategy,
    Contract,
    accounts,
):
    deployer = accounts.at('0xBb4eDcFeC106B378e4b4ec478a985017Bd423523', force=True)
    strategist = accounts.at('0xFeC07aca9d4311FE6F114Dbd25BBb8E6f8894AEA', force=True)

    registry = Contract('0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804')
    dai = interface.ERC20('0x6B175474E89094C44Da98b954EedeAC495271d0F')

    expected_address = '0xAd02E4C635DA744CC1754d14170dC157df6232aF'
    strat_ms = accounts.at('0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7', force=True)
    yearn_dev_ms = '0x846e211e8ba920B353FB717631C015cf04061Cc9'

    tx = registry.newExperimentalVault(dai, strat_ms, yearn_dev_ms, strat_ms, "", "", {'from': strategist})
    vault = Contract(tx.return_value)

    bridge = '0xC564EE9f21Ed8A2d8E7e76c085740d5e4c5FaFbE'
    min_send = 1_000 * 1e18
    max_send = 950_000 * 1e18

    strategy = Strategy.deploy(vault, bridge, min_send, max_send, {'from': deployer})

    assert strategy == expected_address
    print(vault.apiVersion())

    print(strategy.estimatedTotalAssets()/1e18)

    vault.addStrategy(strategy, 10000, 0, 2**256-1, 1000, {'from': strat_ms})
    vault.setDepositLimit(100_000_000 *1e18, {'from': strat_ms})

    dai.approve(vault, 2 ** 256 - 1, {"from": whale})
    before_balance = dai.balanceOf(bridge)

    deposit = 10_000 *1e18

    vault.deposit(deposit, {"from": whale})

    strategy.harvest({'from': deployer})

    print((dai.balanceOf(bridge) - before_balance)/1e18 )


    dai.transfer(strategy, 1000 *1e18, {"from": whale})
    strategy.setPendingProfit(100 *1e18, {'from': strat_ms})
    strategy.harvest({'from': deployer})
    assert dai.balanceOf(vault) == 100 *1e18
    assert dai.balanceOf(strategy) == 900 *1e18

    

