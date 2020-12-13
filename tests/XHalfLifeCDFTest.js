const { time } = require('@openzeppelin/test-helpers');
const truffleAssert = require("truffle-assertions");
const XDEX = artifacts.require('XDEX');
const XHalfLifeCDF = artifacts.require('XHalfLifeCDF');

contract('XHalfLifeCDF', ([alice, bob, minter]) => {
    beforeEach(async () => {
        this.xdex = await XDEX.new({ from: minter });
        this.halflifecdf = await XHalfLifeCDF.new(this.xdex.address, { from: alice });

        await this.xdex.addMinter(minter, { from: minter });
    });

    context('should create and return balance successfully', async () => {
        beforeEach(async () => {
            await this.xdex.mint(alice, '2000', { from: minter });
        });

        it('should return balance of the stream', async () => {
            await this.xdex.approve(this.halflifecdf.address, '1000', { from: alice });
            await this.halflifecdf.createStream(bob, '60', '140', '160', { from: alice });
            console.log("give bob a stream: startBlock #140, stopBlock #160, depositAmount 60");

            await time.advanceBlockTo('140');
            //return sender balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', alice)).toString(), '60');
            //return recipient balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', bob)).toString(), '0');
            console.log("at #140, bob's withdrawable reward is 0");

            await time.advanceBlockTo('145');
            //return sender balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', alice)).toString(), '57');
            //return recipient balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', bob)).toString(), '3');
            console.log("at #145, bob's withdrawable reward is 3");

            await time.advanceBlockTo('150');
            //return sender balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', alice)).toString(), '30');
            //return recipient balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', bob)).toString(), '30');
            console.log("at #150, bob's withdrawable reward is 30");

            await time.advanceBlockTo('155');
            //return sender balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', alice)).toString(), '4');
            //return recipient balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', bob)).toString(), '56');
            console.log("at #155, bob's withdrawable reward is 56");

            await time.advanceBlockTo('160');
            //return sender balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', alice)).toString(), '0');
            //return recipient balance of the stream
            assert.equal((await this.halflifecdf.balanceOf('1', bob)).toString(), '60');
            console.log("at #160, bob's withdrawable reward is 60");
        });
    });
});
