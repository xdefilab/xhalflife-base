pragma solidity 0.5.17;

interface IXHalfLife {
    function createStream(
        address token,
        address recipient,
        uint256 depositAmount,
        uint256 startBlock,
        uint256 kBlock,
        uint256 unlockRatio
    ) external returns (uint256);

    function createEtherStream(
        address recipient,
        uint256 startBlock,
        uint256 kBlock,
        uint256 unlockRatio
    ) external payable returns (uint256);

    function getStream(uint256 streamId)
        external
        view
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
        );

    function fundStream(uint256 streamId, uint256 amount)
        public
        payable
        returns (bool);

    function balanceOf(uint256 streamId)
        public
        view
        returns (uint256 withdrawable, uint256 remaining);

    function withdrawFromStream(uint256 streamId, uint256 amount)
        external
        returns (bool);

    function cancelStream(uint256 streamId) external returns (bool);

    function getVersion() external pure returns (bytes32);
}
