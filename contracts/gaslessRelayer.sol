// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



contract GaslessRelayer is EIP712, Ownable {
    using ECDSA for bytes32;

    IERC20 public feeToken;
    uint256 public relayerFee;
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
    event DebugInfo(
        address from,
        address relayer,
        uint256 fee,
        uint256 balance,
        uint256 allowance
    );

    constructor(address _feeToken, uint256 _initialFee) EIP712("GaslessRelayer", "1") Ownable() {
        feeToken = IERC20(_feeToken);
        relayerFee = _initialFee;
        emit FeeTokenUpdated(_feeToken);
        emit FeeUpdated(_initialFee);
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

        emit DebugInfo(req.from, msg.sender, relayerFee, balance, allowance);

        require(feeToken.transferFrom(req.from, msg.sender, relayerFee), "Fee transfer failed");

        nonces[req.from]++;
        (success, ret) = req.to.call{gas: req.gas, value: req.value}(req.data);

        emit TransactionRelayed(req.from, req.to, success, ret);

        return (success, ret);
    }


    function setFee(uint256 _newFee) external onlyOwner {
        relayerFee = _newFee;
        emit FeeUpdated(_newFee);
    }

    function setFeeToken(address _newToken) external onlyOwner {
        feeToken = IERC20(_newToken);
        emit FeeTokenUpdated(_newToken);
    }

    function getNonce(address from) external view returns (uint256) {
        return nonces[from];
    }

    // Allow contract to receive ETH for transaction value
    receive() external payable {}
}