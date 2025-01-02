mod common;
use anyhow::Result;
use borsh::BorshDeserialize;
use chicken::{
    actions::{bps, InitializePoolArgs},
    state::{Pool, PoolMode, UserPosition},
};
use common::*;
use litesvm_token::spl_token::{self, solana_program};
use solana_sdk::program_pack::Pack;

#[test_log::test]
fn test_withdraw_single_user_last_out_winner() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500, // 5%
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);
    let deposit_amount = 1000000000000000;
    let (user, user_ata) = setup_user(&mut ctx, deposit_amount)?;
    let user_position_key = deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user,
        deposit_amount,
    )?;

    // Get initial balances
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    let deposit_fee = bps(deposit_amount, pool.deposit_fee_bps)?;
    let deposit_less_fee = deposit_amount - deposit_fee;
    let withdraw_fee = bps(deposit_less_fee, pool.withdraw_fee_bps)?;
    let amount_returned = deposit_less_fee - withdraw_fee;
    let fees = deposit_fee + withdraw_fee;
    // Withdraw phase
    ctx.svm.warp_to_slot(current_clock + 900);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user)?;
    let user_position = ctx.svm.get_account(&user_position_key).unwrap();
    assert_eq!(user_position.data, [0; 90]);

    // Verify final balances
    let pool_ata_account = ctx.svm.get_account(&ctx.pool_ata).unwrap();
    let pool_ata = spl_token::state::Account::unpack(&pool_ata_account.data).unwrap();
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    // Pool should only have fees
    assert_eq!(pool_ata.amount, fees);
    assert_eq!(pool.fee_amount, fees);
    // User should get back their deposit + collateral (since they're last out)
    assert_eq!(user_ata.amount, amount_returned);

    Ok(())
}

#[test_log::test]
fn test_withdraw_multi_user_first_out_loser() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,

        pool_mode: PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500, // 5%
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);

    // First user deposits
    let deposit_amount_1 = 10000000;
    let (user1, user1_ata) = setup_user(&mut ctx, deposit_amount_1)?;
    let user1_position_key = deposit_logs(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user1,
        deposit_amount_1,
        false,
    )?;

    // Second user deposits
    let deposit_amount_2 = 20000000;
    let (user2, user2_ata) = setup_user(&mut ctx, deposit_amount_2)?;
    let user2_position_key = deposit_logs(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user2,
        deposit_amount_2,
        false,
    )?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    let deposit_fee_1 = chicken::actions::bps(deposit_amount_1, pool.deposit_fee_bps).unwrap();
    let deposit_less_fee_1 = deposit_amount_1 - deposit_fee_1;
    let collateral_1 = chicken::actions::bps(deposit_less_fee_1, pool.collateral_bps).unwrap();
    let withdraw_fee_1 =
        chicken::actions::bps(deposit_less_fee_1 - collateral_1, pool.withdraw_fee_bps).unwrap();
    let return_amount_1 = deposit_less_fee_1 - withdraw_fee_1 - collateral_1;
    let deposit_fee_2 = chicken::actions::bps(deposit_amount_2, pool.deposit_fee_bps).unwrap();
    let deposit_less_fee_2 = deposit_amount_2 - deposit_fee_2;
    let collateral_2 = chicken::actions::bps(deposit_less_fee_2, pool.collateral_bps).unwrap();
    let withdraw_fee_2 =
        chicken::actions::bps(deposit_less_fee_2 + collateral_1, pool.withdraw_fee_bps).unwrap();
    let return_amount_2 = deposit_less_fee_2 + collateral_1 - withdraw_fee_2;
    assert_eq!(pool.collateral_amount, collateral_1 + collateral_2);
    // First user withdraws (should lose collateral)
    ctx.svm.warp_to_slot(current_clock + 500);
    let user1_position = ctx.svm.get_account(&user1_position_key).unwrap();
    let user1_position = UserPosition::deserialize(&mut &user1_position.data[..]).unwrap();
    assert_eq!(user1_position.collateral_amount, collateral_1);
    assert_eq!(
        user1_position.deposit_amount,
        deposit_less_fee_1 - collateral_1
    );
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user1)?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    assert_eq!(pool.collateral_amount, collateral_1 + collateral_2);
    assert_eq!(pool.withdrawn, return_amount_1);
    assert_eq!(
        pool.fee_amount,
        deposit_fee_1 + deposit_fee_2 + withdraw_fee_1
    );
    let user1_ata_account = ctx.svm.get_account(&user1_ata).unwrap();
    let user1_ata = spl_token::state::Account::unpack(&user1_ata_account.data).unwrap();
    // Calculate expected amount (deposit minus fees minus collateral)
    assert_eq!(user1_ata.amount, return_amount_1);
    // Second user withdraws (should get their collateral back plus first user's collateral)
    ctx.svm.warp_to_slot(current_clock + 600);
    let user2_position = ctx.svm.get_account(&user2_position_key).unwrap();
    let user2_position = UserPosition::deserialize(&mut &user2_position.data[..]).unwrap();
    assert_eq!(user2_position.collateral_amount, collateral_2);
    assert_eq!(
        user2_position.deposit_amount,
        deposit_less_fee_2 - collateral_2
    );
    withdraw_logs(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user2, false)?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    let user2_ata_account = ctx.svm.get_account(&user2_ata).unwrap();
    let user2_ata = spl_token::state::Account::unpack(&user2_ata_account.data).unwrap();
    // Calculate expected amount (deposit plus first user's collateral and their collateral minus fees)
    assert_eq!(pool.collateral_amount, 0);
    assert_eq!(user2_ata.amount, return_amount_2);
    let pool_ata_account = ctx.svm.get_account(&ctx.pool_ata).unwrap();
    let pool_ata = spl_token::state::Account::unpack(&pool_ata_account.data).unwrap();
    assert_eq!(
        pool.fee_amount,
        deposit_fee_1 + deposit_fee_2 + withdraw_fee_1 + withdraw_fee_2
    );
    assert_eq!(pool_ata.amount, pool.fee_amount);
    Ok(())
}

