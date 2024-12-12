mod common;
use anyhow::Result;
use borsh::BorshDeserialize;
use chicken::{
    actions::{bps, InitializePoolArgs},
    state::{Pool, PoolMode, UserPosition},
};
use common::*;
use litesvm_token::spl_token;
use solana_sdk::program_pack::Pack;

#[test_log::test]
fn test_withdraw_single_user_last_out_winner() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500, // 5%
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);
    let deposit_amount = 1000;
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
    let pool = Pool::deserialize(&mut &pool.data[8..]).unwrap();
    let user_position = ctx.svm.get_account(&user_position_key).unwrap();
    let user_position = UserPosition::deserialize(&mut &user_position.data[8..]).unwrap();

    let amount_rerutned =
        user_position.deposit_amount - (bps(user_position.deposit_amount, pool.withdraw_fee_bps)?);
    let fees = bps(user_position.deposit_amount, pool.withdraw_fee_bps)?
        + bps(user_position.deposit_amount, pool.deposit_fee_bps)?;
    // Withdraw phase
    ctx.svm.warp_to_slot(current_clock + 900);
    withdraw(&mut ctx.svm, &ctx.pool_key, &ctx.mint, &user)?;

    // Verify final balances
    let pool_ata_account = ctx.svm.get_account(&ctx.pool_ata).unwrap();
    let pool_ata = spl_token::state::Account::unpack(&pool_ata_account.data).unwrap();
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();

    // User should get back their deposit + collateral (since they're last out)
    assert_eq!(user_ata.amount, amount_rerutned);
    // Pool should only have fees
    assert_eq!(pool_ata.amount,fees);
    assert_eq!(pool.fee_amount, fees);

    Ok(())
}

#[test_log::test]
fn test_withdraw_multi_user_first_out_loser() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500, // 5%
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

    // Deposit phase
    ctx.svm.warp_to_slot(current_clock + 11);

    // First user deposits
    let deposit_amount_1 = 1000;
    let (user1, user1_ata) = setup_user(&mut ctx, deposit_amount_1)?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user1,
        deposit_amount_1,
    )?;

    // Second user deposits
    let deposit_amount_2 = 2000;
    let (user2, user2_ata) = setup_user(&mut ctx, deposit_amount_2)?;
    deposit(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.pool_key,
        &user2,
        deposit_amount_2,
    )?;

    // First user withdraws (should lose collateral)
    ctx.svm.warp_to_slot(current_clock + 500);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user1
    )?;

    let user1_ata_account = ctx.svm.get_account(&user1_ata).unwrap();
    let user1_ata = spl_token::state::Account::unpack(&user1_ata_account.data).unwrap();

    // Calculate expected amount (deposit minus fee minus collateral)
    let fee_1 = chicken::actions::bps(deposit_amount_1, 0).unwrap(); // Assuming 0 fee bps
    let collateral_1 = chicken::actions::bps(deposit_amount_1 - fee_1, 500).unwrap();
    assert_eq!(user1_ata.amount, deposit_amount_1 - fee_1 - collateral_1);

    // Second user withdraws (should get their collateral back plus first user's collateral)
    ctx.svm.warp_to_slot(current_clock + 600);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user2
    )?;

    let user2_ata_account = ctx.svm.get_account(&user2_ata).unwrap();
    let user2_ata = spl_token::state::Account::unpack(&user2_ata_account.data).unwrap();

    // Calculate expected amount (deposit plus first user's collateral)
    let fee_2 = chicken::actions::bps(deposit_amount_2, 0).unwrap();
    let collateral_2 = chicken::actions::bps(deposit_amount_2 - fee_2, 500).unwrap();
    assert_eq!(user2_ata.amount, deposit_amount_2 - fee_2 + collateral_1);

    Ok(())
}

#[test_log::test]
fn test_withdraw_multi_user_last_out_winner() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

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

    // First user withdraws (loses collateral)
    ctx.svm.warp_to_slot(current_clock + 500);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user1
    )?;

    // Second user withdraws (loses collateral)
    ctx.svm.warp_to_slot(current_clock + 600);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user2
    )?;

    // Last user withdraws (gets all collateral)
    ctx.svm.warp_to_slot(current_clock + 700);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user3
    )?;

    // Check final balances
    let user1_ata_account = ctx.svm.get_account(&user1_ata).unwrap();
    let user1_ata = spl_token::state::Account::unpack(&user1_ata_account.data).unwrap();
    let user2_ata_account = ctx.svm.get_account(&user2_ata).unwrap();
    let user2_ata = spl_token::state::Account::unpack(&user2_ata_account.data).unwrap();
    let user3_ata_account = ctx.svm.get_account(&user3_ata).unwrap();
    let user3_ata = spl_token::state::Account::unpack(&user3_ata_account.data).unwrap();

    // Calculate expected amounts
    let fee = chicken::actions::bps(deposit_amount, 0).unwrap();
    let collateral = chicken::actions::bps(deposit_amount - fee, 500).unwrap();

    // First two users should get deposit minus fee minus collateral
    assert_eq!(user1_ata.amount, deposit_amount - fee - collateral);
    assert_eq!(user2_ata.amount, deposit_amount - fee - collateral);
    // Last user should get deposit plus both collaterals
    assert_eq!(user3_ata.amount, deposit_amount - fee + (collateral * 2));

    Ok(())
}

#[test_log::test]
fn test_withdraw_time_based_early_withdrawal() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500, // 5%
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

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

    // Early withdrawal (25% through the pool duration)
    let withdrawal_time = current_clock + 250; // 25% of duration
    ctx.svm.warp_to_slot(withdrawal_time);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user
    )?;

    // Check final balances
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();

    // Calculate expected amount
    // User should get back 25% of their collateral based on time elapsed
    let fee = chicken::actions::bps(deposit_amount, 0).unwrap();
    let total_collateral = chicken::actions::bps(deposit_amount - fee, 500).unwrap();
    let collateral_return = total_collateral * 25 / 100; // 25% of collateral

    assert_eq!(
        user_ata.amount,
        deposit_amount - fee - total_collateral + collateral_return
    );

    Ok(())
}

#[test_log::test]
fn test_withdraw_time_based_full_duration() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

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
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user
    )?;

    // Check final balances
    let user_ata_account = ctx.svm.get_account(&user_ata).unwrap();
    let user_ata = spl_token::state::Account::unpack(&user_ata_account.data).unwrap();

    // User should get back full amount including collateral
    let fee = chicken::actions::bps(deposit_amount, 0).unwrap();
    assert_eq!(user_ata.amount, deposit_amount - fee);

    Ok(())
}

#[test_log::test]
fn test_withdraw_time_based_multiple_users() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

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
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user1
    )?;

    // User 2 withdraws at 75% duration
    ctx.svm.warp_to_slot(current_clock + 750);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user2
    )?;

    // User 3 withdraws after full duration
    ctx.svm.warp_to_slot(current_clock + 1001);
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user3
    )?;

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

#[test_log::test]
fn test_withdraw_time_based_exact_halfway() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: PoolMode::TimeBased,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;

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
    withdraw(
        &mut ctx.svm,
        &ctx.pool_key,
        &ctx.mint,
        &user
    )?;

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
