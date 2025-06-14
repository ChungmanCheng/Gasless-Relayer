
const { network, ethers } = require("hardhat");
const {
    networkConfig,
    developmentChains,
    VERIFICATION_BLOCK_CONFIRMATIONS,
} = require("../helper-hardhat-config");
const { verify } = require("../utils/verify");

module.exports = async function({ getNamedAccounts, deployments }){

    const { deploy, log } = deployments;
    const { deployer } = await getNamedAccounts();
    const chainId = network.config.chainId;

    let contract;

    contract = await deploy("GaslessRelayer", {
        from: deployer,
        args: ["0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", "100000", "0x694AA1769357215DE4FAC081bf1f309aDC325306"],
        log: true,
        waitConfirmations: network.config.blockConfirmations || 1,
    });

    console.log("----------------------------------------------------");

    console.log("GaslessRelayer deployed to:", contract.address);

    console.log("----------------------------------------------------");

    await verify( contract.address, ["0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", "100000", "0x694AA1769357215DE4FAC081bf1f309aDC325306"] );

}

module.exports.tags = ["all", "GaslessRelayer"];