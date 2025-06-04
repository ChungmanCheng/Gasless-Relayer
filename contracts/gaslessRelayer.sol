// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract GaslessRelayer is EIP712, Ownable {
    using ECDSA for bytes32;

    AggregatorV3Interface public priceFeed;
    IERC20 public feeToken;
    uint256 public gasOverhead;
    mapping(address => uint256) public nonces;

    // EIP-712 typed data struct
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    bytes32 private constant FORWARD_REQUEST_TYPEHASH = keccak256(
        "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)"
    );

    event TransactionRelayed(address indexed from, address indexed to, bool success, bytes returnData);
    event gasOverheadUpdated(uint256 newGas);
    event FeeTokenUpdated(address newToken);
    event DebugInfo(
        address from,
        address relayer,
        uint256 gas,
        uint256 balance,
        uint256 allowance
    );

    constructor(address _feeToken, uint256 _gasOverhead, address _priceFeed) EIP712("GaslessRelayer", "1") Ownable() {
        feeToken = IERC20(_feeToken);
        gasOverhead = _gasOverhead;
        priceFeed = AggregatorV3Interface(_priceFeed);
        emit FeeTokenUpdated(_feeToken);
        emit gasOverheadUpdated(_gasOverhead);
    }

    function verify(
        ForwardRequest calldata req,
        bytes calldata signature
    ) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                FORWARD_REQUEST_TYPEHASH,
                req.from,
                req.to,
                req.value,
                req.gas,
                req.nonce,
                keccak256(req.data)
            ))
        ).recover(signature);
        return nonces[req.from] == req.nonce && signer == req.from;
    }

    function execute(
        ForwardRequest calldata req,
        bytes calldata signature
    ) external returns (bool success, bytes memory ret) {
        require(verify(req, signature), "Invalid signature");

        uint256 balance = feeToken.balanceOf(req.from);
        uint256 allowance = feeToken.allowance(req.from, address(this));

        // Estimate gas: use req.gas + overhead
        uint256 totalGas = req.gas + gasOverhead;
        uint256 gasPrice = tx.gasprice; // Current gas price in wei
        uint256 ethCost = totalGas * gasPrice; // Cost in wei (ETH * 1e18)

        // Get ETH price in USDC (6 decimals, e.g., 2000e6 for 2000 USDC/ETH)
        uint256 ethPriceInUSDC = getEthPriceInUSDC();
        // Convert ETH cost to USDC: (ethCost * ethPriceInUSDC) / 1e18
        uint256 feeInUSDC = (ethCost * ethPriceInUSDC) / 1e18;

        emit DebugInfo(req.from, msg.sender, feeInUSDC, balance, allowance);

        require(feeToken.transferFrom(req.from, msg.sender, feeInUSDC), "Fee transfer failed");

        nonces[req.from]++;
        (success, ret) = req.to.call{gas: req.gas, value: req.value}(req.data);

        emit TransactionRelayed(req.from, req.to, success, ret);

        return (success, ret);
    }


    function setFee(uint256 _newGas) external onlyOwner {
        gasOverhead = _newGas;
        emit gasOverheadUpdated(_newGas);
    }

    function setFeeToken(address _newToken) external onlyOwner {
        feeToken = IERC20(_newToken);
        emit FeeTokenUpdated(_newToken);
    }

    function getNonce(address from) external view returns (uint256) {
        return nonces[from];
    }

    function getEthPriceInUSDC() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed");
        // Chainlink ETH/USD returns price with 8 decimals
        // Convert to USDC (6 decimals): price * 10^6 / 10^8 = price / 10^2
        return uint256(price) / 100; // e.g., 200000000000 -> 2000000 (2000 USDC/ETH)
    }

    // Allow contract to receive ETH for transaction value
    receive() external payable {}
}