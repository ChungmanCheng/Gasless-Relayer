require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ganache");
require("solidity-coverage");
require("hardhat-deploy");

require("dotenv").config();

const ETHEREUM_RPC_URL = process.env.ETHEREUM_RPC_URL;
const Sepolia_RPC_URL = process.env.Sepolia_RPC_URL;
const POLYGON_RPC_URL = process.env.POLYGON_RPC_URL;
const Optimism_RPC_URL = process.env.Optimism_RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY;
  

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            chainId: 31337,
        },
        sepolia: {
            chainId: 11155111,
            url: Sepolia_RPC_URL,
            accounts: [PRIVATE_KEY],
        },
        polygon: {
            chainId: 137,
            url: POLYGON_RPC_URL,
            accounts: [PRIVATE_KEY],
        },
        ethereum: {
            chainId: 1,
            url: ETHEREUM_RPC_URL,
            accounts: [PRIVATE_KEY],
        },
        optimism: {
            chainId: 10,
            url: Optimism_RPC_URL,
            accounts: [PRIVATE_KEY],
        }
    },
    namedAccounts: {
        deployer: {
            default: 0,
        }
    },
    solidity: {
        compilers: [
            {
                version: "0.8.20", // Compatible with Uniswap V3
            },
        ],
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY,
    },
    gasReporter: {
        enabled: true,
        outputFile: "gas-report.txt",
        noColors: true,
        currency: "USD",
        coinmarketcap: COINMARKETCAP_API_KEY,
    },
    mocha: {
        timeout: 500000,
    },
};