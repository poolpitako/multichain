import pytest
import brownie
from brownie import Contract, Wei, accounts, chain


@pytest.mark.require_network("mainnet-fork")
def test_weth_to_bsc_trat(WethToBscStrategy):

    vault = Contract("0xa2619fDFB99ABeb533a1147461f3f1109c5ADe75")
    gov = vault.governance()
    vault.setDepositLimit(Wei("10 ether"), {"from": gov})
    strat = WethToBscStrategy.deploy(vault, {"from": gov})

    vault.addStrategy(strat, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})

    weth_whale = accounts.at("0x2f0b23f53734252bda2277357e97e1517d6b042a", force=True)
    weth = Contract(vault.token())

    weth.approve(vault, 2 ** 256 - 1, {"from": weth_whale})
    vault.deposit(Wei("5 ether"), {"from": weth_whale})

    deposit_address = accounts.at(
        "0x13B432914A996b0A48695dF9B2d701edA45FF264", force=True
    )
    prev_balance = deposit_address.balance()
    strat.harvest({"from": gov})
    assert deposit_address.balance() > prev_balance

    deposit_address.transfer(to=strat, amount=Wei("6 ether"))
    strat.harvest({"from": gov})

    # Sleep for a couple of hours
    chain.sleep(60 * 60 * 10)
    chain.mine(1)

    assert vault.strategies(strat).dict()["totalLoss"] == 0
    assert vault.strategies(strat).dict()["totalGain"] > 0
