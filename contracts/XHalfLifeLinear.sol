pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract XHalfLifeLinear is ReentrancyGuard {
    using SafeMath for uint256;

    // The XDEX TOKEN!
    IERC20 public _xdex;

    /**
     * @notice Counter for new stream ids.
     */
    uint256 public nextStreamId = 1;

    // XHalfLife Linear Stream
    struct Stream {
        uint256 depositAmount;
        uint256 ratePerBlock;
        uint256 remainingBalance;
        uint256 startBlock;
        uint256 stopBlock;
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

    event CoreTransferred(
        address indexed _coreAddr,
        address indexed _coreAddrNew
    );

    event StreamCreated(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 stopBlock
    );

    /**
     * @notice Emits when the recipient of a stream withdraws a portion or all their pro rata share of the stream.
     */
    event WithdrawFromStream(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );

    /**
     * @notice Emits when a stream is successfully cancelled and tokens are transferred back on a pro rata basis.
     */
    event StreamCanceled(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 senderBalance,
        uint256 recipientBalance
    );

    constructor(IERC20 _xdexToken) public {
        _xdex = _xdexToken;
    }

    /**
     * @notice Creates a new stream funded by `msg.sender` and paid towards `recipient`.
     * @dev Throws if paused.
     *  Throws if the recipient is the zero address, the contract itself or the caller.
     *  Throws if the deposit is 0.
     *  Throws if the start time is before `block.timestamp`.
     *  Throws if the stop time is before the start time.
     *  Throws if the duration calculation has a math error.
     *  Throws if the deposit is smaller than the duration.
     *  Throws if the deposit is not a multiple of the duration.
     *  Throws if the rate calculation has a math error.
     *  Throws if the next stream id calculation has a math error.
     *  Throws if the contract is not allowed to transfer enough tokens.
     *  Throws if there is a token transfer failure.
     * @param recipient The address towards which the money is streamed.
     * @param depositAmount The amount of money to be streamed.
     * @param startBlock stream start block
     * @param stopBlock stream end block
     * @return The uint256 id of the newly created stream.
     */
    function createStream(
        address recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 stopBlock
    ) external returns (uint256) {
        require(recipient != address(0), "stream to the zero address");
        require(recipient != address(this), "stream to the contract itself");
        require(recipient != msg.sender, "stream to the caller");
        require(depositAmount > 0, "depositAmount is zero");
        require(startBlock >= block.number, "start block before block.number");
        require(stopBlock > startBlock, "stop block before the start block");

        uint256 duration = stopBlock.sub(startBlock);

        /* Without this, the rate per block would be zero. */
        require(
            depositAmount >= duration,
            "deposit smaller than duration blocks"
        );

        uint256 perBlock = depositAmount.div(duration);

        /* Create and store the stream object. */
        uint256 streamId = nextStreamId;
        streams[streamId] = Stream({
            remainingBalance: depositAmount,
            depositAmount: depositAmount,
            isEntity: true,
            ratePerBlock: perBlock,
            recipient: recipient,
            sender: msg.sender,
            startBlock: startBlock,
            stopBlock: stopBlock
        });

        nextStreamId = nextStreamId.add(1);

        require(
            _xdex.transferFrom(
                address(msg.sender),
                address(this),
                depositAmount
            ),
            "createStream: transfer deposit amount failed"
        );

        emit StreamCreated(
            streamId,
            msg.sender,
            recipient,
            depositAmount,
            startBlock,
            stopBlock
        );
        return streamId;
    }

    /**
     * @notice Returns the stream with all its properties.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream to query.
     * @return The stream object.
     */
    function getStream(uint256 streamId)
        external
        view
        streamExists(streamId)
        returns (
            address sender,
            address recipient,
            uint256 depositAmount,
            uint256 startBlock,
            uint256 stopBlock,
            uint256 remainingBalance,
            uint256 ratePerBlock
        )
    {
        sender = streams[streamId].sender;
        recipient = streams[streamId].recipient;
        depositAmount = streams[streamId].depositAmount;
        startBlock = streams[streamId].startBlock;
        stopBlock = streams[streamId].stopBlock;
        remainingBalance = streams[streamId].remainingBalance;
        ratePerBlock = streams[streamId].ratePerBlock;
    }

    /**
     * @notice Returns the available funds for the given stream id and address.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream for which to query the balance.
     * @param who The address for which to query the balance.
     * @return The total funds allocated to `who` as uint256.
     */
    function balanceOf(uint256 streamId, address who)
        public
        view
        streamExists(streamId)
        returns (uint256 balance)
    {
        Stream memory stream = streams[streamId];

        if (who != stream.recipient && who != stream.sender) {
            return 0;
        }

        uint256 recipientBalance = 0;
        if (block.number <= stream.startBlock) {
            recipientBalance = 0;
        } else if (block.number < stream.stopBlock) {
            recipientBalance = block.number.sub(stream.startBlock).mul(
                stream.ratePerBlock
            );
        } else {
            recipientBalance = stream.stopBlock.sub(stream.startBlock).mul(
                stream.ratePerBlock
            );
        }

        /*
         * If the stream `balance` does not equal `deposit`, it means there have been withdrawals.
         * We have to subtract the total amount withdrawn from the amount of money that has been
         * streamed until now.
         */
        if (stream.depositAmount > stream.remainingBalance) {
            uint256 withdrawalAmount = stream.depositAmount.sub(
                stream.remainingBalance
            );
            /* `withdrawalAmount` cannot and should not be bigger than `recipientBalance`. */
            recipientBalance = recipientBalance.sub(withdrawalAmount);
        }

        if (who == stream.recipient) {
            return recipientBalance;
        }
        if (who == stream.sender) {
            /* `recipientBalance` cannot and should not be bigger than `remainingBalance`. */
            uint256 senderBalance = stream.remainingBalance.sub(
                recipientBalance
            );
            return senderBalance;
        }
        return 0;
    }

    /**
     * @notice Withdraws from the contract to the recipient's account.
     * @dev Throws if the id does not point to a valid stream.
     *  Throws if the caller is not the sender or the recipient of the stream.
     *  Throws if the amount exceeds the available balance.
     *  Throws if there is a token transfer failure.
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
        require(amount > 0, "amount is zero");

        Stream memory stream = streams[streamId];
        require(
            stream.remainingBalance > 0,
            "stream remaining balance is zero"
        );

        uint256 balance = balanceOf(streamId, stream.recipient);
        require(balance >= amount, "amount exceeds the available balance");

        streams[streamId].remainingBalance = stream.remainingBalance.sub(
            amount
        );

        _safeXDexTransfer(stream.recipient, amount);
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
        uint256 senderBalance = balanceOf(streamId, stream.sender);
        uint256 recipientBalance = balanceOf(streamId, stream.recipient);

        delete streams[streamId];

        if (recipientBalance > 0) {
            _safeXDexTransfer(stream.recipient, recipientBalance);
        }

        if (senderBalance > 0) {
            _safeXDexTransfer(stream.sender, senderBalance);
        }

        emit StreamCanceled(
            streamId,
            stream.sender,
            stream.recipient,
            senderBalance,
            recipientBalance
        );
        return true;
    }

    // Safe xdex transfer function, just in case if rounding error causes pool to not have enough XDEX.
    function _safeXDexTransfer(address _to, uint256 _amount) internal {
        uint256 xdexBal = _xdex.balanceOf(address(this));
        if (_amount > xdexBal) {
            _xdex.transfer(_to, xdexBal);
        } else {
            _xdex.transfer(_to, _amount);
        }
    }
}
