module suifund::research_platform {
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::linked_table::{Self, LinkedTable};
    use sui::vec_map::{Self, VecMap};
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};

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
    const MAX_REVIEWERS: u64 = 5;
    const REVIEW_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days in seconds

    // ======== Core Structs ========

    struct Platform has key {
        id: UID,
        admin: address,
        treasury: Balance<SUI>,
        proposals: LinkedTable<ID, ResearchProposal>,
        researchers: Table<address, ResearcherProfile>,
        reviewers: Table<address, ReviewerProfile>,
        governance_config: GovernanceConfig,
        impact_metrics: GlobalMetrics
    }

    struct ResearchProposal has store {
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

    struct ResearcherProfile has store {
        reputation_score: u64,
        completed_projects: vector<ID>,
        active_projects: vector<ID>,
        total_funding_received: u64,
        citations: u64,
        stake: Balance<SUI>
    }

    struct ReviewerProfile has store {
        expertise_areas: vector<String>,
        reviews_completed: u64,
        stake: Balance<SUI>,
        reputation_score: u64,
        review_quality_score: u64
    }

    struct Milestone has store {
        description: String,
        required_funding: u64,
        deadline: u64,
        verification_method: VerificationMethod,
        status: MilestoneStatus,
        validators: vector<address>,
        proof_submissions: vector<ProofSubmission>
    }

    struct Review has store {
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

    struct ProofOfReproduction has store {
        validator: address,
        timestamp: u64,
        methodology_hash: vector<u8>,
        results_hash: vector<u8>,
        verification_data: vector<u8>,
        status: VerificationStatus
    }

    struct Timeline has store {
        created_at: u64,
        review_deadline: u64,
        funding_deadline: u64,
        estimated_completion: u64,
        actual_completion: Option<u64>
    }

    struct ImpactMetrics has store {
        citations: u64,
        industry_applications: u64,
        derived_works: vector<ID>,
        social_impact_score: u64,
        commercial_value: u64,
        reproducibility_score: u64
    }

    struct GlobalMetrics has store {
        total_proposals: u64,
        total_funding: u64,
        active_researchers: u64,
        successful_projects: u64,
        total_citations: u64,
        platform_reputation: u64
    }

    struct GovernanceConfig has store {
        min_stake_amount: u64,
        review_period: u64,
        fee_percentage: u64,
        quadratic_funding_pool: Balance<SUI>,
        governance_token_supply: u64
    }

    // ======== Enums ========

    struct ProposalStage has store {
        value: u8
    }

    struct VerificationMethod has store {
        method_type: u8,
        required_proofs: u8,
        verification_params: vector<u8>
    }

    struct MilestoneStatus has store {
        value: u8
    }

    struct VerificationStatus has store {
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
        ctx: &mut TxContext
    ) {
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
        let proposal = linked_table::borrow_mut(&mut platform.proposals, proposal_id);
        assert!(milestone_index < vector::length(&proposal.milestones), EInvalidMilestone);
        
        let milestone = vector::borrow_mut(&mut proposal.milestones, milestone_index);
        assert!(milestone.status.value == 1, EInvalidState); // Must be in progress
        
        // Verify proof
        assert!(verify_reproduction_proof(&proof), EInvalidProof);
        
        vector::push_back(&mut proposal.reproducibility_proofs, proof);
        milestone.status.value = 2; // Completed
        
        // Release funding if available
        if (balance::value(&proposal.current_funding) >= milestone.required_funding) {
            // Implementation for funding release
            // This would involve complex logic for fund distribution
        };
    }

    // ======== Helper Functions ========

    fun create_default_governance_config(ctx: &mut TxContext): GovernanceConfig {
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

    fun create_researcher_profile(stake: Coin<SUI>, ctx: &mut TxContext): ResearcherProfile {
        ResearcherProfile {
            reputation_score: 0,
            completed_projects: vector::empty(),
            active_projects: vector::empty(),
            total_funding_received: 0,
            citations: 0,
            stake: coin::into_balance(stake)
        }
    }

    fun create_reviewer_profile(stake: Coin<SUI>, ctx: &mut TxContext): ReviewerProfile {
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
        // Implementation for verification logic
        // This would involve cryptographic verification
        true // Placeholder
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}