import pytest
import brownie
from brownie import Contract, Wei, accounts, chain


@pytest.mark.require_network("mainnet-fork")
def test_weth_to_bsc_strat(WethToBscStrategy):

    vault = Contract("0xa2619fDFB99ABeb533a1147461f3f1109c5ADe75")
    gov = vault.governance()
    vault.setDepositLimit(Wei("10 ether"), {"from": gov})
    strat = WethToBscStrategy.deploy(vault, {"from": gov})

    weth_whale = accounts.at("0x2f0b23f53734252bda2277357e97e1517d6b042a", force=True)
    weth = Contract(vault.token())
    weth.approve(vault, 2 ** 256 - 1, {"from": weth_whale})

    oldStrat = Contract("0x38B1AAD678D9F47aE9bCB79bd9e4a5975fE3A2bd")
    vault.revokeStrategy(oldStrat, {"from": gov})
    oldStrat.harvest({"from": gov})
    
    vault.addStrategy(strat, 10_000, 0, Wei("2 ether"), 1_000, {"from": gov})
    #vault.updateStrategyDebtRatio(strat, 10_000, {"from": gov})

    vault.deposit(Wei("5 ether"), {"from": weth_whale})

    anyswap_deposit_address = accounts.at(
        "0x13B432914A996b0A48695dF9B2d701edA45FF264", force=True
    )
    anyswap_prev_balance = anyswap_deposit_address.balance()
    vault_balance_before_harvest = weth.balanceOf(vault)
    harvestTx = strat.harvest({"from": gov})
    assert anyswap_deposit_address.balance() > anyswap_prev_balance

    transfer_value = 0
    for transfer in harvestTx.events["Transfer"]:
        if (
            "from" in transfer
            and "to" in transfer
            and "value" in transfer
            and transfer["from"] == strat.address
            and transfer["to"] == anyswap_deposit_address
        ):
            transfer_value = transfer["value"]
            break

    assert transfer_value == Wei("2 ether")

    vault.deposit(Wei("2 ether"), {"from": weth_whale})
    vault_balance_before_harvest_1 = weth.balanceOf(vault)
    harvestTx1 = strat.harvest({"from": gov})
    assert vault.strategies(strat).dict()["totalGain"] == 0

    transfer_value = 0
    for transfer in harvestTx1.events["Transfer"]:
        if (
            "from" in transfer
            and "to" in transfer
            and "value" in transfer
            and transfer["from"] == strat.address
            and transfer["to"] == anyswap_deposit_address
        ):
            transfer_value = transfer["value"]
            break

    assert transfer_value == Wei("2 ether")

    # this simulates 1 eth being returned from the proxy
    weth.transfer(strat, Wei("1 ether"), {"from": weth_whale})

    vault.updateStrategyDebtRatio(strat, 0, {"from": gov})
    strat.harvest({"from": gov})

    weth.transfer(strat, Wei("3 ether"), {"from": weth_whale})   
    strat.harvest({"from": gov})

    weth.transfer(strat, Wei("1 ether"), {"from": weth_whale})   
    strat.harvest({"from": gov})

    assert vault.strategies(strat).dict()["totalLoss"] == 0
    assert vault.strategies(strat).dict()["totalGain"] > 0
