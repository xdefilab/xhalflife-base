pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./lib/AddressHelper.sol";
import "./interfaces/IERC20.sol";

/**
 * @notice Deprecated!
 */
contract XHalfLifeCDF is ReentrancyGuard {
    using SafeMath for uint256;
    using AddressHelper for address;

    /**
     * @notice Counter for new stream ids.
     */
    uint256 public nextStreamId = 1;

    uint256 public CDFPrecision = 10**10;

    struct Stream {
        uint256 depositAmount;
        uint256 remainingBalance;
        uint256 startBlock;
        uint256 stopBlock;
        address token;
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

    modifier createStreamPreflight(
        address recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 stopBlock
    ) {
        require(recipient != address(0), "stream to the zero address");
        require(recipient != address(this), "stream to the contract itself");
        require(recipient != msg.sender, "stream to the caller");
        require(depositAmount > 0, "depositAmount is zero");
        require(startBlock >= block.number, "start block before block.number");
        require(stopBlock > startBlock, "stop block before the start block");
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
        address token,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 stopBlock
    );

    /**
     * @notice Emits when the recipient of a stream withdraws a portion or all their pro rata share of the stream.
     */
    event WithdrawFromStream(
        address indexed token,
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
        address token,
        uint256 senderBalance,
        uint256 recipientBalance
    );

    constructor() public {}

    /**
     * @notice Creates a new stream funded by `msg.sender` and paid towards `recipient`.
     * @dev Throws if paused.
     *  Throws if the token is not a contract.
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
     * @param token the stream of ERC20 token.
     * @param recipient The address towards which the money is streamed.
     * @param depositAmount The amount of money to be streamed.
     * @param startBlock stream start block
     * @param stopBlock stream end block
     * @return The uint256 id of the newly created stream.
     */
    function createStream(
        address token,
        address recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 stopBlock
    )
        external
        createStreamPreflight(recipient, depositAmount, startBlock, stopBlock)
        returns (uint256)
    {
        require(token.isContract(), "not contract");
        token.safeTransferFrom(msg.sender, address(this), depositAmount);

        /* Create and store the stream object. */
        uint256 streamId = nextStreamId;
        streams[streamId] = Stream({
            remainingBalance: depositAmount,
            depositAmount: depositAmount,
            isEntity: true,
            token: token,
            recipient: recipient,
            sender: msg.sender,
            startBlock: startBlock,
            stopBlock: stopBlock
        });

        nextStreamId = nextStreamId.add(1);

        emit StreamCreated(
            streamId,
            msg.sender,
            recipient,
            token,
            depositAmount,
            startBlock,
            stopBlock
        );
        return streamId;
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
     * @param startBlock stream start block
     * @param stopBlock stream end block
     * @return The uint256 id of the newly created stream.
     */
    function createEtherStream(
        address recipient,
        uint256 startBlock,
        uint256 stopBlock
    )
        external
        payable
        createStreamPreflight(recipient, msg.value, startBlock, stopBlock)
        returns (uint256)
    {
        /* Create and store the stream object. */
        uint256 streamId = nextStreamId;
        streams[streamId] = Stream({
            remainingBalance: msg.value,
            depositAmount: msg.value,
            isEntity: true,
            token: address(0x0),
            recipient: recipient,
            sender: msg.sender,
            startBlock: startBlock,
            stopBlock: stopBlock
        });

        nextStreamId = nextStreamId.add(1);

        emit StreamCreated(
            streamId,
            msg.sender,
            recipient,
            address(0x0),
            msg.value,
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
            address token,
            address sender,
            address recipient,
            uint256 depositAmount,
            uint256 startBlock,
            uint256 stopBlock,
            uint256 remainingBalance
        )
    {
        Stream memory stream = streams[streamId];
        sender = stream.sender;
        token = stream.token;
        recipient = stream.recipient;
        depositAmount = stream.depositAmount;
        startBlock = stream.startBlock;
        stopBlock = stream.stopBlock;
        remainingBalance = stream.remainingBalance;
    }

    function normalCDF(uint256 x, bool positive) public view returns (uint256) {
        uint256[6] memory params =
            [
                uint256(498673470),
                uint256(211410061),
                uint256(32776263),
                uint256(380036),
                uint256(488906),
                uint256(53830)
            ];

        uint256 f = 0;
        for (uint256 i = 6; i > 0; i--) {
            f = x.mul(params[i.sub(1)].add(f)).div(CDFPrecision);
        }
        f = f.add(CDFPrecision);

        uint256 temp = f;
        for (uint256 j = 0; j < 16; j++) {
            f = temp.mul(f).div(CDFPrecision);
        }
        f = (CDFPrecision**2).div(f);

        if (positive) {
            f = (CDFPrecision).sub(f.div(2));
        } else {
            f = f.div(2);
        }

        return f;
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
            bool positive = true;
            uint256 subParms = uint256(3).mul(CDFPrecision);
            uint256 blockNumberMap =
                (block.number.sub(stream.startBlock))
                    .mul(6)
                    .mul(CDFPrecision)
                    .div(stream.stopBlock - stream.startBlock);
            if (blockNumberMap >= subParms) {
                blockNumberMap = blockNumberMap.sub(subParms);
            } else {
                positive = false;
                blockNumberMap = subParms.sub(blockNumberMap);
            }
            recipientBalance = stream
                .depositAmount
                .mul(
                normalCDF(blockNumberMap, positive).sub(
                    normalCDF(subParms, false)
                )
            )
                .mul(1000)
                .div(997)
                .div(CDFPrecision);
            recipientBalance = recipientBalance <= stream.depositAmount
                ? recipientBalance
                : stream.depositAmount;
        } else {
            recipientBalance = stream.depositAmount;
        }

        /*
         * If the stream `balance` does not equal `deposit`, it means there have been withdrawals.
         * We have to subtract the total amount withdrawn from the amount of money that has been
         * streamed until now.
         */
        if (stream.depositAmount > stream.remainingBalance) {
            uint256 withdrawalAmount =
                stream.depositAmount.sub(stream.remainingBalance);
            /* `withdrawalAmount` cannot and should not be bigger than `recipientBalance`. */
            recipientBalance = recipientBalance.sub(withdrawalAmount);
        }

        if (who == stream.recipient) {
            return recipientBalance;
        }
        if (who == stream.sender) {
            /* `recipientBalance` cannot and should not be bigger than `remainingBalance`. */
            uint256 senderBalance =
                stream.remainingBalance.sub(recipientBalance);
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

        Stream storage stream = streams[streamId];
        require(
            stream.remainingBalance > 0,
            "stream remaining balance is zero"
        );

        uint256 balance = balanceOf(streamId, stream.recipient);
        require(balance >= amount, "amount exceeds the available balance");

        stream.remainingBalance = stream.remainingBalance.sub(amount);
        if (stream.token == address(0x0)) {
            stream.recipient.safeTransferEther(amount);
        } else {
            stream.token.safeTransfer(stream.recipient, amount);
        }
        emit WithdrawFromStream(
            stream.token,
            streamId,
            stream.recipient,
            amount
        );
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
            if (stream.token == address(0x0)) {
                stream.recipient.safeTransferEther(recipientBalance);
            } else {
                stream.token.safeTransfer(stream.recipient, recipientBalance);
            }
        }

        if (senderBalance > 0) {
            if (stream.token == address(0x0)) {
                stream.sender.safeTransferEther(senderBalance);
            } else {
                stream.token.safeTransfer(stream.sender, senderBalance);
            }
        }

        emit StreamCanceled(
            streamId,
            stream.sender,
            stream.recipient,
            stream.token,
            senderBalance,
            recipientBalance
        );
        return true;
    }
}
