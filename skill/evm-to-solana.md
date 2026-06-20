# EVM / Polygon → Solana Migration Guide

For institutions running credential systems on Ethereum/Polygon who want to migrate to Solana — lower costs, faster finality, and native SBT support via Token Extensions.

> This guide is based on the UDHCertification migration path: Polygon mainnet → Solana mainnet.

---

## Why Migrate?

| Factor | Polygon | Solana |
|--------|---------|--------|
| Cost per credential | $0.01–$0.10 | $0.0025–$0.000001 (cNFT) |
| Finality | ~2 seconds | ~400ms |
| Native SBT standard | ERC-5484 (limited adoption) | Token Extensions `non_transferable` |
| Wallet ecosystem | MetaMask | Phantom, Backpack, Solflare |
| Batch issuance | ERC-1155 (complex) | cNFT / ZK-Compression (simple) |
| Verification tooling | Limited | Metaplex, @solana/kit |

---

## Concept Mapping: EVM → Solana

| EVM / Solidity Concept | Solana Equivalent |
|------------------------|-------------------|
| `ERC-721` NFT | Metaplex Token Metadata + Token 2022 |
| `ERC-5484` Soulbound Token | Token Extensions `non_transferable` |
| `ERC-1155` batch NFT | Metaplex Bubblegum cNFT |
| Smart contract (Solidity) | On-chain program (Anchor / Rust) |
| `mapping(address => bool)` | PDA (Program Derived Address) |
| `msg.sender` | `ctx.accounts.signer` (Anchor) |
| `require(cond, "msg")` | `require!(cond, ErrorCode::Variant)` |
| `event Transfer` | `emit!(EventStruct { ... })` |
| Contract address | Program ID (`declare_id!`) |
| `bytes32` | `[u8; 32]` |
| `address` | `Pubkey` |
| IPFS metadata | IPFS metadata (same) |
| OpenZeppelin Ownable | `has_one` constraint in Anchor |
| Polygon MATIC gas | SOL transaction fees |
| Hardhat / Foundry | Anchor + LiteSVM / Bankrun |

---

## Step-by-Step Migration

### Step 1 — Audit Existing Polygon State

```typescript
import { ethers } from "ethers";

const POLYGON_RPC = "https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY";
const CONTRACT_ADDRESS = "0xYOUR_CONTRACT";

const ABI = [
  "function totalSupply() view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
];

async function exportPolygonCredentials(): Promise<ExistingCredential[]> {
  const provider = new ethers.JsonRpcProvider(POLYGON_RPC);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);

  const totalSupply = Number(await contract.totalSupply());
  console.log(`Total credentials on Polygon: ${totalSupply}`);

  const credentials: ExistingCredential[] = [];

  for (let tokenId = 1; tokenId <= totalSupply; tokenId++) {
    const owner   = await contract.ownerOf(tokenId);
    const uri     = await contract.tokenURI(tokenId);
    const metadata = await fetch(uri).then((r) => r.json());

    credentials.push({ tokenId, polygonOwner: owner, metadataUri: uri, metadata });
  }

  return credentials;
}

interface ExistingCredential {
  tokenId: number;
  polygonOwner: string;  // ETH address
  metadataUri: string;
  metadata: Record<string, unknown>;
}
```

### Step 2 — Map Ethereum Addresses to Solana Wallets

Students need to register their Solana wallet. Build a simple mapping form:

```typescript
// Database table: address_mapping
// eth_address TEXT PRIMARY KEY
// sol_address TEXT NOT NULL
// verified_at TIMESTAMP
// signature TEXT  -- EIP-191 signature proving eth_address ownership

// Verification endpoint
import { ethers } from "ethers";

async function verifyEthOwnership(
  ethAddress: string,
  solAddress: string,
  signature: string  // EIP-191 signature of message: "Link Solana wallet: {solAddress}"
): Promise<boolean> {
  const message = `Link Solana wallet: ${solAddress}`;
  const recovered = ethers.verifyMessage(message, signature);
  return recovered.toLowerCase() === ethAddress.toLowerCase();
}
```

Students who cannot provide their Ethereum keypair (lost access) go through the institution's manual identity verification process.

### Step 3 — Re-mint on Solana

```typescript
import { Connection, Keypair, PublicKey } from "@solana/web3.js";
import { uploadDiplomaMetadata } from "./issuance";
import { mintDiplomaSBT } from "./issuance";

interface MigrationRecord {
  polygonTokenId: number;
  solAddress: string;
  mintAddress?: string;
  status: "pending" | "minted" | "failed";
}

async function migrateCredentials(
  connection: Connection,
  institutionKeypair: Keypair,
  credentials: ExistingCredential[],
  addressMapping: Map<string, string>  // eth → sol
): Promise<MigrationRecord[]> {
  const records: MigrationRecord[] = [];

  for (const cred of credentials) {
    const solAddress = addressMapping.get(cred.polygonOwner.toLowerCase());

    if (!solAddress) {
      console.warn(`No Solana address for ${cred.polygonOwner} (token ${cred.tokenId}) — skipping`);
      records.push({ polygonTokenId: cred.tokenId, solAddress: "", status: "pending" });
      continue;
    }

    try {
      // Re-upload metadata to IPFS (add migration provenance)
      const enrichedMetadata = {
        ...cred.metadata,
        attributes: [
          ...(cred.metadata.attributes as any[]),
          { trait_type: "migrated_from", value: "polygon" },
          { trait_type: "polygon_token_id", value: String(cred.tokenId) },
          { trait_type: "migration_date",   value: new Date().toISOString().split("T")[0] },
        ],
      };

      const metadataUri = await uploadMigratedMetadata(enrichedMetadata);

      const { mint } = await mintDiplomaSBT(
        connection,
        institutionKeypair,
        new PublicKey(solAddress),
        metadataUri,
        cred.metadata.name as string
      );

      records.push({ polygonTokenId: cred.tokenId, solAddress, mintAddress: mint.toBase58(), status: "minted" });
      console.log(`✅ Token ${cred.tokenId} → Solana ${mint.toBase58()}`);
    } catch (err) {
      console.error(`❌ Failed to migrate token ${cred.tokenId}:`, err);
      records.push({ polygonTokenId: cred.tokenId, solAddress, status: "failed" });
    }

    await new Promise((r) => setTimeout(r, 500));  // rate-limit
  }

  return records;
}
```

