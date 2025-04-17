# Gasless-Relayer  

A simple gasless transaction framework using Solidity and ECDSA signatures. This project lets users sign messages off-chain, and relayers execute them on-chain by paying the gas.  

## 🛠 Features

- Custom `GaslessRelayer` smart contract
- Signature verification
- Nonce tracking for replay protection
- Node.js relayer + signer scripts
- Hardhat setup