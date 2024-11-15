module suifund::research_platform {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::linked_table::{Self, LinkedTable};
    use sui::vec_map::{Self, VecMap};
    use sui::balance::{Self, Balance}; 
    use std::string::{String};

    // Error codes
    const ENotAuthorized: u64 = 0;
    const EInvalidAmount: u64 = 1;
    const EInvalidState: u64 = 2;
    const EInvalidMilestone: u64 = 3;
    const EInvalidReview: u64 = 4;
    const EInsufficientStake: u64 = 5;
    const EInvalidProof: u64 = 6;
    const EProposalNotFound: u64 = 7;
    const EReviewerConflict: u64 = 8;

    // Platform configuration constants
    const MIN_STAKE_AMOUNT: u64 = 1000;
    const MIN_FUNDING_AMOUNT: u64 = 100;
    // const MAX_REVIEWERS: u64 = 5;
    const REVIEW_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days in seconds

    // ======== Core Structs ========

    public struct Platform has key {
        id: UID,
        admin: address,
        treasury: Balance<SUI>,
        proposals: LinkedTable<ID, ResearchProposal>,
        researchers: Table<address, ResearcherProfile>,
        reviewers: Table<address, ReviewerProfile>,
        governance_config: GovernanceConfig,
        impact_metrics: GlobalMetrics
    }

    public struct ResearchProposal has key, store {
        id: UID,
        researcher: address,
        title: String,
        description: String,
        methodology: String,
        milestones: vector<Milestone>,
        funding_target: u64,
        current_funding: Balance<SUI>,
        stage: ProposalStage,
        reviews: Table<address, Review>,
        timeline: Timeline,
        impact_metrics: ImpactMetrics,
        reproducibility_proofs: vector<ProofOfReproduction>,
        metadata: VecMap<String, String>
    }

    public struct ResearcherProfile has store {
        reputation_score: u64,
        completed_projects: vector<ID>,
        active_projects: vector<ID>,
        total_funding_received: u64,
        citations: u64,
        stake: Balance<SUI>
    }

    public struct ReviewerProfile has store {
        expertise_areas: vector<String>,
        reviews_completed: u64,
        stake: Balance<SUI>,
        reputation_score: u64,
        review_quality_score: u64
    }

    public struct ProofSubmission has store {
    submitter: address,
    timestamp: u64,
    evidence_hash: vector<u8>,
    metadata: VecMap<String, String>,
    status: VerificationStatus
    }

    public struct Milestone has store {
        description: String,
        required_funding: u64,
        deadline: u64,
        verification_method: VerificationMethod,
        status: MilestoneStatus,
        validators: vector<address>,
        proof_submissions: vector<ProofSubmission>
    }

    public struct Review has store {
        reviewer: address,
        timestamp: u64,
        score: u8,
        comments: String,
        methodology_rating: u8,
        feasibility_rating: u8,
        impact_rating: u8,
        stake_amount: u64,
        verified: bool
    }

    public struct ProofOfReproduction has store {
        validator: address,
        timestamp: u64,
        methodology_hash: vector<u8>,
        results_hash: vector<u8>,
        verification_data: vector<u8>,
        status: VerificationStatus
    }

    public struct Timeline has store {
        created_at: u64,
        review_deadline: u64,
        funding_deadline: u64,
        estimated_completion: u64,
        actual_completion: Option<u64>
    }

    public struct ImpactMetrics has store {
        citations: u64,
        industry_applications: u64,
        derived_works: vector<ID>,
        social_impact_score: u64,
        commercial_value: u64,
        reproducibility_score: u64
    }

    public struct GlobalMetrics has store {
        total_proposals: u64,
        total_funding: u64,
        active_researchers: u64,
        successful_projects: u64,
        total_citations: u64,
        platform_reputation: u64
    }

    public struct GovernanceConfig has store {
        min_stake_amount: u64,
        review_period: u64,
        fee_percentage: u64,
        quadratic_funding_pool: Balance<SUI>,
        governance_token_supply: u64
    }

    // ======== Enums ========

    public struct ProposalStage has store {
        value: u8
    }

    public struct VerificationMethod has store {
        method_type: u8,
        required_proofs: u8,
        verification_params: vector<u8>
    }

    public struct MilestoneStatus has store {
        value: u8
    }

    public struct VerificationStatus has store {
        value: u8
    }

    // ======== Core Functions ========

    fun init(ctx: &mut TxContext) {
        let platform = Platform {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            treasury: balance::zero(),
            proposals: linked_table::new(ctx),
            researchers: table::new(ctx),
            reviewers: table::new(ctx),
            governance_config: create_default_governance_config(ctx),
            impact_metrics: create_default_metrics()
        };
        transfer::share_object(platform);
    }

    public fun create_proposal(
        platform: &mut Platform,
        title: String,
        description: String,
        methodology: String,
        funding_target: u64,
        milestones: vector<Milestone>,
        stake: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let researcher = tx_context::sender(ctx);
        
        // Verify minimum stake
        assert!(coin::value(&stake) >= MIN_STAKE_AMOUNT, EInsufficientStake);
        
        let proposal = ResearchProposal {
            id: object::new(ctx),
            researcher,
            title,
            description,
            methodology,
            milestones,
            funding_target,
            current_funding: balance::zero(),
            stage: ProposalStage { value: 0 }, // Initial stage
            reviews: table::new(ctx),
            timeline: create_timeline(ctx),
            impact_metrics: create_default_impact_metrics(),
            reproducibility_proofs: vector::empty(),
            metadata: vec_map::empty()
        };

        // Register researcher if not exists
        if (!table::contains(&platform.researchers, researcher)) {
            table::add(&mut platform.researchers, researcher, create_researcher_profile(stake, ctx));
        };

        linked_table::push_back(&mut platform.proposals, object::id(&proposal), proposal);
    }

    public fun update_proposal(
    platform: &mut Platform,
    proposal_id: ID,
    new_description: String,
    ctx: &mut TxContext
    ) {
        let proposal = linked_table::borrow_mut(&mut platform.proposals, proposal_id);
        let sender = tx_context::sender(ctx);
        
        // Only researcher who created the proposal or admin can update it
        assert!(
            sender == proposal.researcher || sender == platform.admin, 
            ENotAuthorized
        );
        
        proposal.description = new_description;
    }

    public fun get_proposal_details(
    platform: &Platform,
    proposal_id: ID
    ): &ResearchProposal {
        assert!(
            linked_table::contains(&platform.proposals, proposal_id),
            EProposalNotFound
        );
        
        linked_table::borrow(&platform.proposals, proposal_id)
    }

    public fun submit_review(
        platform: &mut Platform,
        proposal_id: ID,
        score: u8,
        comments: String,
        methodology_rating: u8,
        feasibility_rating: u8,
        impact_rating: u8,
        stake: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let reviewer = tx_context::sender(ctx);
        let proposal = linked_table::borrow_mut(&mut platform.proposals, proposal_id);
        
        // Verify reviewer eligibility and stake
        assert!(is_eligible_reviewer(platform, reviewer, proposal), EReviewerConflict);
        assert!(coin::value(&stake) >= MIN_STAKE_AMOUNT, EInsufficientStake);

        // Validate review scores are within acceptable range (e.g., 0-10)
        assert!(
            score <= 10 && 
            methodology_rating <= 10 && 
            feasibility_rating <= 10 && 
            impact_rating <= 10,
            EInvalidReview
        );
        
        let review = Review {
            reviewer,
            timestamp: tx_context::epoch(ctx),
            score,
            comments,
            methodology_rating,
            feasibility_rating,
            impact_rating,
            stake_amount: coin::value(&stake),
            verified: false
        };

        table::add(&mut proposal.reviews, reviewer, review);
        
        // Update reviewer profile
        if (!table::contains(&platform.reviewers, reviewer)) {
            table::add(&mut platform.reviewers, reviewer, create_reviewer_profile(stake, ctx));
        } else {
            let reviewer_profile = table::borrow_mut(&mut platform.reviewers, reviewer);
            reviewer_profile.reviews_completed = reviewer_profile.reviews_completed + 1;
        };
    }

    public fun fund_proposal(
        platform: &mut Platform,
        proposal_id: ID,
        funding: Coin<SUI>,
        _ctx: &mut TxContext
    ) {
        assert!(
        linked_table::contains(&platform.proposals, proposal_id),
        EProposalNotFound);

        let proposal = linked_table::borrow_mut(&mut platform.proposals, proposal_id);
        assert!(proposal.stage.value == 1, EInvalidState); // Must be in funding stage
        
        let amount = coin::value(&funding);
        assert!(amount >= MIN_FUNDING_AMOUNT, EInvalidAmount);
        
        // Calculate platform fee
        let fee = amount * platform.governance_config.fee_percentage / 10000;
        let funding_balance = coin::into_balance(funding);
        let fee_balance = balance::split(&mut funding_balance, fee);
        
        // Add to platform treasury
        balance::join(&mut platform.treasury, fee_balance);
        
        // Add to proposal funding
        balance::join(&mut proposal.current_funding, funding_balance);
        
        // Update metrics
        platform.impact_metrics.total_funding = 
            platform.impact_metrics.total_funding + amount;
    }

    public fun verify_milestone(
        platform: &mut Platform,
        proposal_id: ID,
        milestone_index: u64,
        proof: ProofOfReproduction,
        ctx: &mut TxContext
    ) {
        // Verify proposal exists and get mutable reference
        assert!(linked_table::contains(&platform.proposals, proposal_id), EProposalNotFound);
        let proposal = linked_table::borrow_mut(&mut platform.proposals, proposal_id);
        
        // Verify milestone index is valid
        assert!(milestone_index < vector::length(&proposal.milestones), EInvalidMilestone);
        
        // Verify caller is an authorized validator
        let sender = tx_context::sender(ctx);
        let milestone = vector::borrow_mut(&mut proposal.milestones, milestone_index);
        assert!(vector::contains(&milestone.validators, &sender), ENotAuthorized);
        
        // Verify milestone is in progress
        assert!(milestone.status.value == 1, EInvalidState); // Must be in progress
        
        // Verify proof
        assert!(verify_reproduction_proof(&proof), EInvalidProof);
        
        // Record the proof
        vector::push_back(&mut proposal.reproducibility_proofs, proof);
        
        // Update milestone status
        milestone.status.value = 2; // Completed
        
        // Release funding if available
        if (balance::value(&proposal.current_funding) >= milestone.required_funding) {
            let amount_to_release = milestone.required_funding;
            
            // Split the required funding amount from the proposal's current funding
            let funding_to_release = balance::split(
                &mut proposal.current_funding, 
                amount_to_release
            );
            
            // Get researcher profile
            let researcher_profile = table::borrow_mut(
                &mut platform.researchers, 
                proposal.researcher
            );
            
            // Update researcher metrics
            researcher_profile.total_funding_received = 
                researcher_profile.total_funding_received + amount_to_release;
                
            // Create coin from balance and transfer to researcher
            let payment = coin::from_balance(funding_to_release, ctx);
            transfer::public_transfer(payment, proposal.researcher);
            
            // Update platform metrics
            platform.impact_metrics.successful_projects = 
                platform.impact_metrics.successful_projects + 1;
                
            // Check if this was the final milestone
            let all_completed = true;
            let i = 0;
            while (i < vector::length(&proposal.milestones)) {
                let milestone = vector::borrow(&proposal.milestones, i);
                if (milestone.status.value != 2) { // 2 = Completed
                    all_completed = false;
                    break
                };
                i = i + 1;
            };
            
            // If all milestones are completed, mark the proposal as completed
            if (all_completed) {
                proposal.stage.value = 3; // Completed stage
                proposal.timeline.actual_completion = option::some(tx_context::epoch(ctx));
                
                // Move project from active to completed in researcher's profile
                let researcher_profile = table::borrow_mut(
                    &mut platform.researchers, 
                    proposal.researcher
                );
                
                let project_id = object::id(proposal);
                
                // Remove from active projects
                let i = 0;
                while (i < vector::length(&researcher_profile.active_projects)) {
                    if (vector::borrow(&researcher_profile.active_projects, i) == &project_id) {
                        vector::remove(&mut researcher_profile.active_projects, i);
                        break
                    };
                    i = i + 1;
                };
                
                // Add to completed projects
                vector::push_back(&mut researcher_profile.completed_projects, project_id);
            };
        };
    }

    // ======== Helper Functions ========

    fun create_default_governance_config(_ctx: &mut TxContext): GovernanceConfig {
        GovernanceConfig {
            min_stake_amount: MIN_STAKE_AMOUNT,
            review_period: REVIEW_PERIOD,
            fee_percentage: 250, // 2.5%
            quadratic_funding_pool: balance::zero(),
            governance_token_supply: 1000000000
        }
    }

    fun create_default_metrics(): GlobalMetrics {
        GlobalMetrics {
            total_proposals: 0,
            total_funding: 0,
            active_researchers: 0,
            successful_projects: 0,
            total_citations: 0,
            platform_reputation: 0
        }
    }

    fun create_researcher_profile(stake: Coin<SUI>, _ctx: &mut TxContext): ResearcherProfile {
        ResearcherProfile {
            reputation_score: 0,
            completed_projects: vector::empty(),
            active_projects: vector::empty(),
            total_funding_received: 0,
            citations: 0,
            stake: coin::into_balance(stake)
        }
    }

    fun create_reviewer_profile(stake: Coin<SUI>, _ctx: &mut TxContext): ReviewerProfile {
        ReviewerProfile {
            expertise_areas: vector::empty(),
            reviews_completed: 0,
            stake: coin::into_balance(stake),
            reputation_score: 0,
            review_quality_score: 0
        }
    }

    fun create_timeline(ctx: &mut TxContext): Timeline {
        let now = tx_context::epoch(ctx);
        Timeline {
            created_at: now,
            review_deadline: now + REVIEW_PERIOD,
            funding_deadline: now + (2 * REVIEW_PERIOD),
            estimated_completion: now + (6 * REVIEW_PERIOD),
            actual_completion: option::none()
        }
    }

    fun create_default_impact_metrics(): ImpactMetrics {
        ImpactMetrics {
            citations: 0,
            industry_applications: 0,
            derived_works: vector::empty(),
            social_impact_score: 0,
            commercial_value: 0,
            reproducibility_score: 0
        }
    }

    fun is_eligible_reviewer(
        platform: &Platform,
        reviewer: address,
        proposal: &ResearchProposal
    ): bool {
        reviewer != proposal.researcher &&
        table::contains(&platform.reviewers, reviewer) &&
        !table::contains(&proposal.reviews, reviewer)
    }

    fun verify_reproduction_proof(proof: &ProofOfReproduction): bool {
        // Check proof timestamp is not zero
        assert!(proof.timestamp > 0, EInvalidProof);
        
        // Check that both methodology and results hashes are not empty
        assert!(!vector::is_empty(&proof.methodology_hash), EInvalidProof);
        assert!(!vector::is_empty(&proof.results_hash), EInvalidProof);
        
        // Verify the validator address is not zero address
        assert!(proof.validator != @0x0, EInvalidProof);
        
        // Verify the status is in a valid state (assuming 0 = pending, 1 = verified)
        assert!(proof.status.value <= 1, EInvalidProof);
        
        // Verify proof data existence
        assert!(!vector::is_empty(&proof.verification_data), EInvalidProof);
        
        // Verify data format and structure
        let valid_format = verify_data_format(&proof.verification_data);
        if (!valid_format) {
            return false
        };
        
        // Verify methodology hash matches expected format
        let valid_methodology = verify_hash_format(&proof.methodology_hash);
        if (!valid_methodology) {
            return false
        };
        
        // Verify results hash matches expected format
        let valid_results = verify_hash_format(&proof.results_hash);
        if (!valid_results) {
            return false
        };
        
        // Verify cryptographic proof
        // This would typically involve checking digital signatures or other cryptographic proofs
        let valid_crypto = verify_cryptographic_proof(
            &proof.methodology_hash,
            &proof.results_hash,
            &proof.verification_data
        );
        
        valid_crypto
    }

    // Helper function to verify the format of verification data
    fun verify_data_format(data: &vector<u8>): bool {
        // Minimum length check
        if (vector::length(data) < 32) {
            return false
        };
        
        // Check if data follows expected structure
        // This is a simplified example - adapt based on your specific data format
        let valid = true;
        let i = 0;
        let len = vector::length(data);
        
        while (i < len) {
            let byte = *vector::borrow(data, i);
            // Checking if certain positions contain expected markers
            if (i == 0 && byte != 0x01) { // Example: first byte should be 0x01
                valid = false;
                break
            };
            i = i + 1;
        };
        
        valid
    }

    // Helper function to verify hash format
    fun verify_hash_format(hash: &vector<u8>): bool {
        // Check hash length (assuming SHA-256 hash - 32 bytes)
        if (vector::length(hash) != 32) {
            return false
        };
        
        // Verify hash is not all zeros
        let all_zeros = true;
        let i = 0;
        while (i < 32) {
            if (*vector::borrow(hash, i) != 0) {
                all_zeros = false;
                break
            };
            i = i + 1;
        };
        
        !all_zeros
    }

    // Helper function to verify cryptographic proof
    fun verify_cryptographic_proof(
        methodology_hash: &vector<u8>,
        results_hash: &vector<u8>,
        verification_data: &vector<u8>
    ): bool {
        // Logic to verify the cryptographic proof
        // 1. Verify digital signatures
        // 2. Check hash chains
        // 3. Verify zero-knowledge proofs
        // 4. Check merkle proofs
        
        // Example implementation (simplified):
        let valid = true;
        
        // Verify methodology hash integrity
        if (!verify_hash_integrity(methodology_hash)) {
            valid = false;
        };
        
        // Verify results hash integrity
        if (!verify_hash_integrity(results_hash)) {
            valid = false;
        };
        
        // Verify data relationship
        if (!verify_hash_relationship(methodology_hash, results_hash, verification_data)) {
            valid = false;
        };
        
        valid
    }

    // Helper function to verify hash integrity
    fun verify_hash_integrity(hash: &vector<u8>): bool {
        // Check if hash meets basic cryptographic properties
        if (vector::length(hash) != 32) {
            return false
        };
        
        // Check hash distribution (simplified)
        let zero_count = 0;
        let i = 0;
        while (i < 32) {
            if (*vector::borrow(hash, i) == 0) {
                zero_count = zero_count + 1;
            };
            i = i + 1;
        };
        
        // Arbitrary threshold for demonstration
        zero_count < 16
    }

    // Helper function to verify relationship between hashes
    fun verify_hash_relationship(
        methodology_hash: &vector<u8>,
        results_hash: &vector<u8>,
        verification_data: &vector<u8>
    ): bool {
        // Checking if results_hash can be derived from methodology_hash
        // using verification_data
        
        // Simplified example:
        let data_length = vector::length(verification_data);
        data_length >= 64 && // Minimum length to contain both hashes
        vector::length(methodology_hash) == 32 &&
        vector::length(results_hash) == 32
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}