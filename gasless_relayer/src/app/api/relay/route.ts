// src/app/api/relay/route.ts
import { NextRequest, NextResponse } from "next/server";
import { ethers } from "ethers";

const RELAYER_PRIVATE_KEY = process.env.NEXT_PUBLIC_RELAYER_PRIVATE_KEY!;
const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL!;
const RELAYER_ADDRESS = process.env.NEXT_PUBLIC_RELAYER_ADDRESS!;
const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID);

const relayerAbi = [
  "function execute((address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data), bytes signature) external payable returns (bool success)",
];

const permitAbi = [
  "function permit(address owner,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r,bytes32 s)",

  // Standard ERC20
  "function balanceOf(address owner) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 value) returns (bool)",
  "function transfer(address to, uint256 value) returns (bool)",
  "function transferFrom(address from, address to, uint256 value) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function name() view returns (string)"
];

export async function POST(req: NextRequest) {
  try {
    const {
      request,
      signature,
      tokenAddress,
      permitData, // { owner, spender, value, deadline, v, r, s }
    } = await req.json();

    const provider = new ethers.providers.WebSocketProvider(RPC_URL);
    const wallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);

    const iface = new ethers.utils.Interface([
      "function transferFrom(address from, address to, uint256 amount)"
    ]);
    const decoded = iface.decodeFunctionData("transferFrom", request.data);
    const [from, to, amount] = decoded;

    console.log("Decoded transferFrom details:");
    console.log(`- From: ${from}`);
    console.log(`- To: ${to}`);
    console.log(`- Amount: ${ethers.utils.formatUnits(amount, 6)}`);

    // Optional: If permitData is provided, send permit tx
    if (permitData && tokenAddress) {
      
      const token = new ethers.Contract(tokenAddress, permitAbi, wallet);
      const allowanceBefore = await token.allowance(permitData.owner, permitData.spender);
      console.log("Allowance before permit:", ethers.utils.formatUnits(allowanceBefore, 6));

      const txPermit = await token.permit(
        permitData.owner,
        permitData.spender,
        permitData.value,
        permitData.deadline,
        permitData.v,
        permitData.r,
        permitData.s
      );
      const balance = await token.balanceOf(permitData.owner,);
      console.log("User balance:", ethers.utils.formatUnits(balance, 6));
      await txPermit.wait();
      console.log("✅ Permit successful:", txPermit.hash);

      // Check allowance before sending permit transaction
      const updatedAllowance = await token.allowance(permitData.owner, permitData.spender);
      const updatedFormattedAllowance = ethers.utils.formatUnits(updatedAllowance, 6); // Assuming 6 decimals
      console.log("Updated Allowance after permit:", updatedFormattedAllowance);

    }

    const contract = new ethers.Contract(RELAYER_ADDRESS, relayerAbi, wallet);
    const tx = await contract.execute(request, signature, {
      gasLimit: ethers.utils.hexlify(1000000),
    })

    await tx.wait();

    return NextResponse.json({ txHash: tx.hash });
  } catch (err: any) {
    console.error("Relay error:", err);
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
