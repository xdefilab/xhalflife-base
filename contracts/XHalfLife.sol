pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/address.sol";
import "./interfaces/ERC20.sol";

contract XHalfLife is ReentrancyGuard {
    using SafeMath for uint256;
    using AddressHelper for address;

    /**
     * @notice Counter for new stream ids.
     */
    uint256 public nextStreamId = 1;

    // halflife stream
    struct Stream {
        uint256 depositAmount;
        uint256 remaining; //un-withdrawable balance
        uint256 withdrawable; //withdrawable balance
        uint256 startBlock;
        uint256 kBlock;
        uint256 unlockRatio;
        uint256 denom; // one readable coin represent
        uint256 lastRewardBlock;
        address token; // ERC20 token address or 0x0 for Ether
        address recipient;
        address sender;
        bool isEntity;
    }

    /**
     * @notice The stream objects identifiable by their unsigned integer ids.
     */
    mapping(uint256 => Stream) public streams;

    /**
     * @dev Throws if the provided id does not point to a valid stream.
     */
    modifier streamExists(uint256 streamId) {
        require(streams[streamId].isEntity, "stream does not exist");
        _;
    }

    /**
     * @dev Throws if the caller is not the sender of the recipient of the stream.
     */
    modifier onlySenderOrRecipient(uint256 streamId) {
        require(
            msg.sender == streams[streamId].sender ||
                msg.sender == streams[streamId].recipient,
            "caller is not the sender or the recipient of the stream"
        );
        _;
    }

    /**
     * @dev Throws if the caller is not the sender of the recipient of the stream.
     *  Throws if the recipient is the zero address, the contract itself or the caller.
     *  Throws if the depositAmount is 0.
     *  Throws if the start block is before `block.number`.
     */
    modifier createStreamPreflight(
        address recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 kBlock
    ) {
        require(recipient != address(0), "stream to the zero address");
        require(recipient != address(this), "stream to the contract itself");
        require(recipient != msg.sender, "stream to the caller");
        require(depositAmount > 0, "depositAmount is zero");
        require(startBlock >= block.number, "start block before block.number");
        require(kBlock > 0, "k block is zero");
        _;
    }

    event StreamCreated(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 kBlock,
        uint256 unlockRatio
    );

    event WithdrawFromStream(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );

    event StreamCanceled(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 senderBalance,
        uint256 recipientBalance
    );

    event StreamFunded(uint256 indexed streamId, uint256 amount);

    /**
     * @notice Creates a new stream funded by `msg.sender` and paid towards `recipient`.
     * @dev Throws if paused.
     *  Throws if the token is not a contract address
     *  Throws if the recipient is the zero address, the contract itself or the caller.
     *  Throws if the depositAmount is 0.
     *  Throws if the start block is before `block.number`.
     *  Throws if the rate calculation has a math error.
     *  Throws if the next stream id calculation has a math error.
     *  Throws if the contract is not allowed to transfer enough tokens.
     * @param token The ERC20 token address
     * @param recipient The address towards which the money is streamed.
     * @param depositAmount The amount of money to be streamed.
     * @param startBlock stream start block
     * @param kBlock unlock every k blocks
     * @param unlockRatio unlock ratio from remaining balanceß
     * @return The uint256 id of the newly created stream.
     */
    function createStream(
        address token,
        address recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 kBlock,
        uint256 unlockRatio
    )
        external
        createStreamPreflight(recipient, depositAmount, startBlock, kBlock)
        returns (uint256)
    {
        require(token.isContract(), "not contract");
        token.safeTransferFrom(msg.sender, address(this), depositAmount);

        uint256 streamId = nextStreamId;
        {
            uint256 denom = 10**uint256(IERC20(token).decimals());
            require(denom >= 10**6, "token decimal too low");
            require(unlockRatio < denom, "unlockRatio must < 100%");
            require(unlockRatio >= denom.div(100), "unlockRatio must >= 0.1%");
            streams[streamId] = Stream({
                token: token,
                remaining: depositAmount,
                withdrawable: 0,
                depositAmount: depositAmount,
                startBlock: startBlock,
                kBlock: kBlock,
                unlockRatio: unlockRatio,
                denom: denom,
                lastRewardBlock: startBlock,
                recipient: recipient,
                sender: msg.sender,
                isEntity: true
            });
        }

        nextStreamId = nextStreamId.add(1);
        emit StreamCreated(
            streamId,
            msg.sender,
            recipient,
            token,
            depositAmount,
            startBlock,
            kBlock,
            unlockRatio
        );
        return streamId;
    }

    /**
     * @notice Creates a new ether stream funded by `msg.sender` and paid towards `recipient`.
     * @dev Throws if paused.
     *  Throws if the recipient is the zero address, the contract itself or the caller.
     *  Throws if the depositAmount is 0.
     *  Throws if the start block is before `block.number`.
     *  Throws if the rate calculation has a math error.
     *  Throws if the next stream id calculation has a math error.
     *  Throws if the contract is not allowed to transfer enough tokens.
     * @param recipient The address towards which the money is streamed.
     * @param startBlock stream start block
     * @param kBlock unlock every k blocks
     * @param unlockRatio unlock ratio from remaining balanceß
     * @return The uint256 id of the newly created stream.
     */
    function createEtherStream(
        address recipient,
        uint256 startBlock,
        uint256 kBlock,
        uint256 unlockRatio
    )
        external
        payable
        createStreamPreflight(recipient, msg.value, startBlock, kBlock)
        nonReentrant
        returns (uint256)
    {
        require(unlockRatio >= 10**16, "unlockRatio must >= 0.1%");
        require(unlockRatio < 10**18, "unlockRatio must < 100%");
        /* Create and store the stream object. */
        uint256 streamId = nextStreamId;
        streams[streamId] = Stream({
            token: address(0x0),
            remaining: msg.value,
            withdrawable: 0,
            depositAmount: msg.value,
            startBlock: startBlock,
            kBlock: kBlock,
            unlockRatio: unlockRatio,
            denom: 10**18,
            lastRewardBlock: startBlock,
            recipient: recipient,
            sender: msg.sender,
            isEntity: true
        });

        nextStreamId = nextStreamId.add(1);

        emit StreamCreated(
            streamId,
            msg.sender,
            recipient,
            address(0x0),
            msg.value,
            startBlock,
            kBlock,
            unlockRatio
        );
        return streamId;
    }

    /**
     * @notice Returns the stream with all its properties.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream to query.
     * @return sender
     * @return recipient
     * @return token
     * @return depositAmount
     * @return startBlock
     * @return kBlock
     * @return remaining
     * @return withdrawable
     * @return unlockRatio
     * @return lastRewardBlock
     */
    function getStream(uint256 streamId)
        external
        view
        streamExists(streamId)
        returns (
            address sender,
            address recipient,
            address token,
            uint256 depositAmount,
            uint256 startBlock,
            uint256 kBlock,
            uint256 remaining,
            uint256 withdrawable,
            uint256 unlockRatio,
            uint256 lastRewardBlock
        )
    {
        Stream memory stream = streams[streamId];
        sender = stream.sender;
        recipient = stream.recipient;
        token = stream.token;
        depositAmount = stream.depositAmount;
        startBlock = stream.startBlock;
        kBlock = stream.kBlock;
        remaining = stream.remaining;
        withdrawable = stream.withdrawable;
        unlockRatio = stream.unlockRatio;
        lastRewardBlock = stream.lastRewardBlock;
    }

    /**
     * @notice funds to an existing stream.
     * Throws if the caller is not the stream.sender
     * @param streamId The id of the stream to query.
     * @param amount deposit amount by stream sender
     */
    function fundStream(uint256 streamId, uint256 amount)
        public
        payable
        nonReentrant
        streamExists(streamId)
        returns (bool)
    {
        Stream storage stream = streams[streamId];
        require(
            msg.sender == stream.sender,
            "caller must be the sender of the stream"
        );
        require(amount > 0, "amount is zero");
        if (stream.token == address(0x0)) {
            require(amount == msg.value, "bad ether fund");
        } else {
            stream.token.safeTransferFrom(msg.sender, address(this), amount);
        }

        (uint256 recipientBalance, uint256 remainingBalance) =
            balanceOf(streamId);
        uint256 m = block.number.sub(stream.startBlock).mod(stream.kBlock);
        uint256 lastRewardBlock = block.number.sub(m);

        stream.lastRewardBlock = lastRewardBlock;
        stream.remaining = remainingBalance.add(amount);
        stream.withdrawable = recipientBalance;

        //add funds to total deposit amount
        stream.depositAmount = stream.depositAmount.add(amount);
        emit StreamFunded(streamId, amount);
        return true;
    }

    /**
     * @notice Returns the available funds for the given stream id and address.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream for which to query the balance.
     * @return withdrawable The total funds allocated to `recipient` and `sender` as uint256.
     * @return remaining The total funds allocated to `recipient` and `sender` as uint256.
     */
    function balanceOf(uint256 streamId)
        public
        view
        streamExists(streamId)
        returns (uint256 withdrawable, uint256 remaining)
    {
        Stream memory stream = streams[streamId];

        if (block.number < stream.startBlock) {
            return (0, stream.depositAmount);
        }

        uint256 lastBalance = stream.withdrawable;

        //If `remaining` not equal zero, it means there have been added funds.
        uint256 r = stream.remaining;
        uint256 w = 0;
        uint256 n = block.number.sub(stream.lastRewardBlock).div(stream.kBlock);
        for (uint256 i = 0; i < n; i++) {
            uint256 reward = r.mul(stream.unlockRatio).div(stream.denom);
            w = w.add(reward);
            r = r.sub(reward);
        }

        stream.remaining = r;
        stream.withdrawable = w;
        if (lastBalance > 0) {
            stream.withdrawable = stream.withdrawable.add(lastBalance);
        }

        //If `remaining` + `withdrawable` < `depositAmount`, it means there have withdraws.
        require(
            stream.remaining.add(stream.withdrawable) <= stream.depositAmount,
            "balanceOf: remaining or withdrawable amount is bad"
        );

        // 0.0001 TOKEN
        uint256 effectiveValue = stream.denom.div(10**4);

        if (stream.withdrawable >= effectiveValue) {
            withdrawable = stream.withdrawable;
        } else {
            withdrawable = 0;
        }

        if (stream.remaining >= effectiveValue) {
            remaining = stream.remaining;
        } else {
            remaining = 0;
        }
    }

    /**
     * @notice Withdraws from the contract to the recipient's account.
     * @dev Throws if the id does not point to a valid stream.
     *  Throws if the amount exceeds the withdrawable balance.
     *  Throws if the amount < the effective withdraw value.
     *  Throws if the caller is not the recipient.
     * @param streamId The id of the stream to withdraw tokens from.
     * @param amount The amount of tokens to withdraw.
     * @return bool true=success, otherwise false.
     */
    function withdrawFromStream(uint256 streamId, uint256 amount)
        external
        nonReentrant
        streamExists(streamId)
        onlySenderOrRecipient(streamId)
        returns (bool)
    {
        Stream storage stream = streams[streamId];

        // 0.0001 TOKEN
        uint256 effectiveValue = stream.denom.div(10**4);

        require(
            amount >= effectiveValue,
            "amount is zero or little than the effective withdraw value"
        );

        (uint256 recipientBalance, uint256 remainingBalance) =
            balanceOf(streamId);

        require(
            recipientBalance >= amount,
            "withdraw amount exceeds the available balance"
        );

        if (stream.token == address(0x0)) {
            stream.recipient.safeTransferEther(amount);
        } else {
            stream.token.safeTransfer(stream.recipient, amount);
        }

        uint256 m = block.number.sub(stream.startBlock).mod(stream.kBlock);
        uint256 lastRewardBlock = block.number.sub(m);

        stream.lastRewardBlock = lastRewardBlock;
        stream.remaining = remainingBalance;
        stream.withdrawable = recipientBalance.sub(amount);

        emit WithdrawFromStream(streamId, stream.recipient, amount);
        return true;
    }

    /**
     * @notice Cancels the stream and transfers the tokens back
     * @dev Throws if the id does not point to a valid stream.
     *  Throws if the caller is not the sender or the recipient of the stream.
     *  Throws if there is a token transfer failure.
     * @param streamId The id of the stream to cancel.
     * @return bool true=success, otherwise false.
     */
    function cancelStream(uint256 streamId)
        external
        nonReentrant
        streamExists(streamId)
        onlySenderOrRecipient(streamId)
        returns (bool)
    {
        Stream memory stream = streams[streamId];
        (uint256 withdrawable, uint256 remaining) = balanceOf(streamId);

        //save gas
        delete streams[streamId];

        if (withdrawable > 0) {
            if (stream.token == address(0x0)) {
                stream.recipient.safeTransferEther(withdrawable);
            } else {
                stream.token.safeTransfer(stream.recipient, withdrawable);
            }
        }

        if (remaining > 0) {
            if (stream.token == address(0x0)) {
                stream.sender.safeTransferEther(remaining);
            } else {
                stream.token.safeTransfer(stream.sender, remaining);
            }
        }

        emit StreamCanceled(
            streamId,
            stream.sender,
            stream.recipient,
            withdrawable,
            remaining
        );
        return true;
    }

    function getVersion() external pure returns (bytes32) {
        return bytes32("APOLLO");
    }
}
