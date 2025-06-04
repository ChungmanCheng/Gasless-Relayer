# Gasless-Relayer  

A simple gasless transaction framework using Solidity and ECDSA signatures. This project lets users sign messages off-chain, and relayers execute them on-chain by paying the gas.  

## 🛠 Features

- Custom `GaslessRelayer` smart contract
- Signature verification
- Nonce tracking for replay protection
- Node.js relayer + signer scripts
- Hardhat setup

## 📦 Deployed Contract  

- **Network**: Sepolia Testnet  
- **GaslessRelayer Contract Address**: [`0x10C0BD984379351cE9196E3a55f68E6297be1d9e`](https://sepolia.etherscan.io/address/0x10C0BD984379351cE9196E3a55f68E6297be1d9e)

## 🚀 Getting Started

### 1. Clone the Project

```bash
git clone https://github.com/ChungmanCheng/Gasless-Relayer.git
cd gasless_relayer
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Start the Frontend

```bash
npm run dev
```
