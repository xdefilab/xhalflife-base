const XHalfLife = artifacts.require("XHalfLife");
const MockToken = artifacts.require("MockToken");

module.exports = async function (deployer) {
    await deployer.deploy(MockToken, "MOCK", "MOCK");

    return deployer.deploy(XHalfLife);
};