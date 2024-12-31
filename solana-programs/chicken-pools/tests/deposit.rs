mod common;
use anyhow::Result;
use borsh::BorshDeserialize;
use chicken::{actions::InitializePoolArgs, state::Pool};
use common::*;
use litesvm_token::spl_token::{self, solana_program};
use solana_sdk::{program_pack::Pack, pubkey::Pubkey, signer::Signer};

#[test_log::test]
fn test_deposit_many() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;
    let number_of_users = 10;
    let mut total_deposited = 0;
    let mut fee_amount = 0;
    let mut collateral_amount = 0;
    ctx.svm.warp_to_slot(current_clock + 11);
    for _ in 0..number_of_users {
        let random = rand::random::<u32>() as u64;
        let (user, _) = setup_user(&mut ctx, random)?;
        let user_position_key = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user, random)?;
        let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
        let pool = Pool::deserialize(&mut &pool.data[..]).unwrap();
        let user_position_account = ctx.svm.get_account(&user_position_key).unwrap();
        println!("{:?}", &mut &user_position_account.data[..]);
        let user_position =
            chicken::state::UserPosition::deserialize(&mut &user_position_account.data[..])
                .unwrap();

        let fee = chicken::actions::bps(random, pool.deposit_fee_bps).unwrap();
        let collateral = chicken::actions::bps(random - fee, pool.collateral_bps).unwrap();
        let deposit_amount = random - fee - collateral;

        assert_eq!(user_position.deposit_amount, deposit_amount);
        assert_eq!(user_position.collateral_amount, collateral);
        total_deposited += deposit_amount;
        fee_amount += fee;
        collateral_amount += collateral;
    }

    let pool_account = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let pool = Pool::deserialize(&mut &pool_account.data[..]).unwrap();
    let pool_ata_account = ctx.svm.get_account(&ctx.pool_ata).unwrap();
    let pool_ata_obj = spl_token::state::Account::unpack(&pool_ata_account.data).unwrap();

    assert_eq!(pool.collateral_amount, collateral_amount);
    assert_eq!(pool.fee_amount, fee_amount);
    assert_eq!(
        pool_ata_obj.amount,
        total_deposited + fee_amount + collateral_amount
    );
    Ok(())
}

#[test_log::test]
fn test_deposit_pool_not_started() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: current_clock + 100,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    let amount = 1000;
    let (user, user_ata) = setup_user(&mut ctx, amount)?;
    let result = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user, amount);
    assert!(result.unwrap_err().to_string().contains("PoolPending"));
    Ok(())
}

#[test_log::test]
fn test_deposit_pool_ended() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_slot = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;

    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: current_slot + 1,
        end_time: current_slot + 10,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    let amount = 1000;
    let (user, user_ata) = setup_user(&mut ctx, amount)?;
    let (user2, user2_ata) = setup_user(&mut ctx, amount)?;
    ctx.svm.warp_to_slot(current_slot + 1);
    let result = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user, amount);
    assert!(result.is_ok());
    ctx.svm.warp_to_slot(current_slot + 100);
    let result2 = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user2, amount);
    assert!(result2.unwrap_err().to_string().contains("PoolEnded"));
    Ok(())
}

// #[test_log::test]
// fn test_deposit_pool_removed() -> Result<()> {
//     let mut ctx = setup_test_context()?;
//     let args = InitializePoolArgs {
//         pool_id: [0; 16],
//         pool_mode: chicken::state::PoolMode::LastOutWinner,
//         start_time: 0,
//         end_time: 100,
//         minimum_deposit: 0,
//         collateral_bps: 500,
//         max_deposit: None,
//         total_deposit_limit: None,
//     };
//     setup_pool(&mut ctx, &args)?;

//     let amount = 1000;
//     let (user, user_ata) = setup_user(&mut ctx, amount)?;

//     remove_pool(&mut ctx)?;

//     let result = deposit(
//         &mut ctx.svm,
//         &ctx.mint,
//         &ctx.pool_key,
//         &ctx.pool_ata,
//         &user,
//         &user_ata,
//         amount,
//     );
//     assert!(result.unwrap_err().to_string().contains("Pool has been Removed"));
//     Ok(())
// }

#[test_log::test]
fn test_deposit_below_minimum() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: 100,
        end_time: 200,
        minimum_deposit: 1000,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;
    let amount = 500; // Try to deposit less than minimum
    let (user, user_ata) = setup_user(&mut ctx, amount)?;

    let result = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user, amount);
    assert!(result.is_err());
    Ok(())
}

#[test_log::test]
fn test_deposit_above_limit() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let id = [0; 16];
    let (pkey, bump) = Pubkey::find_program_address(
        &[
            b"pool".as_ref(),
            [0; 16].as_ref(),
            ctx.creator.pubkey().as_ref(),
        ],
        &Pubkey::from(chicken::ID),
    );
    let args = InitializePoolArgs {
        pool_id: id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: 0,
        end_time: 100,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: Some(1000),
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args)?;

    let amount = 2000; // Try to deposit more than limit
    let (user, user_ata) = setup_user(&mut ctx, amount)?;

    let result = deposit(&mut ctx.svm, &ctx.mint, &pkey, &user, amount);
    assert!(result.is_err());
    Ok(())
}

#[test_log::test]
fn test_deposit_above_total_limit() -> Result<()> {
    let mut ctx = setup_test_context()?;
    let current_clock = ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: current_clock + 10,
        end_time: current_clock + 1000,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: Some(5000), // Set total deposit limit
    };
    setup_pool(&mut ctx, args)?;

    ctx.svm.warp_to_slot(current_clock + 11);

    // First user deposits 3000
    let amount1 = 3000;
    let (user1, user1_ata) = setup_user(&mut ctx, amount1)?;
    let result1 = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user1, amount1);
    assert!(result1.is_ok());

    // Second user deposits 1500
    let amount2 = 1500;
    let (user2, user2_ata) = setup_user(&mut ctx, amount2)?;
    let result2 = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user2, amount2);
    assert!(result2.is_ok());

    // Third user tries to deposit 2000, which would exceed the total limit
    let amount3 = 2000;
    let (user3, user3_ata) = setup_user(&mut ctx, amount3)?;
    let result3 = deposit(&mut ctx.svm, &ctx.mint, &ctx.pool_key, &user3, amount3);

    assert!(result3
        .unwrap_err()
        .to_string()
        .contains("PoolDepositLimitExceeded"));
    Ok(())
}
