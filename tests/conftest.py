import pytest


@pytest.fixture
def owner(accounts):
    yield accounts[0]


@pytest.fixture
def keeper(accounts):
    yield accounts[1]


@pytest.fixture
def strategist(accounts):
    yield accounts[2]


@pytest.fixture
def rando(accounts):
    yield accounts[3]


@pytest.fixture
def whale(accounts):
    yield accounts.at("0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503", force=True)


@pytest.fixture
def proxy(owner, keeper, strategist, BscFusdtVaultProxy):
    yield BscFusdtVaultProxy.deploy(strategist, keeper, {"from": owner})
