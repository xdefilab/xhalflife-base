const XHalfLife = artifacts.require("XHalfLife");

var XDEX_KOVAN = "0x7042758327753f684568528d5eAb0CD2839c6698";

module.exports = async function (deployer) {
    return deployer.deploy(XHalfLife, XDEX_KOVAN);
};