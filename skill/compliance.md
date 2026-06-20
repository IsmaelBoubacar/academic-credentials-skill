# Compliance, Privacy & Institutional Recognition

Legal and regulatory considerations for academic credentials on Solana.

---

## Core Principle: Data Minimization

**Never store PII on-chain or on IPFS.**  
On-chain fields must contain only:

| Field | Stored | Example |
|-------|--------|---------|
| Student name | ❌ No | — |
| Student ID number | ❌ No | — |
| Date of birth | ❌ No | — |
| Email address | ❌ No | — |
| `external_id` (hash) | ✅ Yes | `sha256("UDH-2025-00342:issuerPubkey:2025")` |
| Institution name | ✅ Yes | `"Université Djibo Hamani de Tahoua"` |
| Degree name | ✅ Yes | `"Bachelor of Computer Science"` |
| Graduation year | ✅ Yes | `"2025"` |
| Credential type | ✅ Yes | `"SBT_DIPLOMA"` |

The `external_id` is a one-way SHA-256 hash. It links the NFT to a student record in the institution's private database without exposing any identifying information.

---

## GDPR Compliance

### Applicable Entities

GDPR applies if any student is an EU resident or if the institution operates within the EU. African universities with EU partnerships (Erasmus+, etc.) should implement GDPR-equivalent practices regardless.

### Technical Measures

```typescript
// ✅ Correct: hash before storing
import * as crypto from "crypto";

function computeExternalId(
  studentId: string,
  institutionId: string,
  graduationYear: string
): string {
  return crypto
    .createHash("sha256")
    .update(`${studentId}:${institutionId}:${graduationYear}`)
    .digest("hex");
}

// ❌ Wrong: storing identifiable data
const metadata = {
  attributes: [
    { trait_type: "student_name", value: "Aminata Diallo" },   // ← NEVER
    { trait_type: "student_id",   value: "UDH-2025-00342" },   // ← NEVER
  ]
};
```

### Right to Erasure (Article 17 GDPR)

Blockchain records are immutable — but they can be made meaningless via revocation.

**Strategy:**
1. Revoke the credential (set `revoked = true` in the CredentialRecord PDA).
2. Delete the off-chain metadata from IPFS (unpin from Pinata/nft.storage).
3. Delete the student record from the institution's database.
4. The on-chain NFT becomes an empty, revoked shell — no PII survives.

```typescript
async function gdprErasureRequest(
  mintAddress: string,
  institutionKeypair: Keypair,
  pinataCid: string
) {
  const connection = new Connection(RPC, "confirmed");

  // 1. Revoke on-chain
  await revokeCredential(connection, institutionKeypair, mintAddress);

  // 2. Unpin from IPFS
  const pinata = new PinataSDK({ pinataJWTKey: process.env.PINATA_JWT! });
  await pinata.unpin(pinataCid);

  // 3. Log erasure event for audit trail (GDPR Art. 5(2) accountability)
  console.log(JSON.stringify({
    event: "gdpr_erasure",
    mint: mintAddress,
    timestamp: new Date().toISOString(),
    requestedBy: "data_subject",
  }));

  // 4. Delete from institution DB (application layer — not shown here)
}
```

### Data Processing Agreement

Institutions must sign a Data Processing Agreement (DPA) with:
- Pinata / nft.storage (IPFS metadata storage)
- Their RPC provider (Helius, QuickNode, etc.)

Standard GDPR DPAs are available from Pinata and nft.storage.

---

## Credential Revocation

### When to Revoke

- Academic fraud discovered post-graduation
- Administrative error in the original credential
- GDPR erasure request
- Student withdraws consent (where applicable)

### Revocation via Anchor Program

```typescript
import { Program, AnchorProvider, web3 } from "@coral-xyz/anchor";
import { Connection, Keypair, PublicKey } from "@solana/web3.js";

const REGISTRY_PROGRAM_ID = new PublicKey("CREDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

async function revokeCredential(
  connection: Connection,
  institutionKeypair: Keypair,
  mintAddress: string
) {
  const mint = new PublicKey(mintAddress);
  const provider = new AnchorProvider(
    connection,
    { publicKey: institutionKeypair.publicKey, signTransaction: async (tx) => { tx.partialSign(institutionKeypair); return tx; }, signAllTransactions: async (txs) => txs.map(tx => { tx.partialSign(institutionKeypair); return tx; }) },
    { commitment: "confirmed" }
  );
  const program = new Program(IDL, REGISTRY_PROGRAM_ID, provider);

  const [credentialPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("credential"), institutionKeypair.publicKey.toBuffer(), mint.toBuffer()],
    REGISTRY_PROGRAM_ID
  );

  const tx = await program.methods
    .revokeCredential()
    .accounts({
      institution: institutionKeypair.publicKey,
      credentialRecord: credentialPDA,
    })
    .rpc();

  console.log(`Credential revoked. tx: ${tx}`);
  return tx;
}
```

