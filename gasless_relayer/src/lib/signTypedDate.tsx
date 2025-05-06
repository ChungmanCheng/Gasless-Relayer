// lib/signTypedData.ts
import { ethers } from "ethers";

export async function signForwardRequest(
  signer: ethers.providers.JsonRpcSigner,
  domain: any,
  types: any,
  request: any
) {
  return await signer._signTypedData(domain, types, request);
}
