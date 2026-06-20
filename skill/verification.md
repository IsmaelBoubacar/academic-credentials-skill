# Credential Verification on Solana

How to verify academic diplomas on-chain — by wallet address, mint address, or QR code.

---

## Verification Flow Overview

```
Student presents QR code / wallet address
        │
        ▼
   Extract mint address
        │
        ▼
   Fetch Token Metadata account (Metaplex)
        │
        ├─ Not found → NOT VALID
        │
        ▼
   Check non_transferable extension (Token Extensions) or metadata attributes
        │
        ▼
   Fetch CredentialRecord PDA (Anchor program)
        │
        ├─ record.revoked = true → REVOKED
        │
        ▼
   Fetch off-chain metadata URI → validate JSON schema
        │
        ▼
   Optional: hash-match external_id against institution DB
        │
        ▼
   ✅ VALID credential
```

---

## Path 1 — Verify by Mint Address (programmatic)

```typescript
import { Connection, PublicKey } from "@solana/web3.js";
import { Metaplex } from "@metaplex-foundation/js";
import { Program, AnchorProvider } from "@coral-xyz/anchor";

const RPC = "https://api.mainnet-beta.solana.com"; // use a private RPC in production

interface VerificationResult {
  valid: boolean;
  revoked: boolean;
  institution: string;
  degree: string;
  graduationYear: string;
  externalId: string;
  issuedAt: Date | null;
  error?: string;
}

async function verifyCredential(mintAddress: string): Promise<VerificationResult> {
  const connection = new Connection(RPC, "confirmed");
  const mint = new PublicKey(mintAddress);

  // 1. Fetch Metaplex metadata
  const metaplex = Metaplex.make(connection);
  let nft;
  try {
    nft = await metaplex.nfts().findByMint({ mintAddress: mint });
  } catch {
    return { valid: false, revoked: false, institution: "", degree: "", graduationYear: "", externalId: "", issuedAt: null, error: "Mint not found" };
  }

  // 2. Check credential_type attribute
  const attrs = nft.json?.attributes ?? [];
  const credType = attrs.find((a: any) => a.trait_type === "credential_type")?.value;
  if (credType !== "SBT_DIPLOMA") {
    return { valid: false, revoked: false, institution: "", degree: "", graduationYear: "", externalId: "", issuedAt: null, error: "Not a credential NFT" };
  }

  const institution = attrs.find((a: any) => a.trait_type === "institution")?.value ?? "";
  const degree      = attrs.find((a: any) => a.trait_type === "degree")?.value ?? "";
  const gradYear    = attrs.find((a: any) => a.trait_type === "graduation_year")?.value ?? "";
  const externalId  = attrs.find((a: any) => a.trait_type === "external_id")?.value ?? "";
  const issuerPubkeyStr = attrs.find((a: any) => a.trait_type === "issuer_pubkey")?.value;

  if (!issuerPubkeyStr) {
    return { valid: false, revoked: false, institution, degree, graduationYear: gradYear, externalId, issuedAt: null, error: "Missing issuer_pubkey" };
  }

  const issuerPubkey = new PublicKey(issuerPubkeyStr);

  // 3. Check CredentialRecord PDA (revocation status)
  const REGISTRY_PROGRAM_ID = new PublicKey("CREDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
  const [credentialPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("credential"), issuerPubkey.toBuffer(), mint.toBuffer()],
    REGISTRY_PROGRAM_ID
  );

  let revoked = false;
  let issuedAt: Date | null = null;

  const pdaInfo = await connection.getAccountInfo(credentialPDA);
  if (pdaInfo) {
    // Deserialize CredentialRecord manually (skip 8-byte discriminator)
    const data = pdaInfo.data;
    revoked = data[104] === 1;  // offset: 8+32+32+32 = 104
    const issuedAtTs = Number(data.readBigInt64LE(96));
    issuedAt = new Date(issuedAtTs * 1000);
  }

  return {
    valid: !revoked,
    revoked,
    institution,
    degree,
    graduationYear: gradYear,
    externalId,
    issuedAt,
  };
}
```

---

## Path 2 — Verify by Student Wallet Address

Returns all credentials owned by a wallet.

```typescript
import { Connection, PublicKey } from "@solana/web3.js";
import { Metaplex } from "@metaplex-foundation/js";

async function getCredentialsByWallet(
  walletAddress: string
): Promise<Array<{ mint: string; name: string; valid: boolean }>> {
  const connection = new Connection(RPC, "confirmed");
  const owner = new PublicKey(walletAddress);
  const metaplex = Metaplex.make(connection);

  // Fetch all NFTs owned by this wallet
  const nfts = await metaplex.nfts().findAllByOwner({ owner });

  const credentials = nfts.filter(
    (nft) =>
      nft.json?.attributes?.some(
        (a: any) => a.trait_type === "credential_type" && a.value === "SBT_DIPLOMA"
      )
  );

  return Promise.all(
    credentials.map(async (nft) => {
      const result = await verifyCredential(nft.address.toBase58());
      return {
        mint: nft.address.toBase58(),
        name: nft.name,
        valid: result.valid,
      };
    })
  );
}
```

