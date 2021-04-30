import pytest
import brownie
from brownie import Contract, Wei, accounts, chain


@pytest.mark.require_network("bsc-main-fork")
def test_nerve_proxy(EthereumWethStrategyProxy, owner, strategist):

    proxy = EthereumWethStrategyProxy.deploy(strategist, {"from": owner})
    bsc_eth_whale = accounts.at(
        "0xf508fcd89b8bd15579dc79a6827cb4686a3592c8", force=True
    )
    any_eth_whale = accounts.at(
        "0x146cd24dcc9f4eb224dfd010c5bf2b0d25afa9c0", force=True
    )

    any_eth = Contract("0x6F817a0cE8F7640Add3bC0c1C2298635043c2423")
    bsc_eth = Contract("0x2170Ed0880ac9A755fd29B2688956BD959F933F8")
    vault = Contract(proxy.vault())

    assert vault.balanceOf(proxy) == 0

    any_eth.transfer(proxy, Wei("2 ether"), {"from": any_eth_whale})
    proxy.deposit({"from": strategist})
    assert vault.balanceOf(proxy) >= 0

    # Sleep for a couple of hours
    chain.sleep(60 * 60 * 10)
    chain.mine(1)

    previousTotalValue = proxy.estimatedTotalAssets()
    proxy.sendBack(Wei("1 ether"), {"from": owner})
    assert previousTotalValue > proxy.estimatedTotalAssets()

    proxy.sendBackAll({"from": owner})
    assert vault.balanceOf(proxy) == 0
    assert proxy.estimatedTotalAssets() == 0
