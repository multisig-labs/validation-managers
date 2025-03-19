// Import OpenZeppelin's MerkleTree from esm.sh
import { StandardMerkleTree } from 'https://esm.sh/@openzeppelin/merkle-tree@1.0.5'

// Main function to generate Merkle Tree and proof from command-line args
async function generateMerkleTreeAndProof() {
  // Get command-line arguments (skip first two: deno run script.ts)
  const args = Deno.args.slice(0)

  if (args.length < 1) {
    console.log('Usage: deno run script.ts <leaf1> <leaf2> <leaf3> ...')
    console.log('Example: deno run script.ts Alice Bob Charlie')
    Deno.exit(1)
  }

  // Prepare leaves as arrays (OpenZeppelin expects [value] or structured data)
  // Here, we'll treat each arg as a single string value
  const leaves = args.map((arg) => [arg])

  // Create a StandardMerkleTree using keccak256 (default in OpenZeppelin)
  const tree = StandardMerkleTree.of(leaves, ['address'])

  // Output the Merkle Root
  console.log('Merkle Root:', tree.root)

  // Generate and output proof for the first leaf as an example
  const firstLeaf = leaves[0]
  const proof = tree.getProof(0) // Proof for the first leaf (index 0)
  console.log(`Proof for "${firstLeaf[0]}":`, proof)

  // Optionally, show the full tree structure
  console.log('Full Tree Dump:', JSON.stringify(tree.dump(), null, 2))

  const v = tree.verifyProof(proof, tree.root, firstLeaf)
  console.log('Proof is valid:', v)
}

// Run the function
if (import.meta.main) {
  await generateMerkleTreeAndProof()
}
