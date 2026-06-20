# Credential Issuance on Solana

Issuing academic diplomas as Soulbound Tokens (SBT) — non-transferable, permanently linked to a student's wallet.

---

## Metadata Schema

Every diploma NFT must include these fields. **No PII in on-chain fields.**

```json
{
  "name": "Bachelor of Computer Science — UDH 2025",
  "symbol": "UDH-DIPL",
  "description": "Academic credential issued by Université Djibo Hamani de Tahoua",
  "image": "ipfs://Qm.../diploma-template.png",
  "external_url": "https://verify.udh.edu.ne/verify?mint=MINT_ADDRESS",
  "attributes": [
    { "trait_type": "institution",      "value": "Université Djibo Hamani de Tahoua" },
    { "trait_type": "degree",           "value": "Bachelor of Computer Science" },
    { "trait_type": "graduation_year",  "value": "2025" },
    { "trait_type": "credential_type",  "value": "SBT_DIPLOMA" },
    { "trait_type": "external_id",      "value": "sha256(studentId+institutionId+date)" },
    { "trait_type": "issuer_pubkey",    "value": "INSTITUTION_WALLET_PUBKEY" },
    { "trait_type": "schema_version",   "value": "1.0" }
  ],
  "properties": {
    "category": "credential",
    "non_transferable": true
  }
}
```

`external_id` is the only link to the student record — it lives in the institution's private database.

---

## Path 1 — Token Extensions (≤ 10 diplomas, recommended for 2025+)

Token Extensions' `non_transferable` is the canonical SBT standard on Solana as of Token Extensions v2.

### Dependencies

```bash
npm install @solana/web3.js @solana/spl-token @metaplex-foundation/mpl-token-metadata
```

### Mint a Single SBT

```typescript
import {
  Connection, Keypair, PublicKey, SystemProgram,
  Transaction, sendAndConfirmTransaction,
} from "@solana/web3.js";
import {
  ExtensionType,
  TOKEN_2022_PROGRAM_ID,
  createInitializeMintInstruction,
  createInitializeNonTransferableMintInstruction,
  getMintLen,
} from "@solana/spl-token";
import {
  createCreateMetadataAccountV3Instruction,
  PROGRAM_ID as METADATA_PROGRAM_ID,
} from "@metaplex-foundation/mpl-token-metadata";

async function mintDiplomaSBT(
  connection: Connection,
  payer: Keypair,
  studentWallet: PublicKey,
  metadataUri: string,
  diplomaName: string
): Promise<{ mint: PublicKey; signature: string }> {
  const mint = Keypair.generate();
  const extensions = [ExtensionType.NonTransferable];
  const mintLen = getMintLen(extensions);
  const lamports = await connection.getMinimumBalanceForRentExemption(mintLen);

  // 1. Create mint account with NonTransferable extension
  const createAccountIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: mint.publicKey,
    space: mintLen,
    lamports,
    programId: TOKEN_2022_PROGRAM_ID,
  });

  const initNonTransferableIx = createInitializeNonTransferableMintInstruction(
    mint.publicKey,
    TOKEN_2022_PROGRAM_ID
  );

  const initMintIx = createInitializeMintInstruction(
    mint.publicKey,
    0,                      // 0 decimals — NFT
    payer.publicKey,        // mint authority = institution
    null,                   // no freeze authority
    TOKEN_2022_PROGRAM_ID
  );

  // 2. Attach Metaplex metadata (Token Metadata Program)
  const [metadataPDA] = PublicKey.findProgramAddressSync(
    [
      Buffer.from("metadata"),
      METADATA_PROGRAM_ID.toBuffer(),
      mint.publicKey.toBuffer(),
    ],
    METADATA_PROGRAM_ID
  );

  const createMetadataIx = createCreateMetadataAccountV3Instruction(
    {
      metadata: metadataPDA,
      mint: mint.publicKey,
      mintAuthority: payer.publicKey,
      payer: payer.publicKey,
      updateAuthority: payer.publicKey,
    },
    {
      createMetadataAccountArgsV3: {
        data: {
          name: diplomaName,
          symbol: "DIPL",
          uri: metadataUri,
          sellerFeeBasisPoints: 0,
          creators: null,
          collection: null,
          uses: null,
        },
        isMutable: true,          // keep true to allow revocation
        collectionDetails: null,
      },
    }
  );

  const tx = new Transaction().add(
    createAccountIx,
    initNonTransferableIx,
    initMintIx,
    createMetadataIx
  );

  const signature = await sendAndConfirmTransaction(connection, tx, [payer, mint]);
  console.log(`Diploma SBT minted: ${mint.publicKey.toBase58()} | tx: ${signature}`);

  return { mint: mint.publicKey, signature };
}
```

