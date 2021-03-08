pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract MockToken is ERC20, ERC20Detailed {
    address public core;

    constructor(string memory name, string memory symbol)
        public
        ERC20Detailed(name, symbol, 18)
    {
        core = msg.sender;
    }

    modifier onlyCore() {
        require(msg.sender == core, "Not Authorized");
        _;
    }

    function setCore(address _core) public onlyCore {
        require(_core != address(0), "ERR_ZERO_ADDRESS");
        core = _core;
    }

    function mint(address account, uint256 amount) public onlyCore {
        _mint(account, amount);
    }
}
