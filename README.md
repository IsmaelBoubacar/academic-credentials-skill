# academic-credentials-skill

> A Claude Code skill for issuing, verifying, and managing academic diplomas as Soulbound Tokens (SBT) on Solana.

Built from production experience at **UDHCertification** — a credential verification system serving 7,000+ students at Université Djibo Hamani de Tahoua (Niger). Winner of 1st Prize at CONCIT 2025.

---

## Problem Solved

Universities in emerging markets face:
- **Diploma fraud** — paper credentials are easily forged
- **Verification cost** — international employers can't easily verify foreign degrees
- **Infrastructure gaps** — no national credential registry, no universal student ID
- **Cost barriers** — Ethereum/Polygon gas fees are prohibitive at scale

This skill enables any institution to deploy a production-grade credential system on Solana at a fraction of the cost.

---

## What's Included

| File | Purpose |
|------|---------|
| `skill/SKILL.md` | Entry point — routes to the right sub-skill based on your task |
| `skill/issuance.md` | Mint diploma SBTs: Token Extensions, Metaplex, cNFTs, Anchor program |
| `skill/verification.md` | Verify credentials: wallet lookup, QR code, batch audit portal |
| `skill/compliance.md` | GDPR, revocation, institutional recognition (UNESCO, Bologna Process) |
| `skill/evm-to-solana.md` | Migrate from Polygon/EVM to Solana — concept map, tooling, cost analysis |

---

## Stack

| Layer | Technology |
|-------|------------|
| SBT standard | Token Extensions `non_transferable` (Token 2022) |
| Rich metadata | Metaplex Token Metadata |
| Batch issuance | Metaplex Bubblegum (cNFT) / ZK-Compression |
| On-chain registry | Anchor 0.31+ |
| Metadata storage | IPFS (Pinata / nft.storage) |
| Frontend | Next.js 15 + @solana/kit |
| Institutional auth | Squads v4 multisig |

---

## Cost Comparison

| Cohort size | Token Extensions | cNFT (Bubblegum) |
|-------------|-----------------|-----------------|
| 10 students | ~0.025 SOL | ~0.00005 SOL |
| 100 students | ~0.25 SOL | ~0.0005 SOL |
| 7,000 students | ~17.5 SOL | ~0.035 SOL |

For a university graduation batch, cNFTs cost less than a cup of coffee.

---

## Installation

```bash
git clone https://github.com/IsmaelBoubacar/academic-credentials-skill
cd academic-credentials-skill
./install.sh
```

This installs the skill to `~/.claude/skills/academic-credentials/`.

---

## Usage (Claude Code)

Once installed, Claude automatically loads the relevant sub-skill:

```
"Issue a diploma SBT for our 2025 Computer Science graduates"
→ Loads issuance.md

"How do I verify a credential by QR code?"
→ Loads verification.md

"We need to comply with GDPR for our EU exchange students"
→ Loads compliance.md

"We have 3,000 Polygon SBTs and want to move to Solana"
→ Loads evm-to-solana.md
```

---

## Real-World Context

UDHCertification was deployed on Polygon mainnet in 2024 for the Université Djibo Hamani de Tahoua — a public university in Niger with 7,000+ students. The system:

- Issues tamper-proof diploma NFTs linked to student wallets
- Provides a public QR-code verification portal
- Operates without a third-party intermediary
- Won 1st Prize at CONCIT 2025 (national technology competition, Niger)

This Solana skill represents the next iteration: lower cost, faster finality, and native SBT support.

---

## License

MIT — see [LICENSE](LICENSE)

---

Submitted to the **Superteam Brazil Solana AI Kit bounty**.  
Maintained by [Ing. Ismael](https://github.com/papyismael) — founder, UDHCertification.
