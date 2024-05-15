// #[test_only]
// module stakingfarmer::farmer_tests {
//     use sui::clock;
//     use sui::clock::Clock;
//     use sui::coin;
//     use sui::sui::SUI;
//     use sui::test_scenario;
//     use sui::test_scenario::next_tx;
//     use sui::test_utils::{assert_eq};
//     use stakingfarmer::farmer::{ Record,reward_per_token, earned, init_for_test, AdminCap};
//     use stakingfarmer::farmer;

//     #[test]
//     fun test_r() {
//         let alice = @0x112233;

//         let mut sc = test_scenario::begin(alice);
//         init_for_test(test_scenario::ctx(&mut sc));

//         next_tx(&mut sc, alice);
//         {

//             let start_time = clock::create_for_testing(test_scenario::ctx(&mut sc));
//             let admin_cap = test_scenario::take_from_address<AdminCap>(&sc, alice);
//             farmer::new_record<SUI>(&admin_cap,1, 1, &start_time, test_scenario::ctx(&mut sc));
//             clock::share_for_testing(start_time);
//             test_scenario::return_to_address(alice, admin_cap);
//         };

//         next_tx(&mut sc, alice);
//         {
//             let clk = test_scenario::take_shared<Clock>(&sc);
//             let mut record = test_scenario::take_shared<Record<SUI>>(&sc);

//             farmer::stake(&mut record, coin::mint_for_testing(10, test_scenario::ctx(&mut sc)), &clk, test_scenario::ctx(&mut sc));
//             let r = reward_per_token(&record, clock::timestamp_ms(&clk));
//             assert_eq(r, 0);
//             assert_eq(earned(&mut record, r, alice), 0);

//             test_scenario::return_shared(record);
//             test_scenario::return_shared(clk);
//         };

//         next_tx(&mut sc, alice);
//         {
//             let mut clk = test_scenario::take_shared<Clock>(&sc);
//             clock::increment_for_testing(&mut clk, 10000);

//             let record = test_scenario::take_shared<Record<SUI>>(&sc);

//             // print(&reward_per_token(&record, clock::timestamp_ms(&clk)));
//             let r  = reward_per_token(&record, clock::timestamp_ms(&clk));
//             assert_eq(r, 1000);

//             test_scenario::return_shared(record);
//             test_scenario::return_shared(clk);
//         };

//         test_scenario::end(sc);
//     }
// }
