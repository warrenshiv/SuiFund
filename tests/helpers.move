#[test_only]
module suifund::helpers {
    use sui::test_scenario::{Self as ts};

    const TEST_ADDRESS1: address = @0xee;
    
    use suifund::research_platform::init_for_testing;

    public fun init_test_helper() : ts::Scenario{

       let  mut scenario_val = ts::begin(TEST_ADDRESS1);
        init_for_testing(ts::ctx(&mut scenario_val));       
        scenario_val
    }
}