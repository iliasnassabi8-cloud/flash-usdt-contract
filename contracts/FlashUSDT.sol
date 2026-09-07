// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

/**
 * @title FlashUSDT
 * @dev A comprehensive USDT-based contract with swap, transfer, and trading functionalities.
 */
contract FlashUSDT is IERC20 {
    // ============ State Variables ============
    string public name = "Flash USDT";
    string public symbol = "fUSDT";
    uint8 public decimals = 6;
    uint256 private _totalSupply = 1_000_000_000 * 10**6;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public owner;
    mapping(address => bool) public admins;
    mapping(address => bool) public traders;

    uint256 public constant MAX_DURATION = 180;

    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenPrices;
    mapping(address => uint256) public tradingLimits;

    struct Trade {
        address trader;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 price;
        uint256 duration;
        uint256 createdAt;
        bool completed;
    }

    struct TransferRecord {
        address from;
        address to;
        uint256 amount;
        uint256 duration;
        uint256 createdAt;
        bool completed;
    }

    mapping(uint256 => Trade) public trades;
    mapping(uint256 => TransferRecord) public transfers;
    uint256 public tradeCounter = 0;
    uint256 public transferCounter = 0;

    mapping(address => bool) public frozenAccounts;

    // ============ Events ============
    event SwapExecuted(
        indexed address user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 price
    );

    event TradeInitiated(
        indexed uint256 tradeId,
        indexed address trader,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 duration
    );

    event TradeCompleted(
        indexed uint256 tradeId,
        indexed address trader,
        uint256 amountOut
    );

    event ScheduledTransfer(
        indexed uint256 transferId,
        indexed address from,
        indexed address to,
        uint256 amount,
        uint256 duration
    );

    event ScheduledTransferCompleted(
        indexed uint256 transferId,
        indexed address from,
        indexed address to,
        uint256 amount
    );

    event TradingLimitUpdated(
        indexed address token,
        uint256 newLimit
    );

    event PriceUpdated(
        indexed address token,
        uint256 newPrice
    );

    event AccountFrozen(indexed address account, string reason);
    event AccountUnfrozen(indexed address account);

    // ============ Modifiers ============
    modifier onlyOwner() {
        require(msg.sender == owner, "FlashUSDT: Only owner can execute this");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "FlashUSDT: Only admin can execute this");
        _;
    }

    modifier onlyTrader() {
        require(traders[msg.sender], "FlashUSDT: Only trader can execute this");
        _;
    }

    modifier notFrozen(address account) {
        require(!frozenAccounts[account], "FlashUSDT: Account is frozen");
        _;
    }

    modifier validDuration(uint256 duration) {
        require(duration > 0 && duration <= MAX_DURATION, "FlashUSDT: Invalid duration");
        _;
    }

    // ============ Constructor ============
    constructor() {
        owner = msg.sender;
        admins[msg.sender] = true;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    // ============ ERC20 Standard Functions ============
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override notFrozen(msg.sender) returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public override notFrozen(msg.sender) returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override notFrozen(sender) returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    // ============ Internal Transfer Functions ============
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "FlashUSDT: Transfer from zero address");
        require(recipient != address(0), "FlashUSDT: Transfer to zero address");
        require(amount > 0, "FlashUSDT: Transfer amount must be greater than zero");
        require(_balances[sender] >= amount, "FlashUSDT: Insufficient balance");

        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0), "FlashUSDT: Approve from zero address");
        require(spender != address(0), "FlashUSDT: Approve to zero address");

        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    // ============ Swap Functions ============
    /**
     * @dev Swaps USDT for another supported token at the current price
     */
    function swapUSDTForToken(
        address tokenOut,
        uint256 amountIn
    ) public notFrozen(msg.sender) returns (uint256 amountOut) {
        require(supportedTokens[tokenOut], "FlashUSDT: Token not supported");
        require(amountIn > 0, "FlashUSDT: Amount must be greater than zero");
        require(_balances[msg.sender] >= amountIn, "FlashUSDT: Insufficient balance");

        uint256 price = tokenPrices[tokenOut];
        require(price > 0, "FlashUSDT: Price not set for token");

        amountOut = (amountIn * 10**18) / price;

        _balances[msg.sender] -= amountIn;
        _totalSupply -= amountIn;

        emit SwapExecuted(msg.sender, address(this), tokenOut, amountIn, amountOut, price);
        emit Transfer(msg.sender, address(0), amountIn);

        return amountOut;
    }

    /**
     * @dev Swaps another token for USDT at the current price
     */
    function swapTokenForUSDT(
        address tokenIn,
        uint256 amountIn
    ) public notFrozen(msg.sender) returns (uint256 amountOut) {
        require(supportedTokens[tokenIn], "FlashUSDT: Token not supported");
        require(amountIn > 0, "FlashUSDT: Amount must be greater than zero");

        uint256 price = tokenPrices[tokenIn];
        require(price > 0, "FlashUSDT: Price not set for token");

        amountOut = (amountIn * price) / 10**18;

        _balances[msg.sender] += amountOut;
        _totalSupply += amountOut;

        emit SwapExecuted(msg.sender, tokenIn, address(this), amountIn, amountOut, price);
        emit Transfer(address(0), msg.sender, amountOut);

        return amountOut;
    }

    // ============ Transferable Functions ============
    /**
     * @dev Initiates a scheduled transfer with a specified duration
     */
    function scheduleTransfer(
        address recipient,
        uint256 amount,
        uint256 duration
    ) public notFrozen(msg.sender) validDuration(duration) returns (uint256) {
        require(recipient != address(0), "FlashUSDT: Invalid recipient address");
        require(amount > 0, "FlashUSDT: Transfer amount must be greater than zero");
        require(_balances[msg.sender] >= amount, "FlashUSDT: Insufficient balance");

        uint256 transferId = transferCounter;
        transferCounter++;

        transfers[transferId] = TransferRecord({
            from: msg.sender,
            to: recipient,
            amount: amount,
            duration: duration,
            createdAt: block.timestamp,
            completed: false
        });

        emit ScheduledTransfer(transferId, msg.sender, recipient, amount, duration);
        return transferId;
    }

    /**
     * @dev Executes a scheduled transfer after the duration has passed
     */
    function executeScheduledTransfer(uint256 transferId) public {
        TransferRecord storage transfer_ = transfers[transferId];
        require(!transfer_.completed, "FlashUSDT: Transfer already completed");
        require(block.timestamp >= transfer_.createdAt + (transfer_.duration * 1 days), "FlashUSDT: Duration not yet elapsed");

        transfer_.completed = true;

        _transfer(transfer_.from, transfer_.to, transfer_.amount);

        emit ScheduledTransferCompleted(transferId, transfer_.from, transfer_.to, transfer_.amount);
    }

    /**
     * @dev Cancels a scheduled transfer if not yet executed
     */
    function cancelScheduledTransfer(uint256 transferId) public {
        TransferRecord storage transfer_ = transfers[transferId];
        require(!transfer_.completed, "FlashUSDT: Transfer already completed");
        require(msg.sender == transfer_.from || msg.sender == owner, "FlashUSDT: Only initiator or owner can cancel");

        transfer_.completed = true;
    }

    /**
     * @dev Gets details of a scheduled transfer
     */
    function getScheduledTransfer(uint256 transferId) public view returns (TransferRecord memory) {
        return transfers[transferId];
    }

    // ============ Trading Functions ============
    /**
     * @dev Initiates a trade with a specified duration
     */
    function initiateTrade(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 duration
    ) public onlyTrader notFrozen(msg.sender) validDuration(duration) returns (uint256) {
        require(tokenIn != address(0) && tokenOut != address(0), "FlashUSDT: Invalid token addresses");
        require(amountIn > 0 && amountOut > 0, "FlashUSDT: Amounts must be greater than zero");
        require(amountIn <= tradingLimits[tokenIn], "FlashUSDT: Amount exceeds trading limit");

        uint256 tradeId = tradeCounter;
        tradeCounter++;

        uint256 price = tokenPrices[tokenOut];
        require(price > 0, "FlashUSDT: Price not set for token");

        trades[tradeId] = Trade({
            trader: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            price: price,
            duration: duration,
            createdAt: block.timestamp,
            completed: false
        });

        emit TradeInitiated(tradeId, msg.sender, tokenIn, tokenOut, amountIn, amountOut, duration);
        return tradeId;
    }

    /**
     * @dev Executes a pending trade after the duration has passed
     */
    function executeTrade(uint256 tradeId) public onlyAdmin {
        Trade storage trade = trades[tradeId];
        require(!trade.completed, "FlashUSDT: Trade already completed");
        require(block.timestamp >= trade.createdAt + (trade.duration * 1 days), "FlashUSDT: Duration not yet elapsed");

        trade.completed = true;

        emit TradeCompleted(tradeId, trade.trader, trade.amountOut);
    }

    /**
     * @dev Cancels a pending trade if not yet executed
     */
    function cancelTrade(uint256 tradeId) public {
        Trade storage trade = trades[tradeId];
        require(!trade.completed, "FlashUSDT: Trade already completed");
        require(msg.sender == trade.trader || msg.sender == owner, "FlashUSDT: Only trader or owner can cancel");

        trade.completed = true;
    }

    /**
     * @dev Gets details of a trade
     */
    function getTrade(uint256 tradeId) public view returns (Trade memory) {
        return trades[tradeId];
    }

    /**
     * @dev Updates the trading limit for a token
     */
    function setTradingLimit(address token, uint256 newLimit) public onlyAdmin {
        require(token != address(0), "FlashUSDT: Invalid token address");
        tradingLimits[token] = newLimit;
        emit TradingLimitUpdated(token, newLimit);
    }

    /**
     * @dev Gets the trading limit for a token
     */
    function getTradingLimit(address token) public view returns (uint256) {
        return tradingLimits[token];
    }

    // ============ Price Management Functions ============
    /**
     * @dev Sets the price for a token in wei
     */
    function setTokenPrice(address token, uint256 newPrice) public onlyAdmin {
        require(token != address(0), "FlashUSDT: Invalid token address");
        require(newPrice > 0, "FlashUSDT: Price must be greater than zero");
        tokenPrices[token] = newPrice;
        emit PriceUpdated(token, newPrice);
    }

    /**
     * @dev Gets the price of a token
     */
    function getTokenPrice(address token) public view returns (uint256) {
        return tokenPrices[token];
    }

    // ============ Token Management Functions ============
    /**
     * @dev Adds a token to the supported tokens list
     */
    function addSupportedToken(address token) public onlyAdmin {
        require(token != address(0), "FlashUSDT: Invalid token address");
        supportedTokens[token] = true;
    }

    /**
     * @dev Removes a token from the supported tokens list
     */
    function removeSupportedToken(address token) public onlyAdmin {
        require(token != address(0), "FlashUSDT: Invalid token address");
        supportedTokens[token] = false;
    }

    /**
     * @dev Checks if a token is supported
     */
    function isSupportedToken(address token) public view returns (bool) {
        return supportedTokens[token];
    }

    // ============ Access Control Functions ============
    /**
     * @dev Grants admin privileges to an address
     */
    function grantAdmin(address account) public onlyOwner {
        require(account != address(0), "FlashUSDT: Invalid address");
        admins[account] = true;
    }

    /**
     * @dev Revokes admin privileges from an address
     */
    function revokeAdmin(address account) public onlyOwner {
        require(account != address(0), "FlashUSDT: Invalid address");
        admins[account] = false;
    }

    /**
     * @dev Grants trader privileges to an address
     */
    function grantTrader(address account) public onlyAdmin {
        require(account != address(0), "FlashUSDT: Invalid address");
        traders[account] = true;
    }

    /**
     * @dev Revokes trader privileges from an address
     */
    function revokeTrader(address account) public onlyAdmin {
        require(account != address(0), "FlashUSDT: Invalid address");
        traders[account] = false;
    }

    // ============ Account Freeze Functions ============
    /**
     * @dev Freezes an account, preventing all token operations
     */
    function freezeAccount(address account, string memory reason) public onlyAdmin {
        require(account != address(0), "FlashUSDT: Invalid address");
        frozenAccounts[account] = true;
        emit AccountFrozen(account, reason);
    }

    /**
     * @dev Unfreezes an account, allowing all token operations
     */
    function unfreezeAccount(address account) public onlyAdmin {
        require(account != address(0), "FlashUSDT: Invalid address");
        frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    /**
     * @dev Checks if an account is frozen
     */
    function isFrozen(address account) public view returns (bool) {
        return frozenAccounts[account];
    }
}
