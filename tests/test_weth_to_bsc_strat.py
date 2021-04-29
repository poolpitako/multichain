import pytest
import brownie
from brownie import Contract, Wei, accounts, chain


@pytest.mark.require_network("mainnet-fork")
def test_weth_to_bsc_strat(WethToBscStrategy):

    vault = Contract("0xa2619fDFB99ABeb533a1147461f3f1109c5ADe75")
    gov = vault.governance()
    vault.setDepositLimit(Wei("10 ether"), {"from": gov})
    strat = WethToBscStrategy.deploy(vault, {"from": gov})

    vault.migrateStrategy(Contract("0x0a207aA750827FeaFF4f7668cB157eDCb5215526"), strat, {"from": gov})

    weth_whale = accounts.at("0x2f0b23f53734252bda2277357e97e1517d6b042a", force=True)
    weth = Contract(vault.token())

    weth.approve(vault, 2 ** 256 - 1, {"from": weth_whale})
    vault.deposit(Wei("5 ether"), {"from": weth_whale})

    deposit_address = accounts.at(
        "0x13B432914A996b0A48695dF9B2d701edA45FF264", force=True
    )
    prev_balance = deposit_address.balance()
    harvestTx = strat.harvest({"from": gov})
    assert deposit_address.balance() > prev_balance

    successfulTransfer = None
    for transfer in harvestTx.events["Transfer"]:
        if ('from' in transfer and 'to' in transfer and 'value' in transfer
            and transfer['from'] == strat.address
            and transfer['to'] == deposit_address):
            successfulTransfer = transfer
            break

    assert successfulTransfer is not None

    deposit_address.transfer(to=strat, amount=Wei("6 ether"))
    harvestTx = strat.harvest({"from": gov})

    successfulTransfer = None
    for transfer in harvestTx.events["Transfer"]:
        if ('from' in transfer and 'to' in transfer and 'value' in transfer
            and transfer['from'] == strat.address
            and transfer['to'] == deposit_address):
            successfulTransfer = transfer
            break

    assert successfulTransfer is not None

    # Sleep for a couple of hours
    chain.sleep(60 * 60 * 10)
    chain.mine(1)

    assert vault.strategies(strat).dict()["totalLoss"] == Wei("1.02 ether")
    assert vault.strategies(strat).dict()["totalGain"] > 0
