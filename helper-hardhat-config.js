
const { ethers } = require("hardhat");

const networkConfig = {

    default: {
        name: "hardhat",
    },

    31337: {
        name: "localhost",
    },
    
    5: {
        name: "Goerli",
    },

    11155111: {
        name: "Sepolia"
    }

}

const developmentChains = ["hardhat", "localhost"];
const VERIFICATION_BLOCK_CONFIRMATIONS = 6;

module.exports = {
    networkConfig,
    developmentChains,
    VERIFICATION_BLOCK_CONFIRMATIONS,
};