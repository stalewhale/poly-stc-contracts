address 0x2d81a0427d64ff61b11ede9085efa5ad {

module CrossChainData {

    use 0x1::Vector;
    use 0x1::Signer;
    use 0x1::Errors;
    use 0x1::Hash;
    //use 0x1::Debug;

    use 0x2d81a0427d64ff61b11ede9085efa5ad::CrossChainGlobal;
    use 0x2d81a0427d64ff61b11ede9085efa5ad::MerkleProofNonExists;

    const ERR_INITIALIZED_REPEATE: u64 = 101;
    const ERR_PROOF_HASH_INVALID: u64 = 102;
    const ERR_PROOF_ROOT_HASH_INVALID: u64 = 103;

    struct Consensus has key, store {
        //  When Poly chain switches the consensus epoch book keepers, the consensus peers public keys of Poly chain should be 
        //  changed into no-compressed version so that solidity smart contract can convert it to address type and 
        //  verify the signature derived from Poly chain account signature.
        //  ConKeepersPkBytes means Consensus book Keepers Public Key Bytes
        con_keepers_pk_bytes: vector<u8>,

        // CurEpochStartHeight means Current Epoch Start Height of Poly chain block
        cur_epoch_start_height: u64,

        // This index records the current Map length
        eth_to_poly_tx_hash_index: u128,

        /*
         Ethereum cross chain tx hash indexed by the automatically increased index.
         This map exists for the reason that Poly chain can verify the existence of 
         cross chain request tx coming from Ethereum
        */
        eth_to_poly_tx_hash: vector<vector<u8>>
    }

    /// SMT hash root key
    struct SparseMerkleTreeRoot<ChainType> has key, store {
        hash: vector<u8>
    }

    /// This function called from cross chain data
    public fun init_genesis(signer: &signer) {
        let account = Signer::address_of(signer);
        CrossChainGlobal::require_genesis_account(account);

        // repeate check
        assert(!exists<Consensus>(account), Errors::invalid_state(ERR_INITIALIZED_REPEATE));

        move_to(signer, Consensus{
            con_keepers_pk_bytes: Vector::empty<u8>(),
            cur_epoch_start_height: 0,
            eth_to_poly_tx_hash_index: 0,
            eth_to_poly_tx_hash: Vector::empty<vector<u8>>()
        });
    }

    /// Initialize from chain id to struct
    public fun init_txn_exists_proof<ChainType: store>(signer: &signer) {
        let account = Signer::address_of(signer);
        CrossChainGlobal::require_genesis_account(account);
        assert(
            !exists<SparseMerkleTreeRoot<ChainType>>(Signer::address_of(signer)),
            Errors::invalid_state(ERR_INITIALIZED_REPEATE));
        move_to(signer, SparseMerkleTreeRoot<ChainType>{
            hash: *&MerkleProofNonExists::get_place_holder_hash()
        });
    }

    public fun put_cur_epoch_con_pubkey_bytes(bytes: vector<u8>) acquires Consensus {
        let consesus = borrow_global_mut<Consensus>(CrossChainGlobal::genesis_account());
        consesus.con_keepers_pk_bytes = bytes;
    }

    public fun get_cur_epoch_con_pubkey_bytes(): vector<u8> acquires Consensus {
        let consesus = borrow_global<Consensus>(CrossChainGlobal::genesis_account());
        //CrosschainUtils::duplicate_vector<u8>(&consesus.conKeepersPkBytes)
        *&consesus.con_keepers_pk_bytes
    }

    public fun put_cur_epoch_start_height(curEpochStartHeight: u64) acquires Consensus {
        let consesus = borrow_global_mut<Consensus>(CrossChainGlobal::genesis_account());
        consesus.cur_epoch_start_height = curEpochStartHeight;
    }

    public fun get_cur_epoch_start_height(): u64 acquires Consensus {
        let consesus = borrow_global_mut<Consensus>(CrossChainGlobal::genesis_account());
        consesus.cur_epoch_start_height
    }

    // // Store extra data, which may be used in the future
    // public fun putExtraData(bytes32 key1, bytes32 key2, bytes memory value) : bool {
    //     // ExtraData[key1][key2] = value;
    //     // return true;
    // }
    // // Get extra data, which may be used in the future
    // public fun getExtraData(bytes32 key1, bytes32 key2) public view returns (bytes memory) {
    //     // return ExtraData[key1][key2];
    // }

    /// Get current recorded index of cross chain txs requesting from Ethereum to other public chains
    /// in order to help cross chain manager contract differenciate two cross chain tx requests
    public fun get_eth_tx_hash_index(): u128 acquires Consensus {
        let consesus = borrow_global_mut<Consensus>(CrossChainGlobal::genesis_account());
        consesus.eth_to_poly_tx_hash_index
    }

    /// Store Ethereum cross chain tx hash, increase the index record by 1
    public fun put_eth_tx_hash(eth_tx_hash: vector<u8>) acquires Consensus {
        let consesus = borrow_global_mut<Consensus>(CrossChainGlobal::genesis_account());
        consesus.eth_to_poly_tx_hash_index = consesus.eth_to_poly_tx_hash_index + 1;
        Vector::push_back<vector<u8>>(&mut consesus.eth_to_poly_tx_hash, eth_tx_hash);
    }

    /// Get Ethereum cross chain tx hash indexed by ethTxHashIndex
    public fun get_eth_tx_hash(eth_tx_hash_index: u64): vector<u8> acquires Consensus {
        let consesus = borrow_global<Consensus>(CrossChainGlobal::genesis_account());
        let eth_to_poly_hash = Vector::borrow<vector<u8>>(&consesus.eth_to_poly_tx_hash, eth_tx_hash_index);
        *eth_to_poly_hash
    }


    /// Query merkle root hash from data
    public fun get_merkle_root_hash<ChainType: store>(): vector<u8> acquires SparseMerkleTreeRoot {
        let smt = borrow_global<SparseMerkleTreeRoot<ChainType>>(CrossChainGlobal::genesis_account());
        *&smt.hash
    }

    /// Mark from chain tx fromChainTx as exist or processed
    public fun mark_from_chain_tx_exists<ChainType: store>(from_chain_tx: &vector<u8>,
                                                           proof_leaf: &vector<u8>,
                                                           proof_siblings: &vector<vector<u8>>)
    acquires SparseMerkleTreeRoot {
        let smt_root = borrow_global_mut<SparseMerkleTreeRoot<ChainType>>(CrossChainGlobal::genesis_account());
        smt_root.hash = MerkleProofNonExists::update_leaf(&Hash::sha3_256(*from_chain_tx), proof_leaf, proof_siblings);
    }

    /// Check if from chain tx fromChainTx has been processed before
    public fun check_chain_tx_not_exists<ChainType: store>(from_chain_tx: &vector<u8>,
                                                           proof_root: &vector<u8>,
                                                           proof_leaf: &vector<u8>,
                                                           proof_siblings: &vector<vector<u8>>
    ): bool acquires SparseMerkleTreeRoot {
        let smt_root = borrow_global_mut<SparseMerkleTreeRoot<ChainType>>(CrossChainGlobal::genesis_account());
        assert(*&smt_root.hash == *proof_root, Errors::invalid_state(ERR_PROOF_ROOT_HASH_INVALID));
        MerkleProofNonExists::proof_not_exists_in_root(&smt_root.hash, &Hash::sha3_256(*from_chain_tx), proof_leaf, proof_siblings)
    }
}
}