---

## Path 3 — QR Code Verification

### QR Code Encoding

The QR code encodes a URL (preferred) or a bare mint address:

```typescript
// Option A: URL (user-friendly)
const qrContent = `https://verify.udh.edu.ne/verify?mint=${mintAddress}`;

// Option B: Bare mint address (scanner reads and looks up)
const qrContent = mintAddress;
```

Generate with `qrcode` npm package:

```typescript
import QRCode from "qrcode";

async function generateDiplomaQR(mintAddress: string, outputPath: string) {
  await QRCode.toFile(outputPath, `https://verify.udh.edu.ne/verify?mint=${mintAddress}`, {
    width: 400,
    margin: 2,
    color: { dark: "#000000", light: "#ffffff" },
    errorCorrectionLevel: "H",  // High — survives partial damage on printed diplomas
  });
}
```

### Verification Portal (Next.js 15)

`app/verify/page.tsx`:

```typescript
"use client";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

export default function VerifyPage() {
  const params = useSearchParams();
  const mint = params.get("mint");
  const [result, setResult] = useState<VerificationResult | null>(null);

  useEffect(() => {
    if (!mint) return;
    verifyCredential(mint).then(setResult);
  }, [mint]);

  if (!mint) return <p>No mint address provided.</p>;
  if (!result) return <p>Verifying…</p>;

  return (
    <div>
      <h1>{result.valid ? "✅ Valid Credential" : "❌ Invalid / Revoked"}</h1>
      {result.valid && (
        <dl>
          <dt>Institution</dt> <dd>{result.institution}</dd>
          <dt>Degree</dt>      <dd>{result.degree}</dd>
          <dt>Year</dt>        <dd>{result.graduationYear}</dd>
          <dt>Issued</dt>      <dd>{result.issuedAt?.toLocaleDateString()}</dd>
        </dl>
      )}
      {result.revoked && <p>This credential has been revoked by the issuing institution.</p>}
    </div>
  );
}
```

---

## Batch Verification (Institutional Audit)

For employers or partner universities verifying a list of graduates:

```typescript
import * as XLSX from "xlsx";

interface AuditRow {
  name: string;     // from employer's list
  mintAddress: string;
  status: string;
  degree: string;
  institution: string;
  year: string;
  issuedAt: string;
}

async function batchVerifyFromCSV(csvPath: string, outputPath: string) {
  const wb = XLSX.readFile(csvPath);
  const rows: Array<{ name: string; mint: string }> =
    XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]]);

  const results: AuditRow[] = [];

  for (const row of rows) {
    const v = await verifyCredential(row.mint);
    results.push({
      name: row.name,
      mintAddress: row.mint,
      status: v.revoked ? "REVOKED" : v.valid ? "VALID" : "NOT FOUND",
      degree: v.degree,
      institution: v.institution,
      year: v.graduationYear,
      issuedAt: v.issuedAt?.toISOString().split("T")[0] ?? "",
    });
    await new Promise((r) => setTimeout(r, 200)); // rate-limit
  }

  const ws = XLSX.utils.json_to_sheet(results);
  const out = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(out, ws, "Verification");
  XLSX.writeFile(out, outputPath);

  const valid   = results.filter((r) => r.status === "VALID").length;
  const revoked = results.filter((r) => r.status === "REVOKED").length;
  const invalid = results.filter((r) => r.status === "NOT FOUND").length;

  console.log(`Audit complete: ${valid} valid, ${revoked} revoked, ${invalid} not found`);
}
```

---

## Verification Error Reference

| Error | Cause | Action |
|-------|-------|--------|
| `Mint not found` | Address doesn't exist on-chain | Check address; may be wrong network |
| `Not a credential NFT` | NFT exists but lacks `credential_type: SBT_DIPLOMA` | Not issued by this system |
| `Missing issuer_pubkey` | Metadata malformed | Contact issuing institution |
| `REVOKED` | Institution revoked this diploma | Contact institution |
| `PDA not found` | Credential not registered in registry | May be legacy / pre-registry |

---

## Off-Chain Hash Verification (optional, highest assurance)

For institutions that want to tie the on-chain credential to their private database:

```typescript
import * as crypto from "crypto";

function verifyExternalId(
  studentId: string,
  institutionPubkey: string,
  graduationYear: string,
  onChainExternalId: string  // the external_id attribute from metadata
): boolean {
  const expected = crypto
    .createHash("sha256")
    .update(`${studentId}:${institutionPubkey}:${graduationYear}`)
    .digest("hex");

  return crypto.timingSafeEqual(
    Buffer.from(expected, "hex"),
    Buffer.from(onChainExternalId, "hex")
  );
}
```

This confirms the on-chain credential corresponds to a specific student record without exposing PII.