#[test_log::test]
fn test_withdraw_multi_user_last_out_winner() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);

    // Setup three users
    let deposit_amount = 1000;
    let (user1, user1_ata) = setup_user(&mut ctx, deposit_amount)?;
    let (user2, user2_ata) = setup_user(&mut ctx, deposit_amount)?;
    let (user3, user3_ata) = setup_user(&mut ctx, deposit_amount)?;

    // All users deposit
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user1,
        deposit_amount,
    )?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user2,
        deposit_amount,
    )?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user3,
        deposit_amount,
    )?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    // First user withdraws (loses collateral)
    ctx.svm.warp_to_slot(current_clock + 500);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user1)?;

    // Second user withdraws (loses collateral)
    ctx.svm.warp_to_slot(current_clock + 600);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user2)?;

    // Last user withdraws (gets all collateral)
    ctx.svm.warp_to_slot(current_clock + 700);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user3)?;

    // Check final balances
    let user1_ata_account = ctx.svm.get_account(&user1_ata).unwrap();
    let user1_ata = spl_token::state::Account::unpack(&user1_ata_account.data).unwrap();
    let user2_ata_account = ctx.svm.get_account(&user2_ata).unwrap();
    let user2_ata = spl_token::state::Account::unpack(&user2_ata_account.data).unwrap();
    let user3_ata_account = ctx.svm.get_account(&user3_ata).unwrap();
    let user3_ata = spl_token::state::Account::unpack(&user3_ata_account.data).unwrap();

    // Calculate expected amounts
    let deposit_fee = chicken::actions::bps(deposit_amount, pool.deposit_fee_bps).unwrap();
    let collateral =
        chicken::actions::bps(deposit_amount - deposit_fee, pool.collateral_bps).unwrap();
    let deposit_loser = deposit_amount - deposit_fee - collateral;
    let withdraw_loser_fee = chicken::actions::bps(deposit_loser, pool.withdraw_fee_bps).unwrap();
    let return_amount_loser = deposit_loser - withdraw_loser_fee;

    let deposit_winner = deposit_amount - deposit_fee + collateral * 2;
    let withdraw_winner_fee = chicken::actions::bps(deposit_winner, pool.withdraw_fee_bps).unwrap();
    let return_amount_winner = deposit_winner - withdraw_winner_fee;

    // First two users should get deposit minus fee minus collateral
    assert_eq!(user1_ata.amount, return_amount_loser);
    assert_eq!(user2_ata.amount, return_amount_loser);
    // Last user should get deposit plus both collaterals
    assert_eq!(user3_ata.amount, return_amount_winner);
    Ok(())
}

#[ignore]
#[test_log::test]
fn test_withdraw_time_based_early_withdrawal() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let start_time = current_clock + 10;
    let end_time = current_clock + 1010;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: PoolMode::TimeBased,
        start_time,
        end_time,
        minimum_deposit: 0,
        collateral_bps: 500, // 5%
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    let deposit_time = current_clock + 11;
    ctx.svm.warp_to_slot(deposit_time);

    let deposit_amount = 10000000;
    let (user, user_ata) = setup_user(&mut ctx, deposit_amount)?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user,
        deposit_amount,
    )?;
    println!("deposit amount: {}", deposit_amount);

    // Early withdrawal (25% through the pool duration)
    let withdrawal_time = current_clock + 260; // ~25% of duration
    ctx.svm.warp_to_slot(withdrawal_time);
    withdraw_logs(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user, true)?;
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();
    let deposit_fee = chicken::actions::bps(deposit_amount, pool.deposit_fee_bps).unwrap();
    let deposit_less_fee = deposit_amount - deposit_fee;
    let total_collateral = chicken::actions::bps(deposit_less_fee, pool.collateral_bps).unwrap();
    let total_duration = end_time - start_time;
    let slots_passed = withdrawal_time - start_time;
    let time_in_pool = ((deposit_time - start_time + slots_passed) * 100) / total_duration;
    let time_percentage = (time_in_pool.pow(3)) / 10_000;
    let penalty_percentage = 100u64.saturating_sub(time_percentage);
    let penalty = (total_collateral * penalty_percentage) / 100;
    let reward_percentage = (time_in_pool.pow(2)) / 100;
    let rewards = (total_collateral * reward_percentage) / 100;
    println!("collateral_penalty {}", penalty);

    let refund = total_collateral - penalty;
    println!("collateral_refund {}", refund);
    println!("rewards {}", rewards);
    println!("penalty_percentage {}", penalty_percentage);
    println!("reward_percentage {}", reward_percentage);
    println!("time_percentage {}", time_percentage);
    println!("time_in_pool {}", time_in_pool);

    // Final collateral return is: total_collateral - penalty + rewards
    let collateral_return = total_collateral
        .saturating_sub(penalty)
        .saturating_add(rewards);
    let withdraw_fee = chicken::actions::bps(
        deposit_amount - deposit_fee + collateral_return,
        pool.withdraw_fee_bps,
    )
    .unwrap();

    assert_eq!(
        user_ata.amount,
        deposit_amount + collateral_return - deposit_fee - withdraw_fee
    );
    Ok(())
}

