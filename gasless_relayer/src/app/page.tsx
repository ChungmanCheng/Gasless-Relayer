"use client";

import { useState } from "react";
import { ethers, utils } from "ethers";
import { signForwardRequest } from "@/lib/signTypedDate";

const RELAYER_ADDRESS = process.env.NEXT_PUBLIC_RELAYER_ADDRESS!;  // Update for environment variables
const USDC_ADDRESS = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";
const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID); // Sepolia

declare global {
  interface Window {
    ethereum?: import("ethers").providers.ExternalProvider;
  }
}

const domain = {
  name: "GaslessRelayer",
  version: "1",
  chainId: CHAIN_ID,
  verifyingContract: RELAYER_ADDRESS,
};

const types = {
  ForwardRequest: [
    { name: "from", type: "address" },
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "gas", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "data", type: "bytes" },
  ],
};

const permitTypes = {
  Permit: [
    { name: "owner", type: "address" },
    { name: "spender", type: "address" },
    { name: "value", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};


export default function Home() {
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("");
  const [status, setStatus] = useState("");

  const handleSend = async () => {
    try {
      setStatus("Connecting wallet...");
      let provider, signer, address;
      if (window.ethereum) {
        await window.ethereum.request({ method: "eth_requestAccounts" });
        provider = new ethers.providers.Web3Provider(window.ethereum);
        signer = provider.getSigner();
        address = await signer.getAddress();
      } else {
        throw new Error("Ethereum provider not found.");
      }
  
      // Prepare relayer and USDC contracts
      const relayer = new ethers.Contract(
        RELAYER_ADDRESS,
        ["function getNonce(address) view returns (uint256)"],
        provider
      );
  
      const usdc = new ethers.Contract(
        USDC_ADDRESS,
        [
          "function nonces(address owner) view returns (uint256)",
          "function name() view returns (string)"
        ],
        provider
      );
  
      const [nonce, usdcName] = await Promise.all([
        relayer.getNonce(address),
        usdc.name()
      ]);
  
      // Create ForwardRequest
      const iface = new utils.Interface([
        "function transferFrom(address from, address to, uint256 amount)"
      ]);
      const amountInUnits = utils.parseUnits(amount, 6);
      const relayerFee = utils.parseUnits("0.1", 6);      // Fee for relayer
      const totalAmount = amountInUnits.add(relayerFee);
      const data = iface.encodeFunctionData("transferFrom", [address, recipient, amountInUnits]);
  
      const request = {
        from: address,
        to: USDC_ADDRESS,
        value: 0,
        gas: 1000000,
        nonce,
        data
      };
  
      // Generate permitData
      const usdcNonce = await usdc.nonces(address);
      const deadline = Math.floor(Date.now() / 1000) + 3600;
  
      const permitDomain = {
        name: usdcName,
        version: "2", // Most permit tokens use version "1"
        chainId: CHAIN_ID,
        verifyingContract: USDC_ADDRESS
      };
  
      const permitValue = {
        owner: address,
        spender: RELAYER_ADDRESS,
        value: totalAmount,
        nonce: usdcNonce,
        deadline
      };
  
      setStatus("Signing permit...");
      const permitSig = await signer._signTypedData(permitDomain, permitTypes, permitValue);
      const { v, r, s } = ethers.utils.splitSignature(permitSig);
  
      const permitData = {
        owner: address,
        spender: RELAYER_ADDRESS,
        value: totalAmount.toString(),
        deadline,
        v,
        r,
        s
      };
  
      setStatus("Signing transaction...");
      const signature = await signForwardRequest(signer, domain, types, request);
  
      setStatus("Sending to relayer...");
      const res = await fetch("/api/relay", {
        method: "POST",
        body: JSON.stringify({
          request,
          signature,
          tokenAddress: USDC_ADDRESS,
          permitData
        }),
        headers: {
          "Content-Type": "application/json"
        }
      });
  
      const result = await res.json();
      if (res.ok) {
        setStatus(`✅ Relayed! Tx Hash: ${result.txHash}`);
      } else {
        throw new Error(result.error || "Relay failed");
      }
    } catch (err: any) {
      setStatus(`❌ ${err.message}`);
    }
  };
  

  return (
    <div className="min-h-screen p-12 flex flex-col gap-6 items-center">
      <h1 className="text-2xl font-bold">Gasless USDC Transfer</h1>
      <input
        type="text"
        placeholder="Recipient address"
        value={recipient}
        onChange={(e) => setRecipient(e.target.value)}
        className="p-2 border rounded w-full max-w-md"
      />
      <input
        type="text"
        placeholder="Amount (USDC)"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        className="p-2 border rounded w-full max-w-md"
      />
      <button
        onClick={handleSend}
        className="bg-black text-white px-6 py-2 rounded"
      >
        Send Gasless
      </button>
      <div className="mt-4 text-sm">{status}</div>
    </div>
  );
}