### Revocation Registry (Alternative: Simple Account)

For institutions that don't run the full Anchor program, a lightweight revocation list:

```typescript
// Store a list of revoked mint addresses in a PDA
// PDA: ["revocation_list", institutionPubkey]
// Data: BTreeSet<Pubkey> (sorted for efficient lookup)
```

---

## Institutional Multisig (Squads)

Credential issuance and revocation should require multi-party authorization — e.g., the Registrar + Dean of Studies.

```typescript
// Use Squads v4 for institutional multisig
// npm install @sqds/multisig

import * as multisig from "@sqds/multisig";

async function createInstitutionMultisig(
  connection: Connection,
  creator: Keypair,
  members: PublicKey[],
  threshold: number  // e.g., 2 out of 3
) {
  const createKey = Keypair.generate();

  const [multisigPda] = multisig.getMultisigPda({ createKey: createKey.publicKey });

  const { blockhash } = await connection.getLatestBlockhash();

  const tx = multisig.transactions.multisigCreateV2({
    blockhash,
    createKey: createKey.publicKey,
    creator: creator.publicKey,
    multisigPda,
    configAuthority: null,
    timeLock: 0,
    members: members.map((m) => ({ key: m, permissions: multisig.types.Permissions.all() })),
    threshold,
    rentCollector: null,
  });

  tx.sign([creator, createKey]);
  const sig = await connection.sendRawTransaction(tx.serialize());
  console.log(`Institution multisig created: ${multisigPda.toBase58()}`);
  return multisigPda;
}
```

---

## UNESCO / Bologna Process Alignment

Academic credentials issued on Solana can align with international recognition frameworks:

### European Qualifications Framework (EQF)

Add an `eqf_level` attribute to metadata:

```json
{ "trait_type": "eqf_level", "value": "6" }
```

EQF levels: 1 (basic) → 8 (doctorate). Bachelor = 6, Master = 7, PhD = 8.

### Lisbon Recognition Convention (LRC)

The Lisbon Convention requires that institutions have a procedure for recognition of foreign qualifications. On-chain credentials support this by providing:
- A permanent, tamper-proof record
- A public verification URL
- An institution-signed issuer_pubkey

### UNESCO LEARN Framework

UNESCO's Learning Passport and blockchain credentials initiatives recommend:
- Open, interoperable credential formats
- Student-controlled credential wallets
- Privacy-preserving verification

Solana SBTs satisfy all three criteria.

### Recommended Metadata Additions for International Recognition

```json
{
  "attributes": [
    { "trait_type": "eqf_level",       "value": "6" },
    { "trait_type": "isced_level",     "value": "6" },
    { "trait_type": "language",        "value": "fr" },
    { "trait_type": "country",         "value": "NE" },
    { "trait_type": "accreditation",   "value": "MESRS-Niger-2024-001" },
    { "trait_type": "verification_url","value": "https://verify.udh.edu.ne" }
  ]
}
```

---

## Security Checklist for Production Deployment

- [ ] Institution keypair stored in HSM or hardware wallet (Ledger) — never in plaintext
- [ ] Update authority is a multisig (Squads), not a single keypair
- [ ] Metadata URIs use IPFS content-addressable hashes (not mutable HTTP URLs)
- [ ] PINATA_JWT and all secrets in environment variables, never in source code
- [ ] RPC endpoint is a paid private node (Helius/QuickNode) — not public mainnet
- [ ] Rate limiting on the verification portal (max 100 req/min per IP)
- [ ] Revocation checks cached for max 60 seconds to avoid RPC hammering
- [ ] Audit log of all issuance and revocation events (immutable, separate from app DB)
- [ ] GDPR erasure procedure documented and tested
- [ ] DPA signed with all data processors (Pinata, RPC provider)
