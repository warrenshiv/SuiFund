#[test_only]
module suifund::test {
    use sui::test_scenario::{Self as ts, next_tx};
    use sui::coin::{mint_for_testing};
    use sui::sui::{SUI};

    use std::string::{Self, String};
    use std::debug::print;

    use suifund::helpers::init_test_helper;
    use suifund::research_platform::{Self as rp, Platform, PlatformCap};

    const ADMIN: address = @0xe;
    const TEST_ADDRESS1: address = @0xee;
    const TEST_ADDRESS2: address = @0xbb;

   #[test]
    public fun test1() {
        let mut scenario_test = init_test_helper();
        let scenario = &mut scenario_test;

        // set platfrom shared object  
        next_tx(scenario, TEST_ADDRESS1);
        {
            let mut shared = ts::take_shared<Platform>(scenario);
            let cap = ts::take_from_sender<PlatformCap>(scenario);

            rp::set_platform(&mut shared, &cap, ts::ctx(scenario));

            ts::return_shared(shared);
            ts::return_to_sender(scenario, cap);
        };

        next_tx(scenario, TEST_ADDRESS1);
        {

        };


        ts::end(scenario_test);
    }


}