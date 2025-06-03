// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

library FullMath {
    /// @notice Calculates floor(a×b÷denominator) with full precision.
    /// @dev Throws if result overflows a uint256 or denominator == 0
    /// Credit: Uniswap Labs (ported to Solidity 0.8)
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                require(denominator > 0, "Denominator zero");
                assembly {
                    result := div(prod0, denominator)
                }
                return result;
            }

            require(denominator > prod1, "Overflow");

            uint256 remainder;
            assembly {
                remainder := mulmod(a, b, denominator)
            }
            assembly {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv; // inverse mod 2^8
            inv *= 2 - denominator * inv; // inverse mod 2^16
            inv *= 2 - denominator * inv; // inverse mod 2^32
            inv *= 2 - denominator * inv; // inverse mod 2^64
            inv *= 2 - denominator * inv; // inverse mod 2^128
            inv *= 2 - denominator * inv; // inverse mod 2^256

            result = prod0 * inv;
            return result;
        }
    }
}

library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 2**96;
}


interface _IERC20 {
    function decimals() external view returns (uint256);
}

contract GaslessRelayer is EIP712, Ownable {
    using ECDSA for bytes32;

    IERC20 public feeToken; // USDC (6 decimals)
    IUniswapV3Pool public uniswapPool; // ETH/USDC pool
    uint256 public relayerFee; // Base fee in USDC (6 decimals)
    bool public isToken0USDC; // True if USDC is token0 in the pool

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
    event FeeUpdated(uint256 newFee);
    event FeeTokenUpdated(address newToken);
    event UniswapPoolUpdated(address newPool);
    event DebugInfo(
        address from,
        address relayer,
        uint256 usdcFee,
        uint256 balance,
        uint256 allowance,
        uint256 gasLimit,
        uint256 gasPrice,
        uint256 ethPriceInUSDC
    );

    constructor(
        address _feeToken,
        uint256 _initialFee,
        address _uniswapPool,
        bool _isToken0USDC
    ) EIP712("GaslessRelayer", "1") Ownable() {
        require(_feeToken != address(0), "Invalid fee token address");
        require(_uniswapPool != address(0), "Invalid Uniswap pool address");
        feeToken = IERC20(_feeToken);
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        relayerFee = _initialFee;
        isToken0USDC = _isToken0USDC;
        emit FeeTokenUpdated(_feeToken);
        emit FeeUpdated(_initialFee);
        emit UniswapPoolUpdated(_uniswapPool);
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

    // Get current ETH price in USDC (6 decimals) using Uniswap V3 pool's slot0
    function getEthPriceInUSDC() public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();
        uint256 priceX96 = getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        return getActualPrice(priceX96);
    }

    function getActualPrice(uint256 priceX96) public view returns (uint256) {
        // If USDC is token0, price is ETH/USDC; if ETH is token0, price is USDC/ETH
        address quoteToken = isToken0USDC ? uniswapPool.token0() : uniswapPool.token1();
        uint256 t0Decimals = _IERC20(uniswapPool.token0()).decimals();
        uint256 t1Decimals = _IERC20(uniswapPool.token1()).decimals();
        
        uint256 decimals;
        if (isToken0USDC) {
            // USDC is token0 (ETH/USDC pool), priceX96 is in ETH/USDC
            if (t1Decimals > t0Decimals) {
                decimals = t1Decimals - t0Decimals; // 18 - 6 = 12
            } else {
                decimals = 0;
            }
            return FullMath.mulDiv(priceX96, 10 ** decimals, 2 ** 96); // Returns USDC (6 decimals)
        } else {
            // ETH is token0 (USDC/ETH pool), priceX96 is in USDC/ETH
            if (t0Decimals > t1Decimals) {
                decimals = t0Decimals - t1Decimals; // 18 - 6 = 12
            } else {
                decimals = 0;
            }
            // Invert price to get ETH/USDC
            return FullMath.mulDiv(2 ** 96, 10 ** decimals, priceX96); // Returns USDC (6 decimals)
        }
    }

    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure returns (uint256) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function execute(
        ForwardRequest calldata req,
        bytes calldata signature
    ) external returns (bool success, bytes memory ret) {
        require(verify(req, signature), "Invalid signature");

        // Get current gas price
        uint256 gasPrice = tx.gasprice;

        // Estimate gas cost in ETH using req.gas (18 decimals)
        uint256 gasCostInEth = gasPrice * req.gas;

        // Get ETH price in USDC (6 decimals)
        uint256 ethPriceInUSDC = getEthPriceInUSDC();

        // Calculate gas cost in USDC (6 decimals)
        uint256 usdcFee = FullMath.mulDiv(gasCostInEth, ethPriceInUSDC, 1e18);
        usdcFee = usdcFee > relayerFee ? usdcFee : relayerFee; // Ensure minimum fee

        // Check balance and allowance
        uint256 balance = feeToken.balanceOf(req.from);
        uint256 allowance = feeToken.allowance(req.from, address(this));
        require(balance >= usdcFee, "Insufficient USDC balance");
        require(allowance >= usdcFee, "Insufficient USDC allowance");

        // Transfer USDC fee to relayer
        require(feeToken.transferFrom(req.from, msg.sender, usdcFee), "Fee transfer failed");

        emit DebugInfo(req.from, msg.sender, usdcFee, balance, allowance, req.gas, gasPrice, ethPriceInUSDC);

        // Increment nonce
        nonces[req.from]++;

        // Execute the relayed transaction
        (success, ret) = req.to.call{gas: req.gas, value: req.value}(req.data);

        emit TransactionRelayed(req.from, req.to, success, ret);

        return (success, ret);
    }

    function setFee(uint256 _newFee) external onlyOwner {
        relayerFee = _newFee;
        emit FeeUpdated(_newFee);
    }

    function setFeeToken(address _newToken) external onlyOwner {
        require(_newToken != address(0), "Invalid fee token address");
        feeToken = IERC20(_newToken);
        emit FeeTokenUpdated(_newToken);
    }

    function setUniswapPool(address _newPool) external onlyOwner {
        require(_newPool != address(0), "Invalid Uniswap pool address");
        uniswapPool = IUniswapV3Pool(_newPool);
        emit UniswapPoolUpdated(_newPool);
    }

    function getNonce(address from) external view returns (uint256) {
        return nonces[from];
    }

    // Allow contract to receive ETH for transaction value
    receive() external payable {}
}