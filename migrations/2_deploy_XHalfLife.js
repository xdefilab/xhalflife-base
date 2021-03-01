const XHalfLife = artifacts.require("XHalfLife");
const MockToken = artifacts.require("MockToken");

module.exports = async function (deployer) {
    await deployer.deploy(MockToken, "MOCK", "MOCK", 100000000);

    return deployer.deploy(XHalfLife);
};