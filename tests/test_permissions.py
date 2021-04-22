import pytest
import brownie
from brownie import Contract, Wei


def test_permissions(proxy, owner, strategist, keeper, rando, whale):

    # Rando can't do anything
    with brownie.reverts():
        proxy.deposit({"from": rando})

    with brownie.reverts():
        proxy.sendBack({"from": rando})

    usdt = Contract(proxy.usdt())
    for operator in [owner, strategist, keeper]:
        usdt.transfer(proxy, 100 * 1e6, {"from": whale})
        proxy.deposit({"from": operator})
        proxy.sendBack({"from": operator})