### Step 4 — Freeze / Sunset Polygon Contracts

After migration, pause the Polygon contract so no new credentials are issued there:

```solidity
// Add to your Solidity contract
function pause() external onlyOwner {
    _pause();
}

// Override _beforeTokenTransfer and _mint to require !paused()
```

Communicate the sunset date to students and institutional partners **at least 90 days in advance**.

---

## Solana Token Extensions vs. Metaplex Token Metadata

Understanding both standards is essential for migration decisions.

| | Token Extensions (Token 2022) | Metaplex Token Metadata |
|-|-------------------------------|-------------------------|
| Program | Token-2022 program | Metaplex Token Metadata |
| SBT support | Native `non_transferable` | Enforced via update authority lock |
| Metadata storage | On-chain (compact) | Separate Metadata account |
| cNFT support | No | Yes (Bubblegum) |
| Best for | Simple SBTs, small batches | Rich metadata, large collections |
| `isMutable` | N/A | Set to `false` to freeze metadata |
| Royalties | No (credential context) | No (set `sellerFeeBasisPoints: 0`) |

**Recommendation for credentials:**
- Use **Token Extensions** (`non_transferable`) for the token itself (enforces non-transferability at protocol level)
- Use **Metaplex Token Metadata** for the metadata account (rich attributes, URI, name)
- Use **Bubblegum** (cNFT) for large batches only

This is the stack implemented in [issuance.md](issuance.md).

---

## EVM Solidity → Anchor Rust Pattern Map

### Access Control (Ownable)

```solidity
// Solidity
modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
}
```

```rust
// Anchor
#[account(mut, constraint = institution.key() == credential_record.institution @ CredentialError::Unauthorized)]
pub institution: Signer<'info>,
```

### Storage (mapping)

```solidity
// Solidity
mapping(uint256 => address) public tokenOwner;
mapping(address => bool) public isRevoked;
```

```rust
// Anchor — PDA per credential
#[account(
    seeds = [b"credential", institution.key().as_ref(), mint.key().as_ref()],
    bump
)]
pub credential_record: Account<'info, CredentialRecord>,
```

### Events

```solidity
// Solidity
event CredentialIssued(address indexed issuer, uint256 indexed tokenId);
emit CredentialIssued(msg.sender, tokenId);
```

```rust
// Anchor
#[event]
pub struct CredentialIssued {
    pub institution: Pubkey,
    pub mint: Pubkey,
    pub issued_at: i64,
}

emit!(CredentialIssued { institution, mint, issued_at });
```

### Custom Errors

```solidity
// Solidity
error AlreadyRevoked();
revert AlreadyRevoked();
```

```rust
// Anchor
#[error_code]
pub enum CredentialError {
    #[msg("Credential is already revoked")]
    AlreadyRevoked,
}

require!(!record.revoked, CredentialError::AlreadyRevoked);
```

---

## Cost Analysis: Polygon vs. Solana

### Per-Credential Costs (June 2025)

| Network | Method | Cost |
|---------|--------|------|
| Polygon | ERC-721 mint | ~$0.03–$0.10 (MATIC gas) |
| Polygon | ERC-5484 SBT | ~$0.05–$0.15 |
| Solana | Token Extensions SBT | ~$0.002–$0.005 SOL (~$0.20–$0.50 at $100/SOL) |
| Solana | cNFT (Bubblegum) | ~$0.000005 SOL (~$0.0005) |
| Solana | ZK-Compression | ~$0.000001 SOL (~$0.0001) |

### Migration Cost Estimate for UDHCertification (7,000 students)

| Method | Total cost |
|--------|------------|
| Re-mint as Token Extensions SBTs | ~35 SOL (~$3,500) |
| Re-mint as cNFTs (Bubblegum) | ~0.035 SOL (~$3.50) |
| ZK-Compression | ~0.007 SOL (~$0.70) |

**For 7,000 students: use cNFTs.** Cost difference vs. Token Extensions: 1,000×.

---

## Migration Checklist

- [ ] Export all Polygon token IDs, owners, and metadata URIs
- [ ] Build student address mapping UI (ETH → Solana, EIP-191 signature verification)
- [ ] Collect Solana wallet addresses for > 90% of students before migrating
- [ ] Test full migration pipeline on devnet with 100 credentials
- [ ] Deploy Anchor credential registry to mainnet
- [ ] Migrate in batches of 500 with 48h delay between batches
- [ ] Verify each migrated credential via `verifyCredential()` script
- [ ] Pause Polygon contract (no new issuances)
- [ ] Communicate new Solana verification URL to all institutional partners
- [ ] Update employer verification portal to query Solana
- [ ] Set Polygon sunset date (recommend: 12 months post-migration)
- [ ] Archive Polygon contract address and block numbers for historical reference