---

## Path 2 — Compressed NFTs / cNFTs (batches 10–10,000)

ZK-Compression via Bubblegum reduces per-diploma cost from ~0.002 SOL to ~0.000005 SOL.

### Dependencies

```bash
npm install @metaplex-foundation/mpl-bubblegum \
            @metaplex-foundation/umi \
            @metaplex-foundation/umi-bundle-defaults \
            @solana/web3.js
```

### Create Merkle Tree

One tree per graduation cohort (e.g., `UDH_2025_ComputerScience`).

```typescript
import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
import {
  createTree,
  mintToCollectionV1,
  mplBubblegum,
} from "@metaplex-foundation/mpl-bubblegum";
import {
  generateSigner,
  keypairIdentity,
  percentAmount,
} from "@metaplex-foundation/umi";

const umi = createUmi("https://api.mainnet-beta.solana.com").use(mplBubblegum());

// Create a Merkle tree (do once per cohort)
async function createCredentialTree(maxDepth = 14, maxBufferSize = 64) {
  // maxDepth 14 = up to 16,384 credentials per tree
  const merkleTree = generateSigner(umi);

  await createTree(umi, {
    merkleTree,
    maxDepth,
    maxBufferSize,
    canopyDepth: 10,   // store top 10 levels on-chain for cheaper proofs
  }).sendAndConfirm(umi);

  console.log("Merkle tree:", merkleTree.publicKey);
  return merkleTree.publicKey;
}
```

### Batch Mint cNFT Diplomas

```typescript
async function batchMintDiplomas(
  merkleTree: string,
  collectionMint: string,
  students: Array<{ wallet: string; metadataUri: string; name: string }>
) {
  const results: string[] = [];

  for (const student of students) {
    const { signature } = await mintToCollectionV1(umi, {
      leafOwner: publicKey(student.wallet),
      merkleTree: publicKey(merkleTree),
      collectionMint: publicKey(collectionMint),
      metadata: {
        name: student.name,
        uri: student.metadataUri,
        sellerFeeBasisPoints: 0,
        collection: { key: publicKey(collectionMint), verified: false },
        creators: [
          {
            address: umi.identity.publicKey,
            verified: true,
            share: 100,
          },
        ],
      },
    }).sendAndConfirm(umi);

    results.push(signature);
    console.log(`Minted: ${student.wallet} | sig: ${signature}`);

    // Rate limit: 1 tx / 400ms on mainnet
    await new Promise((r) => setTimeout(r, 400));
  }

  return results;
}
```

---

## Anchor Program — Credential Registry

A program to track issuance, enforce institutional authority, and support revocation.

### Anchor.toml

```toml
[toolchain]
anchor_version = "0.31.0"

[programs.mainnet]
credential_registry = "CREDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### lib.rs

```rust
use anchor_lang::prelude::*;

declare_id!("CREDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

#[program]
pub mod credential_registry {
    use super::*;

    /// Issue a new credential record on-chain
    pub fn issue_credential(
        ctx: Context<IssueCredential>,
        params: CredentialParams,
    ) -> Result<()> {
        let record = &mut ctx.accounts.credential_record;
        record.institution = ctx.accounts.institution.key();
        record.mint = params.mint;
        record.external_id_hash = params.external_id_hash;  // sha256 only
        record.issued_at = Clock::get()?.unix_timestamp;
        record.revoked = false;
        record.bump = ctx.bumps.credential_record;

        emit!(CredentialIssued {
            institution: record.institution,
            mint: record.mint,
            issued_at: record.issued_at,
        });

        Ok(())
    }

    /// Revoke a credential (institution authority only)
    pub fn revoke_credential(ctx: Context<RevokeCredential>) -> Result<()> {
        require!(!ctx.accounts.credential_record.revoked, CredentialError::AlreadyRevoked);
        ctx.accounts.credential_record.revoked = true;
        ctx.accounts.credential_record.revoked_at = Some(Clock::get()?.unix_timestamp);

        emit!(CredentialRevoked {
            mint: ctx.accounts.credential_record.mint,
            revoked_at: ctx.accounts.credential_record.revoked_at.unwrap(),
        });

        Ok(())
    }
}

// ── Accounts ──────────────────────────────────────────────────────────────────

#[derive(Accounts)]
#[instruction(params: CredentialParams)]
pub struct IssueCredential<'info> {
    #[account(mut)]
    pub institution: Signer<'info>,

    #[account(
        init,
        payer = institution,
        space = CredentialRecord::LEN,
        seeds = [b"credential", institution.key().as_ref(), params.mint.as_ref()],
        bump
    )]
    pub credential_record: Account<'info, CredentialRecord>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RevokeCredential<'info> {
    #[account(mut)]
    pub institution: Signer<'info>,

    #[account(
        mut,
        seeds = [b"credential", institution.key().as_ref(), credential_record.mint.as_ref()],
        bump = credential_record.bump,
        has_one = institution,
    )]
    pub credential_record: Account<'info, CredentialRecord>,
}