#[ignore]
#[test_log::test]
fn test_withdraw_time_based_full_duration() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,

        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);
    let deposit_amount = 1000;
    let (user, user_ata) = setup_user(&mut ctx, deposit_amount)?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user,
        deposit_amount,
    )?;

    // Full duration withdrawal
    ctx.svm.warp_to_slot(current_clock + 1001);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user)?;

    // Check final balances
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();

    // User should get back full amount including collateral
    let fee = chicken::actions::bps(deposit_amount, 0).unwrap();
    assert_eq!(user_ata.amount, deposit_amount - fee);

    Ok(())
}

#[ignore]
#[test_log::test]
fn test_withdraw_time_based_multiple_users() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,

        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);
    let deposit_amount = 1000;

    // Setup three users
    let (user1, user1_ata) = setup_user(&mut ctx, deposit_amount)?;
    let (user2, user2_ata) = setup_user(&mut ctx, deposit_amount)?;
    let (user3, user3_ata) = setup_user(&mut ctx, deposit_amount)?;

    // All users deposit
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user1,
        deposit_amount,
    )?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user2,
        deposit_amount,
    )?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user3,
        deposit_amount,
    )?;

    // User 1 withdraws at 25% duration
    ctx.svm.warp_to_slot(current_clock + 250);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user1)?;

    // User 2 withdraws at 75% duration
    ctx.svm.warp_to_slot(current_clock + 750);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user2)?;

    // User 3 withdraws after full duration
    ctx.svm.warp_to_slot(current_clock + 1001);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user3)?;

    // Check final balances
    let user1_ata_account = ctx.svm.get_account(&user1_ata).unwrap();
    let user1_ata = spl_token::state::Account::unpack(&user1_ata_account.data).unwrap();
    let user2_ata_account = ctx.svm.get_account(&user2_ata).unwrap();
    let user2_ata = spl_token::state::Account::unpack(&user2_ata_account.data).unwrap();
    let user3_ata_account = ctx.svm.get_account(&user3_ata).unwrap();
    let user3_ata = spl_token::state::Account::unpack(&user3_ata_account.data).unwrap();

    // Calculate expected amounts
    let fee = chicken::actions::bps(deposit_amount, 0).unwrap();
    let total_collateral = chicken::actions::bps(deposit_amount - fee, 500).unwrap();

    // User 1 should get 25% of collateral
    let user1_collateral_return = total_collateral * 25 / 100;
    assert_eq!(
        user1_ata.amount,
        deposit_amount - fee - total_collateral + user1_collateral_return
    );

    // User 2 should get 75% of collateral
    let user2_collateral_return = total_collateral * 75 / 100;
    assert_eq!(
        user2_ata.amount,
        deposit_amount - fee - total_collateral + user2_collateral_return
    );

    // User 3 should get full amount back
    assert_eq!(user3_ata.amount, deposit_amount - fee);

    Ok(())
}

#[ignore]
#[test_log::test]
fn test_withdraw_time_based_exact_halfway() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,

        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);
    let deposit_amount = 1000;
    let (user, user_ata) = setup_user(&mut ctx, deposit_amount)?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user,
        deposit_amount,
    )?;

    // Withdraw exactly halfway through
    ctx.svm.warp_to_slot(current_clock + 505); // 50% of duration
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user)?;

    // Check final balance
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();

    // Calculate expected amount (should get exactly 50% of collateral back)
    let fee = chicken::actions::bps(deposit_amount, 0).unwrap();
    let total_collateral = chicken::actions::bps(deposit_amount - fee, 500).unwrap();
    let collateral_return = total_collateral * 50 / 100;

    assert_eq!(
        user_ata.amount,
        deposit_amount - fee - total_collateral + collateral_return
    );

    Ok(())
}
