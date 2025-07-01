import { readFileSync } from "fs";
import { ethers } from "ethers";
import * as dotenv from "dotenv";
import { exec } from "child_process";
import { promisify } from "util";

dotenv.config()
if (!process.env.RPC_URL || 
    !process.env.PRIVATE_KEY || 
    !process.env.FEE_RECIPIENT || 
    !process.env.OWNER ||
    !process.env.ETHERSCAN_API_KEY
) {
    console.error(".env error");
    process.exit(1);
}
// setting provider and signer
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

console.log("sender address: ", wallet.address);

async function deploy_contract(name, ...args) {
    console.log(`start deploy ${name} ...`);
    const artifact = JSON.parse(readFileSync(`./out/${name}.sol/${name}.json`, "utf8"));
    const factory = new ethers.ContractFactory(
        artifact.abi,
        artifact.bytecode.object,
        wallet
    );

    const contract = await factory.deploy(...args);
    const tx = contract.deploymentTransaction();
    console.log("hash", tx.hash)
    const res = await tx?.wait();
    console.log(`✅ ${name} deploy success:`, res.contractAddress);
    return res.contractAddress
}

async function deploy_proxy_contract(name, logic_address, ...args) {
    console.log(`start deploy ${name} Proxy ...`);
    const logic_artifact = JSON.parse(readFileSync(`./out/${name}.sol/${name}.json`, "utf8"));
    const iface = new ethers.Interface(logic_artifact.abi);
    const initData = iface.encodeFunctionData("initialize", args);
    const artifact = JSON.parse(readFileSync("./out/ERC1967Proxy.sol/ERC1967Proxy.json", "utf8"));
    const factory = new ethers.ContractFactory(
        artifact.abi,
        artifact.bytecode.object,
        wallet
    );
    const contract = await factory.deploy(logic_address, initData);
    const tx = contract.deploymentTransaction();
    console.log("hash", tx.hash)
    const res = await tx?.wait();
    console.log(`✅ ${name} Proxy deploy success`, res.contractAddress);
    return res.contractAddress
}

async function preCalcAddr() {
    const nonce = await provider.getTransactionCount(wallet.address);
    return ethers.getCreateAddress({
        from: wallet.address,
        nonce: nonce + 3
    });
}

async function verifyContract(name, address, consArgs, chainId) {
    const execPromise = promisify(exec);
    console.log("start verify ", name, " ......");
    var shell = "forge verify-contract --chain-id " + chainId + " --num-of-optimizations 200 --watch ";
    shell += consArgs;
    shell += " --etherscan-api-key " + process.env.ETHERSCAN_API_KEY;
    shell += " --compiler-version v0.8.28+commit.7893614 ";
    shell += address + " " + name;

    try {
        const { stdout, stderr } = await execPromise(shell);
        if (stderr) {
          console.error(`stderr: ${stderr}`);
        }
        console.log("✅ " + name + " verify successful");
        return stdout;
    } catch (error) {
        console.error(`execute error: ${error.message}`);
        throw error;
    }
}

async function getChainId() {
    try {
      const network = await provider.getNetwork();
      console.log("Chain ID:", network.chainId);
      return network.chainId;
    } catch (error) {
      console.error("Error fetching chainId:", error.message);
      throw error;
    }
}

async function main() {
    const factory_addr = await deploy_contract("Factory"); 
    const nft_manager_pre_addr = await preCalcAddr();
    console.log("PreCalc NFTManager Proxy:", nft_manager_pre_addr)
    const azoth_addr = await deploy_contract("Azoth", factory_addr, nft_manager_pre_addr); 
    const azoth_proxy_addr = await deploy_proxy_contract("Azoth", azoth_addr, process.env.OWNER, process.env.FEE_RECIPIENT);
    const nftmanager_addr = await deploy_contract("NFTManager", azoth_proxy_addr);
    const nftmanager_proxy_addr = await deploy_proxy_contract("NFTManager", nftmanager_addr);
    console.log("============================ Deploy Contract ============================");
    console.log("Sender: ", wallet.address);
    console.log("Owner: ", process.env.OWNER);
    console.log("Fee Recipient: ", process.env.FEE_RECIPIENT);
    console.log("Azoth deployed at:", azoth_proxy_addr);
    console.log("Factory deployed at:", factory_addr);
    console.log("NFTManager deployed at:", nftmanager_proxy_addr);

    const chainId = await getChainId();

    console.log("============================= Verify Contract =============================");
    await verifyContract("Factory", factory_addr, "", chainId);

    const azothImpleConsArgs = '--constructor-args $(cast abi-encode "constructor(address,address)" ' + factory_addr + ' ' + nftmanager_proxy_addr + ')';
    await verifyContract("Azoth", azoth_addr, azothImpleConsArgs, chainId);

    const subArgs = '$(cast calldata "initialize(address,address)" ' + process.env.OWNER + ' ' + process.env.FEE_RECIPIENT + ')';
    const azothProxyConsArgs = '--constructor-args $(cast abi-encode "constructor(address,bytes)" ' + azoth_addr + ' ' + subArgs + ')';
    await verifyContract("ERC1967Proxy", azoth_proxy_addr, azothProxyConsArgs, chainId);

    const nftmanagerImpleConsArgs = '--constructor-args $(cast abi-encode "constructor(address)" ' + azoth_proxy_addr + ')';
    await verifyContract("NFTManager", nftmanager_addr, nftmanagerImpleConsArgs, chainId);

    const nftManagerProxyConsArgs = '--constructor-args $(cast abi-encode "constructor(address,bytes)" ' + nftmanager_addr + ' 0x8129fc1c)';
    await verifyContract("ERC1967Proxy", nftmanager_proxy_addr, nftManagerProxyConsArgs, chainId);
}

main()