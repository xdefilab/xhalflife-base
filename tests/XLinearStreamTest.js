const { expectRevert, time } = require("@openzeppelin/test-helpers");
const truffleAssert = require("truffle-assertions");
const XDEX = artifacts.require("XDEX");
const XHalfLifeLinear = artifacts.require("XHalfLifeLinear");

contract("XHalfLifeLinear", ([alice, bob, carol, minter]) => {
  beforeEach(async () => {
    this.xdex = await XDEX.new({ from: minter });
    this.halflifelinear = await XHalfLifeLinear.new({ from: alice });
    await this.xdex.addMinter(minter, { from: minter });
  });

  it("should set correct state variables", async () => {
    const xdexCore = await this.xdex.core();
    assert.equal(xdexCore, minter);
  });

  context("should create streams successfully", async () => {
    beforeEach(async () => {
      await this.xdex.mint(alice, "2000", { from: minter });
    });

    it("the sender should have enough tokens", async () => {
      const deposit = 2001;
      const recipient = bob;

      await this.xdex.approve(this.halflifelinear.address, "3000", {
        from: alice,
      });
      await truffleAssert.reverts(
        this.halflifelinear.createStream(
          this.xdex.address,
          recipient,
          deposit,
          "30",
          "80",
          {
            from: alice,
          }
        ),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("the recipient should not be the caller itself", async () => {
      await truffleAssert.reverts(
        this.halflifelinear.createStream(
          this.xdex.address,
          alice,
          1000,
          "30",
          "80",
          {
            from: alice,
          }
        ),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("the recipient should not be the 0 address", async () => {
      const recipient = "0x0000000000000000000000000000000000000000";
      await truffleAssert.reverts(
        this.halflifelinear.createStream(
          this.xdex.address,
          recipient,
          1000,
          "30",
          "80",
          {
            from: alice,
          }
        ),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("the recipient should not be the liner contract itself", async () => {
      await truffleAssert.reverts(
        this.halflifelinear.createStream(
          this.xdex.address,
          this.halflifelinear.address,
          1000,
          "30",
          "80",
          { from: alice }
        ),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("the liner contract should have enough allowance", async () => {
      const deposit = 1001;
      const recipient = carol;

      await this.xdex.approve(this.halflifelinear.address, "1000", {
        from: alice,
      });
      await truffleAssert.reverts(
        this.halflifelinear.createStream(
          this.xdex.address,
          recipient,
          deposit,
          "30",
          "80",
          {
            from: alice,
          }
        ),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("the start block should not after the stop block", async () => {
      await truffleAssert.reverts(
        this.halflifelinear.createStream(
          this.xdex.address,
          bob,
          1000,
          "80",
          "30",
          {
            from: alice,
          }
        ),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("should create stream successfully", async () => {
      await this.xdex.approve(this.halflifelinear.address, "1000", {
        from: alice,
      });

      let deposit = 100;
      let startBlock = 50;
      let stopBlock = 100;
      let result = await this.halflifelinear.createStream(
        this.xdex.address,
        bob,
        deposit,
        startBlock,
        stopBlock,
        { from: alice }
      );
      let stream = await this.halflifelinear.getStream(
        Number(result.logs[0].args.streamId)
      );

      //emits a stream event
      truffleAssert.eventEmitted(result, "StreamCreated");

      assert.equal(stream.token, this.xdex.address);
      assert.equal(stream.sender, alice);
      assert.equal(stream.recipient, bob);
      assert.equal(stream.depositAmount, deposit);
      assert.equal(stream.startBlock, startBlock);
      assert.equal(stream.stopBlock, stopBlock);
      assert.equal(stream.remainingBalance, deposit);

      //token transfered to the contract
      let balance = (
        await this.xdex.balanceOf(this.halflifelinear.address)
      ).toString();
      assert.equal(balance, deposit);

      //increase next stream id
      const nextStreamId = await this.halflifelinear.nextStreamId();
      assert.equal(nextStreamId, "2");

      //could withdraw all after stop bock
      await time.advanceBlockTo("105");
      assert.equal(
        (await this.halflifelinear.balanceOf("1", bob)).toString(),
        deposit
      );
    });

    it("should return balance of the stream", async () => {
      await this.xdex.approve(this.halflifelinear.address, "1000", {
        from: alice,
      });
      await this.halflifelinear.createStream(
        this.xdex.address,
        bob,
        "60",
        "140",
        "160",
        {
          from: alice,
        }
      );

      await time.advanceBlockTo("135");
      //return sender balance of the stream
      assert.equal(
        (await this.halflifelinear.balanceOf("1", alice)).toString(),
        "60"
      );
      //return recipient balance of the stream
      assert.equal(
        (await this.halflifelinear.balanceOf("1", bob)).toString(),
        "0"
      );
      //return 0 for anyone else
      assert.equal(
        (await this.halflifelinear.balanceOf("1", carol)).toString(),
        "0"
      );

      await time.advanceBlockTo("155");
      //return sender balance of the stream
      assert.equal(
        (await this.halflifelinear.balanceOf("1", alice)).toString(),
        "15"
      );
      //return recipient balance of the stream
      assert.equal(
        (await this.halflifelinear.balanceOf("1", bob)).toString(),
        "45"
      );
      //return 0 for anyone else
      assert.equal(
        (await this.halflifelinear.balanceOf("1", carol)).toString(),
        "0"
      );

      await time.advanceBlockTo("160");
      //return sender balance of the stream
      assert.equal(
        (await this.halflifelinear.balanceOf("1", alice)).toString(),
        "0"
      );
      //return recipient balance of the stream
      assert.equal(
        (await this.halflifelinear.balanceOf("1", bob)).toString(),
        "60"
      );
      //return 0 for anyone else
      assert.equal(
        (await this.halflifelinear.balanceOf("1", carol)).toString(),
        "0"
      );
    });

    it("should withdraw from the stream", async () => {
      await this.xdex.approve(this.halflifelinear.address, "1000", {
        from: alice,
      });
      let streamResult = await this.halflifelinear.createStream(
        this.xdex.address,
        bob,
        "100",
        "200",
        "225",
        { from: alice }
      );

      await time.advanceBlockTo("195");
      await expectRevert(
        this.halflifelinear.withdrawFromStream("1", "10", { from: carol }),
        "caller is not the sender or the recipient of the stream"
      );

      await time.advanceBlockTo("201");
      await expectRevert(
        this.halflifelinear.withdrawFromStream("1", "10", { from: bob }),
        "amount exceeds the available balance"
      );

      await time.advanceBlockTo("210");
      assert.equal((await this.xdex.balanceOf(bob)).toString(), "0");
      assert.equal(
        (await this.halflifelinear.balanceOf("1", bob)).toString(),
        "40"
      ); // block 210

      //bob withdraw 20 from liner
      let result = await this.halflifelinear.withdrawFromStream("1", "20", {
        from: bob,
      }); // block 211

      //emits a WithdrawFromStream event
      truffleAssert.eventEmitted(result, "WithdrawFromStream");

      //decreases bob's balance in stream
      assert.equal((await this.xdex.balanceOf(bob)).toString(), "20"); // block 211
      assert.equal(
        (await this.halflifelinear.balanceOf("1", bob)).toString(),
        "24"
      );

      //remainingBalance should be zero when withdrawn in full
      await time.advanceBlockTo("250");
      await this.halflifelinear.withdrawFromStream("1", "80", { from: bob });
      assert.equal((await this.xdex.balanceOf(bob)).toString(), "100");
      let stream = await this.halflifelinear.getStream(
        Number(streamResult.logs[0].args.streamId)
      );
      assert.equal(stream.remainingBalance.toString(), 0);
    });

    it("should cancel the stream", async () => {
      await expectRevert(
        this.halflifelinear.cancelStream("10", { from: bob }),
        "stream does not exist"
      );

      await time.advanceBlockTo("299");
      await this.xdex.approve(this.halflifelinear.address, "1000", {
        from: alice,
      });
      await this.halflifelinear.createStream(
        this.xdex.address,
        bob,
        "300",
        "350",
        "400",
        {
          from: alice,
        }
      );

      assert.equal((await this.xdex.balanceOf(alice)).toString(), "1700");
      assert.equal((await this.xdex.balanceOf(bob)).toString(), "0");

      await time.advanceBlockTo("359");
      let result = await this.halflifelinear.cancelStream("1", { from: bob }); // block 360

      //emits a cancel event
      truffleAssert.eventEmitted(result, "StreamCanceled");

      //transfer tokens to the stream sender and recipient
      assert.equal((await this.xdex.balanceOf(bob)).toString(), "60");
      assert.equal((await this.xdex.balanceOf(alice)).toString(), "1940");
    });
  });
});
