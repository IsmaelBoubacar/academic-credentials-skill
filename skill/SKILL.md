---
name: academic-credentials
description: Solana skill for issuing, verifying, and managing academic credentials as Soulbound Tokens (SBT). Covers Metaplex-based diploma NFTs, compressed NFTs (ZK-compression), on-chain verification, GDPR/institutional compliance, and EVM-to-Solana migration. Built from UDHCertification — a production system serving 7,000+ students at Université Djibo Hamani de Tahoua, Niger (CONCIT 2025 1st Prize).
user-invocable: true
---

# Academic Credentials Skill

> Production-grade skill for university diploma verification on Solana.  
> Based on [UDHCertification](https://github.com/papyismael/UDHCertification) — deployed for 7,000+ students.

---

## What This Skill Covers

### Credential Issuance
- Mint diploma SBTs via Metaplex Token Metadata
- Compressed NFT (cNFT) batch issuance using ZK-compression
- Non-transferable enforcement at program level
- Metadata schema for diplomas (student ID, degree, institution, date, hash)

### Credential Verification
- On-chain lookup by wallet address or QR code
- Off-chain verification via metadata URI + hash comparison
- Batch verification for institutional audits
- Public verification portal patterns (Next.js + @solana/kit)

### Compliance & Legal
- GDPR-compatible on-chain data minimization
- Off-chain PII storage patterns (IPFS / encrypted S3)
- Institutional recognition strategies (UNESCO, Bologna Process)
- Revocation patterns for SBTs

### EVM → Solana Migration
- Mapping Polygon SBTs to Solana Token Metadata / Token Extensions
- Bridging existing credential records (no re-issuance required)
- Cost comparison and migration tooling

---

## Task Routing

| User asks about… | Read this file |
|------------------|----------------|
| Mint a diploma NFT / SBT | [issuance.md](issuance.md) |
| Compressed NFTs / batch issuance | [issuance.md](issuance.md) |
| Verify a diploma on-chain | [verification.md](verification.md) |
| QR code verification | [verification.md](verification.md) |
| GDPR / data privacy | [compliance.md](compliance.md) |
| Revocation of credentials | [compliance.md](compliance.md) |
| Migrate from Polygon / EVM | [evm-to-solana.md](evm-to-solana.md) |
| Token Extensions vs Token Metadata | [evm-to-solana.md](evm-to-solana.md) |
| Anchor program for credentials | [issuance.md](issuance.md) → Anchor section |

---

## Default Stack Decisions (Opinionated)

### 1) Issuance: Metaplex Token Metadata + Token Extensions
- Use `non_transferable` extension for SBT enforcement (Token Extensions, 2025 standard)
- Use Metaplex Token Metadata for rich metadata (name, URI, attributes)
- Use ZK-Compression (Light Protocol) for batches > 100 diplomas — 1000× cheaper

### 2) Verification: @solana/kit + Next.js 15
- `getAccountInfo` → deserialize Metadata account
- Off-chain metadata: IPFS (Pinata/nft.storage) or Arweave for permanence
- QR code encodes `solana:<mint_address>` or a verification URL

### 3) Compliance
- Store only `sha256(student_PII)` on-chain — never names, IDs, emails
- Keep plaintext in institution's own encrypted database
- Use `updateAuthority` with a multisig (Squads) for revocation

### 4) Programs
- Anchor 0.31+ for the credential registry program
- PDA per diploma: `["credential", institution_pubkey, student_id_hash]`

---

## Operating Procedure

### Step 1 — Classify the task

| Task | Skill file |
|------|------------|
| Single diploma mint | [issuance.md](issuance.md) §Single Issuance |
| Batch (graduation cohort) | [issuance.md](issuance.md) §Compressed NFTs |
| Verify via wallet | [verification.md](verification.md) §Wallet Lookup |
| Verify via QR | [verification.md](verification.md) §QR Code |
| GDPR audit | [compliance.md](compliance.md) §GDPR |
| Revoking a diploma | [compliance.md](compliance.md) §Revocation |
| Moving from Polygon | [evm-to-solana.md](evm-to-solana.md) |

### Step 2 — Apply the data-minimization rule

Before writing any code: **no PII on-chain**.  
Only store: `sha256(studentId + institutionId + graduationDate)` as `external_id` in metadata.

### Step 3 — Choose issuance path

```
Batch < 10   → Token Extensions (non_transferable) + Token Metadata
Batch 10–500 → Metaplex + Bubblegum (cNFT)
Batch 500+   → ZK-Compression (Light Protocol) Merkle tree
```

### Step 4 — Deliver

Provide: program code (Anchor), client script (TypeScript), metadata JSON schema, verification snippet.

---

## Progressive Disclosure

Read files **only when needed** for the current task — do not load all at once.

- **[issuance.md](issuance.md)** — Anchor program, mint scripts, metadata schema, cNFT batch
- **[verification.md](verification.md)** — On-chain lookup, QR codes, portal frontend
- **[compliance.md](compliance.md)** — GDPR, revocation, institutional recognition
- **[evm-to-solana.md](evm-to-solana.md)** — Migration from Polygon, cost analysis, tooling