// ── State ──────────────────────────────────────────────────────────────────────

#[account]
pub struct CredentialRecord {
    pub institution: Pubkey,         // 32
    pub mint: Pubkey,                // 32
    pub external_id_hash: [u8; 32],  // 32 — sha256(studentId+institutionId+date)
    pub issued_at: i64,              // 8
    pub revoked: bool,               // 1
    pub revoked_at: Option<i64>,     // 9
    pub bump: u8,                    // 1
}

impl CredentialRecord {
    pub const LEN: usize = 8 + 32 + 32 + 32 + 8 + 1 + 9 + 1;
}

// ── Params ──────────────────────────────────────────────────────────────────────

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct CredentialParams {
    pub mint: Pubkey,
    pub external_id_hash: [u8; 32],
}

// ── Events ──────────────────────────────────────────────────────────────────────

#[event]
pub struct CredentialIssued {
    pub institution: Pubkey,
    pub mint: Pubkey,
    pub issued_at: i64,
}

#[event]
pub struct CredentialRevoked {
    pub mint: Pubkey,
    pub revoked_at: i64,
}

// ── Errors ──────────────────────────────────────────────────────────────────────

#[error_code]
pub enum CredentialError {
    #[msg("Credential is already revoked")]
    AlreadyRevoked,
}
```

---

## Metadata Upload (IPFS via Pinata)

```typescript
import PinataSDK from "@pinata/sdk";
import * as crypto from "crypto";

const pinata = new PinataSDK({ pinataJWTKey: process.env.PINATA_JWT! });

interface DiplomaMetadataInput {
  institution: string;
  degree: string;
  graduationYear: string;
  studentId: string;       // used only to compute hash — never stored on IPFS
  issuerPubkey: string;
  diplomaImageCid: string; // pre-uploaded diploma image
}

async function uploadDiplomaMetadata(input: DiplomaMetadataInput): Promise<string> {
  const externalId = crypto
    .createHash("sha256")
    .update(`${input.studentId}:${input.issuerPubkey}:${input.graduationYear}`)
    .digest("hex");

  const metadata = {
    name: `${input.degree} — ${input.institution} ${input.graduationYear}`,
    symbol: "DIPL",
    description: `Academic credential issued by ${input.institution}`,
    image: `ipfs://${input.diplomaImageCid}`,
    attributes: [
      { trait_type: "institution",     value: input.institution },
      { trait_type: "degree",          value: input.degree },
      { trait_type: "graduation_year", value: input.graduationYear },
      { trait_type: "credential_type", value: "SBT_DIPLOMA" },
      { trait_type: "external_id",     value: externalId },
      { trait_type: "issuer_pubkey",   value: input.issuerPubkey },
      { trait_type: "schema_version",  value: "1.0" },
    ],
    properties: { category: "credential", non_transferable: true },
  };

  const result = await pinata.pinJSONToIPFS(metadata, {
    pinataMetadata: { name: `diploma-${externalId.slice(0, 8)}` },
  });

  return `https://ipfs.io/ipfs/${result.IpfsHash}`;
}
```

---

## Cost Reference (Mainnet, June 2025)

| Method | Per diploma | 1,000 diplomas |
|--------|-------------|----------------|
| Token Extensions (non_transferable) | ~0.0025 SOL | ~2.5 SOL |
| Metaplex Token Metadata | ~0.014 SOL | ~14 SOL |
| cNFT / Bubblegum (depth 14) | ~0.000005 SOL | ~0.005 SOL |
| ZK-Compression (Light Protocol) | ~0.000001 SOL | ~0.001 SOL |

**Recommendation**: Use Token Extensions for small cohorts (< 50); cNFTs for graduation batches.
