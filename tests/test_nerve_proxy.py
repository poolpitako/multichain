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
    assert vault.balanceOf(proxy) > 0

    # Sleep for a couple of hours
    chain.sleep(60 * 60 * 10)
    chain.mine(1)

    previousTotalValue = proxy.estimatedTotalAssets()
    proxy.sendBack(Wei("1 ether"), {"from": owner})
    assert previousTotalValue > proxy.estimatedTotalAssets()

    proxy.sendBackAll({"from": owner})
    assert vault.balanceOf(proxy) == 0
    assert proxy.estimatedTotalAssets() == 0


@pytest.mark.require_network("bsc-main-fork")
def test_nerve_proxy_migration(EthereumWethStrategyProxy, owner, strategist):

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
    proxy_vault_balance = vault.balanceOf(proxy)
    assert proxy_vault_balance > 0

    any_eth.transfer(proxy, Wei("3 ether"), {"from": any_eth_whale})
    bsc_eth.transfer(proxy, Wei("3 ether"), {"from": bsc_eth_whale})
    newProxy = EthereumWethStrategyProxy.deploy(strategist, {"from": owner})
    proxy.migrate(newProxy, {"from": owner})
    assert any_eth.balanceOf(newProxy) == Wei("3 ether")
    assert bsc_eth.balanceOf(newProxy) == Wei("3 ether")
    assert vault.balanceOf(newProxy) == proxy_vault_balance
    assert newProxy.estimatedTotalAssets() > 0
    assert proxy.estimatedTotalAssets() == 0


@pytest.mark.require_network("bsc-main-fork")
def test_nerve_proxy_sweep(EthereumWethStrategyProxy, owner, strategist):

    proxy = EthereumWethStrategyProxy.deploy(strategist, {"from": owner})
    bsc_eth_whale = accounts.at(
        "0xf508fcd89b8bd15579dc79a6827cb4686a3592c8", force=True
    )
    any_eth_whale = accounts.at(
        "0x146cd24dcc9f4eb224dfd010c5bf2b0d25afa9c0", force=True
    )
    fusdt_whale = accounts.at("0x0480b924a6f1018863e318af33c15f01619b7f2f", force=True)

    any_eth = Contract("0x6F817a0cE8F7640Add3bC0c1C2298635043c2423")
    bsc_eth = Contract("0x2170Ed0880ac9A755fd29B2688956BD959F933F8")
    fusdt = Contract("0x049d68029688eabf473097a2fc38ef61633a3c7a")
    vault = Contract(proxy.vault())

    assert vault.balanceOf(proxy) == 0

    any_eth.transfer(proxy, Wei("2 ether"), {"from": any_eth_whale})
    proxy.deposit({"from": strategist})
    proxy_vault_balance = vault.balanceOf(proxy)
    assert proxy_vault_balance > 0

    any_eth.transfer(proxy, Wei("0.1 ether"), {"from": any_eth_whale})
    bsc_eth.transfer(proxy, Wei("3 ether"), {"from": bsc_eth_whale})
    fusdt.transfer(proxy, 17728, {"from": fusdt_whale})
    assert fusdt.balanceOf(proxy) > 0

    proxy.sweep(fusdt, {"from": owner})
    assert any_eth.balanceOf(proxy) == Wei("0.1 ether")
    assert bsc_eth.balanceOf(proxy) == Wei("3 ether")
    assert vault.balanceOf(proxy) == proxy_vault_balance
    assert fusdt.balanceOf(proxy) == 0
    assert fusdt.balanceOf(owner) == 17728
