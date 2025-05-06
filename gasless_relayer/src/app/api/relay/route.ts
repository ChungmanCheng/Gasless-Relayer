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
  "function permit(address owner,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r,bytes32 s)"
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

    // Optional: If permitData is provided, send permit tx
    if (permitData && tokenAddress) {
      const token = new ethers.Contract(tokenAddress, permitAbi, wallet);
      const txPermit = await token.permit(
        permitData.owner,
        permitData.spender,
        permitData.value,
        permitData.deadline,
        permitData.v,
        permitData.r,
        permitData.s
      );
      await txPermit.wait();
      console.log("✅ Permit successful:", txPermit.hash);
    }

    const contract = new ethers.Contract(RELAYER_ADDRESS, relayerAbi, wallet);
    const tx = await contract.execute(request, signature, {
      gasLimit: ethers.utils.hexlify(100000),
    });

    await tx.wait();

    return NextResponse.json({ txHash: tx.hash });
  } catch (err: any) {
    console.error("Relay error:", err);
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
